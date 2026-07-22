import Foundation
import Observation
import WatchConnectivity

@MainActor
@Observable
final class WatchWorkoutBridge: NSObject, WatchLiveSource, WCSessionDelegate {
    var onEnvelope: ((WatchMetricEnvelope) -> Void)?
    var onEvent: ((WatchWorkoutEventEnvelope) -> Void)?
    var onAcknowledgement: ((WatchWorkoutAcknowledgement) -> Void)?
    var onStatusChange: (() -> Void)?
    private let session: WCSession?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    var isPairedAndInstalled: Bool {
        guard let session else { return false }
        return session.isPaired && session.isWatchAppInstalled
    }
    var isReachable: Bool { session?.isReachable == true }

    func activate() { session?.activate(); onStatusChange?() }

    func send(command: MirroredWorkoutEvent, sessionID: UUID, activity: String) {
        let message: [String: Any] = ["type": "command", "command": command.rawValue, "sessionID": sessionID.uuidString, "activity": activity]
        // Application context is idempotent fallback state; the reachable path
        // adds a prompt acknowledgement without relying on it for delivery.
        try? session?.updateApplicationContext(message)
        if session?.isReachable == true {
            session?.sendMessage(message) { [weak self] reply in
                self?.decode(reply)
            }
        } else {
            session?.transferUserInfo(message)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.onStatusChange?() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.onStatusChange?() }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { decode(message) }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { decode(applicationContext) }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) { decode(userInfo) }

    nonisolated private func decode(_ message: [String: Any]) {
        if let event = WatchMessageDecoder.event(from: message) {
            Task { @MainActor in self.onEvent?(event) }
            return
        }
        if let acknowledgement = WatchMessageDecoder.acknowledgement(from: message) {
            Task { @MainActor in self.onAcknowledgement?(acknowledgement) }
            return
        }
        guard message["type"] as? String == "metric",
              let sessionText = message["sessionID"] as? String,
              let sessionID = UUID(uuidString: sessionText),
              let timestamp = message["timestamp"] as? Double else { return }
        let source = MetricProvenance(source: .appleWatch, sourceName: "Apple Watch", confidence: .measured, coverage: 1, sampledAt: Date(timeIntervalSince1970: timestamp))
        let sample = WorkoutMetricSample(
            timestamp: Date(timeIntervalSince1970: timestamp),
            heartRateBPM: message["heartRate"] as? Double,
            cadence: message["cadence"] as? Double,
            steps: message["steps"] as? Int,
            distanceMeters: message["distanceMeters"] as? Double,
            activeEnergyKcal: message["activeEnergyKcal"] as? Double,
            swimmingStrokeCount: message["strokeCount"] as? Double,
            provenance: source
        )
        let sequence = (message["sequence"] as? NSNumber)?.intValue
        Task { @MainActor in self.onEnvelope?(WatchMetricEnvelope(sessionID: sessionID, sequence: sequence, sample: sample)) }
    }
}
