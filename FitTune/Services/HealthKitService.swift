import Foundation
import HealthKit
import Observation

private final class DailyHealthSampleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [DailyHealthSample] = []

    func append(_ sample: DailyHealthSample) {
        lock.lock()
        values.append(sample)
        lock.unlock()
    }

    func snapshot() -> [DailyHealthSample] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

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
    private var dailyObserverQueries: [HKObserverQuery] = []

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestDailyReadAuthorization() async -> [DailyHealthMetric: Bool] {
        guard isAvailable else {
            return Dictionary(uniqueKeysWithValues: DailyHealthMetric.allCases.map { ($0, false) })
        }
        let identifiers: [HKQuantityTypeIdentifier] = [
            .restingHeartRate, .heartRate, .stepCount, .distanceWalkingRunning,
            .activeEnergyBurned, .bodyMass
        ]
        var readTypes = Set<HKObjectType>(identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
        readTypes.insert(HKObjectType.workoutType())
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { readTypes.insert(sleep) }

        let success: Bool = await withCheckedContinuation { continuation in
            store.requestAuthorization(toShare: [], read: readTypes) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        return Dictionary(uniqueKeysWithValues: DailyHealthMetric.allCases.map { ($0, success) })
    }

    func fetchDailyHealthSamples(
        day: Date,
        timeZone: TimeZone,
        completion: @escaping ([DailyHealthSample]) -> Void
    ) {
        guard isAvailable else { completion([]); return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let group = DispatchGroup()
        let imported = DailyHealthSampleBox()

        let cumulative: [(HKQuantityTypeIdentifier, DailyHealthMetric, HKUnit)] = [
            (.stepCount, .steps, .count()),
            (.distanceWalkingRunning, .walkingDistanceKm, .meterUnit(with: .kilo)),
            (.activeEnergyBurned, .activeEnergyKcal, .kilocalorie())
        ]
        for (identifier, metric, unit) in cumulative {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            group.enter()
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                if let value = statistics?.sumQuantity()?.doubleValue(for: unit) {
                    imported.append(DailyHealthSample(
                        externalID: "healthkit-day:\(metric.rawValue):\(Int(start.timeIntervalSince1970))",
                        metric: metric,
                        value: value,
                        sampleDate: min(.now, end.addingTimeInterval(-1)),
                        updatedAt: .now,
                        source: .appleHealth,
                        sourceName: "Apple 健康"
                    ))
                }
                group.leave()
            }
            store.execute(query)
        }

        if let restingType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            group.enter()
            let query = HKSampleQuery(sampleType: restingType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                for sample in samples as? [HKQuantitySample] ?? [] {
                    let kind = HealthSourceClassifier.classify(
                        sourceName: sample.sourceRevision.source.name,
                        bundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
                        productType: sample.sourceRevision.productType
                    )
                    imported.append(DailyHealthSample(
                        externalID: sample.uuid.uuidString,
                        metric: .restingHeartRate,
                        value: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                        sampleDate: sample.startDate,
                        updatedAt: .now,
                        source: Self.metricSource(for: kind),
                        sourceName: sample.sourceRevision.source.name
                    ))
                }
                group.leave()
            }
            store.execute(query)
        }

        group.notify(queue: .main) { completion(imported.snapshot()) }
    }

    func startDailyObservation(onChange: @escaping () -> Void) {
        stopDailyObservation()
        let observed: [(HKSampleType?, HKUpdateFrequency)] = [
            (HKObjectType.quantityType(forIdentifier: .restingHeartRate), .immediate),
            (HKObjectType.quantityType(forIdentifier: .stepCount), .hourly),
            (HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning), .hourly),
            (HKObjectType.quantityType(forIdentifier: .activeEnergyBurned), .hourly),
            (HKObjectType.workoutType(), .immediate)
        ]
        for (type, frequency) in observed {
            guard let type else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
                onChange()
                completion()
            }
            dailyObserverQueries.append(query)
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: frequency) { _, _ in }
        }
    }

    func stopDailyObservation() {
        dailyObserverQueries.forEach(store.stop)
        dailyObserverQueries.removeAll()
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

    func fetchRecoveryData(completion: @escaping (SleepImportSummary?, [RestingHeartRateSample]) -> Void) {
        guard isAvailable,
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let restingHeartRate = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else {
            state = .failed("此设备暂不支持睡眠或静息心率数据")
            completion(nil, [])
            return
        }
        state = .requesting
        store.requestAuthorization(toShare: [], read: [sleepType, restingHeartRate]) { [weak self] success, error in
            guard success else {
                Task { @MainActor in
                    self?.state = .failed(error?.localizedDescription ?? "未获得恢复数据读取权限")
                    completion(nil, [])
                }
                return
            }
            let now = Date.now
            let sleepStart = Calendar.current.date(byAdding: .hour, value: -36, to: now) ?? now.addingTimeInterval(-129_600)
            let heartRateStart = Calendar.current.date(byAdding: .day, value: -22, to: now) ?? now.addingTimeInterval(-1_900_800)
            let group = DispatchGroup()
            var sleepSummary: SleepImportSummary?
            var heartRates: [RestingHeartRateSample] = []

            group.enter()
            let sleepPredicate = HKQuery.predicateForSamples(withStart: sleepStart, end: now)
            let sleepQuery = HKSampleQuery(sampleType: sleepType, predicate: sleepPredicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let imported = (samples as? [HKCategorySample] ?? []).compactMap(Self.sleepImportSample)
                sleepSummary = imported.isEmpty ? nil : HealthImportMerger.mergeSleep(imported)
                group.leave()
            }
            self?.store.execute(sleepQuery)

            group.enter()
            let heartRatePredicate = HKQuery.predicateForSamples(withStart: heartRateStart, end: now)
            let heartRateQuery = HKSampleQuery(sampleType: restingHeartRate, predicate: heartRatePredicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                heartRates = (samples as? [HKQuantitySample] ?? []).map { sample in
                    let sourceKind = HealthSourceClassifier.classify(
                        sourceName: sample.sourceRevision.source.name,
                        bundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
                        productType: sample.sourceRevision.productType
                    )
                    return RestingHeartRateSample(
                        date: sample.startDate,
                        bpm: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                        source: Self.metricSource(for: sourceKind),
                        sourceName: sample.sourceRevision.source.name,
                        externalID: sample.uuid.uuidString
                    )
                }
                group.leave()
            }
            self?.store.execute(heartRateQuery)

            group.notify(queue: .main) {
                Task { @MainActor in
                    self?.state = .success("已同步睡眠与静息心率")
                    completion(sleepSummary, heartRates)
                }
            }
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

    nonisolated private static func sleepImportSample(_ sample: HKCategorySample) -> SleepImportSample? {
        let stage: SleepStage
        switch sample.value {
        case HKCategoryValueSleepAnalysis.awake.rawValue: stage = .awake
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: stage = .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: stage = .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: stage = .rem
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
             HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: stage = .asleep
        default: stage = .unknown
        }
        guard stage != .unknown else { return nil }
        let source = HealthSourceClassifier.classify(
            sourceName: sample.sourceRevision.source.name,
            bundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
            productType: sample.sourceRevision.productType
        )
        return SleepImportSample(
            externalID: sample.uuid.uuidString,
            start: sample.startDate,
            end: sample.endDate,
            stage: stage,
            source: source
        )
    }

    nonisolated private static func metricSource(for source: HealthSourceKind) -> MetricSource {
        switch source {
        case .appleWatch: .appleWatch
        case .huaweiHealth: .huaweiHealth
        case .other: .appleHealth
        }
    }
}
