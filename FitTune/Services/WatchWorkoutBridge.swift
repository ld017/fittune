import Foundation
import Observation
import WatchConnectivity

@MainActor
@Observable
final class WatchWorkoutBridge: NSObject, WatchLiveSource, WCSessionDelegate {
    var onEnvelope: ((WatchMetricEnvelope) -> Void)?
    var onEvent: ((WatchWorkoutEventEnvelope) -> Void)?
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
        if session?.isReachable == true { session?.sendMessage(message, replyHandler: nil) }
        else { try? session?.updateApplicationContext(message) }
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

    nonisolated private func decode(_ message: [String: Any]) {
        if let event = WatchMessageDecoder.event(from: message) {
            Task { @MainActor in self.onEvent?(event) }
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
        Task { @MainActor in self.onEnvelope?(WatchMetricEnvelope(sessionID: sessionID, sample: sample)) }
    }
}
