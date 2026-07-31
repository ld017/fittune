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
    private(set) var startedAt: Date?
    private var sequence = 0

    override init() {
        super.init()
        if WCSession.isSupported() {
            connectivity = .default
            connectivity?.delegate = self
            connectivity?.activate()
        }
    }

    func start(sessionID: UUID, activity: String) {
        if let currentSessionID = self.sessionID {
            if currentSessionID == sessionID {
                sendAcknowledgement(sessionID: sessionID, accepted: true, reason: "already-started")
            } else {
                sendAcknowledgement(sessionID: sessionID, accepted: false, reason: "另一场训练正在进行")
            }
            return
        }
        self.sessionID = sessionID
        startedAt = .now
        sequence = 0
        let readTypes = [
            HKQuantityType.quantityType(forIdentifier: .heartRate),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        ].compactMap { $0 }
        healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: Set(readTypes)) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                guard success else {
                    self.status = error?.localizedDescription ?? "健康权限不可用"
                    self.sendAcknowledgement(sessionID: sessionID, accepted: false, reason: self.status)
                    self.sessionID = nil
                    self.startedAt = nil
                    return
                }
                self.beginAuthorizedSession(sessionID: sessionID, activity: activity)
            }
        }
    }

    private func beginAuthorizedSession(sessionID: UUID, activity: String) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType(activity)
        let components = activity.split(separator: "|").map(String.init)
        if components.dropFirst().first == "outdoor" {
            configuration.locationType = .outdoor
        } else if components.dropFirst().first == "indoor" {
            configuration.locationType = .indoor
        } else {
            configuration.locationType = [.running, .walking, .cycling, .hiking].contains(configuration.activityType) ? .outdoor : .indoor
        }
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
                    if success {
                        self?.sendAcknowledgement(sessionID: sessionID, accepted: true, reason: "started")
                        self?.sendEvent("started")
                    } else {
                        self?.sendAcknowledgement(sessionID: sessionID, accepted: false, reason: error?.localizedDescription ?? "无法开始采集")
                        self?.sessionID = nil
                        self?.startedAt = nil
                    }
                }
            }
        } catch {
            status = error.localizedDescription
            sendAcknowledgement(sessionID: sessionID, accepted: false, reason: status)
            self.sessionID = nil
            startedAt = nil
        }
    }

    func pause() { workoutSession?.pause(); isPaused = true; sendEvent("paused") }
    func resume() { workoutSession?.resume(); isPaused = false; sendEvent("resumed") }
    func end() {
        let endingSessionID = sessionID
        workoutSession?.end()
        builder?.endCollection(withEnd: .now) { [weak self] _, _ in
            Task { @MainActor in _ = try? await self?.builder?.finishWorkout() }
        }
        isRunning = false; isPaused = false; status = "训练已结束"; sendEvent("ended")
        if let endingSessionID { sendAcknowledgement(sessionID: endingSessionID, accepted: true, reason: "ended") }
        sessionID = nil
        startedAt = nil
        sequence = 0
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {}
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handle(message, replyHandler: replyHandler)
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { handle(applicationContext) }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) { handle(userInfo) }

    nonisolated private func handle(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        guard message["type"] as? String == "command",
              let command = message["command"] as? String,
              let idText = message["sessionID"] as? String,
              let id = UUID(uuidString: idText) else { return }
        let activity = message["activity"] as? String ?? "strength"
        Task { @MainActor in
            let response: [String: Any]
            switch command {
            case "started":
                if let current = self.sessionID, current != id {
                    response = self.acknowledgementMessage(sessionID: id, accepted: false, reason: "另一场训练正在进行")
                } else {
                    self.start(sessionID: id, activity: activity)
                    response = self.acknowledgementMessage(sessionID: id, accepted: true, reason: "start-command-accepted")
                }
            case "paused", "resumed", "ended" where self.sessionID != id:
                response = self.acknowledgementMessage(sessionID: id, accepted: false, reason: "场次不匹配")
            case "paused": self.pause(); response = self.acknowledgementMessage(sessionID: id, accepted: true, reason: "paused")
            case "resumed": self.resume(); response = self.acknowledgementMessage(sessionID: id, accepted: true, reason: "resumed")
            case "ended": self.end(); response = self.acknowledgementMessage(sessionID: id, accepted: true, reason: "ended")
            default: response = self.acknowledgementMessage(sessionID: id, accepted: false, reason: "未知命令")
            }
            replyHandler?(response)
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
        sequence += 1
        var message: [String: Any] = ["type": "metric", "sessionID": sessionID.uuidString, "sequence": sequence, "timestamp": Date().timeIntervalSince1970, "source": "appleWatch"]
        if let heartRate { message["heartRate"] = heartRate }
        if let activeEnergyKcal { message["activeEnergyKcal"] = activeEnergyKcal }
        if let distanceMeters { message["distanceMeters"] = distanceMeters }
        if connectivity?.isReachable == true { connectivity?.sendMessage(message, replyHandler: nil) }
        else { connectivity?.transferUserInfo(message) }
    }

    private func sendEvent(_ event: String) {
        guard let sessionID else { return }
        let message: [String: Any] = ["type": "event", "event": event, "sessionID": sessionID.uuidString]
        if connectivity?.isReachable == true { connectivity?.sendMessage(message, replyHandler: nil) }
        else { connectivity?.transferUserInfo(message) }
    }

    private func sendAcknowledgement(sessionID: UUID, accepted: Bool, reason: String) {
        let message = acknowledgementMessage(sessionID: sessionID, accepted: accepted, reason: reason)
        if connectivity?.isReachable == true { connectivity?.sendMessage(message, replyHandler: nil) }
        else { connectivity?.transferUserInfo(message) }
    }

    private func acknowledgementMessage(sessionID: UUID, accepted: Bool, reason: String) -> [String: Any] {
        [
            "type": "acknowledgement",
            "sessionID": sessionID.uuidString,
            "accepted": accepted,
            "reason": reason,
            "timestamp": Date().timeIntervalSince1970
        ]
    }

    private func activityType(_ text: String) -> HKWorkoutActivityType {
        switch text.split(separator: "|").first.map(String.init) ?? text {
        case "running": .running
        case "briskWalking", "inclineWalking": .walking
        case "cycling": .cycling
        case "swimming": .swimming
        case "rowing": .rowing
        case "stairClimber": .stairClimbing
        case "elliptical": .elliptical
        case "jumpRope": .jumpRope
        case "badminton": .badminton
        case "tableTennis": .tableTennis
        case "soccer": .soccer
        case "climbing": .climbing
        case "hiking": .hiking
        default: .traditionalStrengthTraining
        }
    }
}
