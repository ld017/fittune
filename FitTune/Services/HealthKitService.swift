import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class HealthKitService {
    enum SyncState: Equatable {
        case idle
        case requesting
        case success(String)
        case failed(String)
    }

    var state: SyncState = .idle

    private let store = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func fetchLatestBodyWeight(completion: @escaping (Double?) -> Void) {
        guard isAvailable,
              let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            state = .failed("此设备暂不支持健康数据")
            completion(nil)
            return
        }

        state = .requesting
        let readTypes: Set<HKObjectType> = [bodyMass]
        store.requestAuthorization(toShare: [], read: readTypes) { [weak self] success, error in
            guard success else {
                Task { @MainActor in
                    self?.state = .failed(error?.localizedDescription ?? "未获得体重读取权限")
                    completion(nil)
                }
                return
            }

            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: bodyMass,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { [weak self] _, samples, queryError in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .gramUnit(with: .kilo))
                Task { @MainActor in
                    if let value {
                        self?.state = .success("已同步 \(value.formatted(.number.precision(.fractionLength(1)))) kg")
                    } else {
                        self?.state = .failed(queryError?.localizedDescription ?? "健康中还没有体重记录")
                    }
                    completion(value)
                }
            }
            self?.store.execute(query)
        }
    }

    func fetchTodayWorkoutData(
        weightKg: Double,
        completion: @escaping (Double?, [CardioWorkoutRecord], DailyStepEntry?, [WearableStrengthWorkout]) -> Void
    ) {
        guard isAvailable,
              let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let stepCount = HKObjectType.quantityType(forIdentifier: .stepCount),
              let walkingDistance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
              let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            state = .failed("此设备暂不支持训练数据")
            completion(nil, [], nil, [])
            return
        }

        let workoutType = HKObjectType.workoutType()
        state = .requesting
        store.requestAuthorization(toShare: [], read: [activeEnergy, workoutType, stepCount, walkingDistance, heartRate]) { [weak self] success, error in
            guard success else {
                Task { @MainActor in
                    self?.state = .failed(error?.localizedDescription ?? "未获得训练数据权限")
                    completion(nil, [], nil, [])
                }
                return
            }

            let start = Calendar.current.startOfDay(for: .now)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
            let group = DispatchGroup()
            var totalEnergy: Double?
            var imported: [CardioWorkoutRecord] = []
            var importedStrength: [WearableStrengthWorkout] = []
            var steps = 0
            var distanceKm: Double?

            group.enter()
            let energyQuery = HKStatisticsQuery(quantityType: activeEnergy, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                totalEnergy = result?.sumQuantity()?.doubleValue(for: .kilocalorie())
                group.leave()
            }
            self?.store.execute(energyQuery)

            group.enter()
            let stepQuery = HKStatisticsQuery(quantityType: stepCount, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                steps = Int((result?.sumQuantity()?.doubleValue(for: .count()) ?? 0).rounded())
                group.leave()
            }
            self?.store.execute(stepQuery)

            group.enter()
            let distanceQuery = HKStatisticsQuery(quantityType: walkingDistance, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                distanceKm = result?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo))
                group.leave()
            }
            self?.store.execute(distanceQuery)

            group.enter()
            let workoutQuery = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let workouts = samples as? [HKWorkout] ?? []
                importedStrength = workouts.compactMap { workout in
                    guard workout.workoutActivityType == .traditionalStrengthTraining || workout.workoutActivityType == .functionalStrengthTraining else { return nil }
                    let measured = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                    let averageHR = workout.statistics(for: heartRate)?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    return WearableStrengthWorkout(
                        date: workout.startDate,
                        durationMinutes: max(1, Int(workout.duration / 60)),
                        activeEnergyKcal: measured,
                        averageHeartRate: averageHR,
                        externalID: workout.uuid.uuidString
                    )
                }
                imported = workouts.compactMap { workout in
                    let modality = Self.modality(for: workout.workoutActivityType)
                    guard let modality else { return nil }
                    let minutes = max(1, Int(workout.duration / 60))
                    let measured = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                    let averageHR = workout.statistics(for: heartRate)?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    let intensity: CardioIntensity = (measured ?? 0) / Double(minutes) >= 9 ? .intervals : .zone2
                    return TrainingEngine.makeCardioWorkout(
                        modality: modality,
                        intensity: intensity,
                        minutes: minutes,
                        weightKg: weightKg,
                        distanceKm: workout.totalDistance?.doubleValue(for: .meterUnit(with: .kilo)),
                        averageHeartRate: averageHR,
                        measuredActiveEnergy: measured,
                        source: "Apple Watch / 健康",
                        externalID: workout.uuid.uuidString,
                        date: workout.startDate
                    )
                }
                group.leave()
            }
            self?.store.execute(workoutQuery)

            group.notify(queue: .main) {
                Task { @MainActor in
                    self?.state = .success("已同步今日手表训练")
                    let stepEnergy = (distanceKm.map { 0.5 * weightKg * $0 }) ?? Double(steps) * 0.0004 * weightKg
                    let stepEntry = DailyStepEntry(date: .now, steps: steps, distanceKm: distanceKm, estimatedActiveEnergyKcal: max(0, stepEnergy), source: "Apple Health")
                    completion(totalEnergy, imported, stepEntry, importedStrength)
                }
            }
        }
    }

    nonisolated private static func modality(for activity: HKWorkoutActivityType) -> CardioModality? {
        switch activity {
        case .walking: .briskWalking
        case .hiking: .inclineWalking
        case .stairClimbing: .stairClimber
        case .swimming: .swimming
        case .running: .running
        case .cycling: .cycling
        case .rowing: .rowing
        case .elliptical: .elliptical
        case .jumpRope: .jumpRope
        default: nil
        }
    }
}
