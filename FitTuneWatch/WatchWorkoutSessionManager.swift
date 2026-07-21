import Foundation
import HealthKit
import Observation
import WatchConnectivity

@MainActor
@Observable
final class WatchWorkoutSessionManager: NSObject, WCSessionDelegate, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var connectivity: WCSession?
    private(set) var sessionID: UUID?
    private(set) var heartRate: Double?
    private(set) var activeEnergyKcal: Double?
    private(set) var distanceMeters: Double?
    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var status = "等待 iPhone"

    override init() {
        super.init()
        if WCSession.isSupported() {
            connectivity = .default
            connectivity?.delegate = self
            connectivity?.activate()
        }
    }

    func start(sessionID: UUID, activity: String) {
        guard !isRunning else { return }
        self.sessionID = sessionID
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType(activity)
        configuration.locationType = [.running, .walking, .cycling].contains(configuration.activityType) ? .outdoor : .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            workoutSession = session
            self.builder = builder
            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { [weak self] success, error in
                Task { @MainActor in
                    self?.isRunning = success
                    self?.status = success ? "实时采集中" : (error?.localizedDescription ?? "无法开始")
                }
            }
        } catch { status = error.localizedDescription }
    }

    func pause() { workoutSession?.pause(); isPaused = true; sendEvent("paused") }
    func resume() { workoutSession?.resume(); isPaused = false; sendEvent("resumed") }
    func end() {
        workoutSession?.end()
        builder?.endCollection(withEnd: .now) { [weak self] _, _ in
            Task { @MainActor in self?.builder?.finishWorkout { _, _ in } }
        }
        isRunning = false; isPaused = false; status = "训练已结束"; sendEvent("ended")
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {}
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { handle(applicationContext) }

    nonisolated private func handle(_ message: [String: Any]) {
        guard message["type"] as? String == "command",
              let command = message["command"] as? String,
              let idText = message["sessionID"] as? String,
              let id = UUID(uuidString: idText) else { return }
        let activity = message["activity"] as? String ?? "strength"
        Task { @MainActor in
            switch command {
            case "started": self.start(sessionID: id, activity: activity)
            case "paused": self.pause()
            case "resumed": self.resume()
            case "ended": self.end()
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Task { @MainActor in self.status = error.localizedDescription; self.isRunning = false }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            if let type = HKQuantityType.quantityType(forIdentifier: .heartRate), collectedTypes.contains(type) {
                self.heartRate = workoutBuilder.statistics(for: type)?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }
            if let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned), collectedTypes.contains(type) {
                self.activeEnergyKcal = workoutBuilder.statistics(for: type)?.sumQuantity()?.doubleValue(for: .kilocalorie())
            }
            if let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning), collectedTypes.contains(type) {
                self.distanceMeters = workoutBuilder.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter())
            }
            self.sendMetric()
        }
    }

    private func sendMetric() {
        guard let sessionID else { return }
        var message: [String: Any] = ["type": "metric", "sessionID": sessionID.uuidString, "timestamp": Date().timeIntervalSince1970]
        if let heartRate { message["heartRate"] = heartRate }
        if let activeEnergyKcal { message["activeEnergyKcal"] = activeEnergyKcal }
        if let distanceMeters { message["distanceMeters"] = distanceMeters }
        if connectivity?.isReachable == true { connectivity?.sendMessage(message, replyHandler: nil) }
        else { connectivity?.transferUserInfo(message) }
    }

    private func sendEvent(_ event: String) {
        guard let sessionID else { return }
        let message: [String: Any] = ["type": "event", "event": event, "sessionID": sessionID.uuidString]
        connectivity?.sendMessage(message, replyHandler: nil)
    }

    private func activityType(_ text: String) -> HKWorkoutActivityType {
        switch text {
        case "running": .running
        case "briskWalking", "inclineWalking": .walking
        case "cycling": .cycling
        case "swimming": .swimming
        case "rowing": .rowing
        case "stairClimber": .stairClimbing
        case "elliptical": .elliptical
        case "jumpRope": .jumpRope
        default: .traditionalStrengthTraining
        }
    }
}
