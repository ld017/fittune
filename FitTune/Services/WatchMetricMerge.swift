import Foundation

enum MirroredWorkoutEvent: String, Codable, Equatable, Hashable {
    case started
    case paused
    case resumed
    case ended
}

struct WatchMetricEnvelope: Codable, Equatable {
    var sessionID: UUID
    var sequence: Int? = nil
    var sample: WorkoutMetricSample
}

struct WatchWorkoutEventEnvelope: Codable, Equatable {
    var sessionID: UUID
    var event: MirroredWorkoutEvent
}

struct WatchWorkoutAcknowledgement: Codable, Equatable {
    var sessionID: UUID
    var accepted: Bool
    var reason: String
    var timestamp: Date

    init(sessionID: UUID, accepted: Bool, reason: String, timestamp: Date = .now) {
        self.sessionID = sessionID
        self.accepted = accepted
        self.reason = reason
        self.timestamp = timestamp
    }
}

enum WatchPacketIngestResult: Equatable {
    case accepted
    case wrongSession
    case duplicateOrOutOfOrder
    case stale
    case cumulativeRegression
}

struct WatchMetricStreamState: Equatable {
    let sessionID: UUID
    private(set) var lastSequence: Int?
    private(set) var lastTimestamp: Date?
    private(set) var lastActiveEnergyKcal: Double?

    mutating func ingest(_ envelope: WatchMetricEnvelope, now: Date = .now) -> WatchPacketIngestResult {
        guard envelope.sessionID == sessionID else { return .wrongSession }
        guard now.timeIntervalSince(envelope.sample.timestamp) <= 15 else { return .stale }
        if let sequence = envelope.sequence, let lastSequence, sequence <= lastSequence {
            return .duplicateOrOutOfOrder
        }
        if envelope.sequence == nil, let lastTimestamp, envelope.sample.timestamp <= lastTimestamp {
            return .duplicateOrOutOfOrder
        }
        if let energy = envelope.sample.activeEnergyKcal,
           let lastActiveEnergyKcal,
           energy + 0.01 < lastActiveEnergyKcal {
            return .cumulativeRegression
        }
        if let sequence = envelope.sequence { lastSequence = sequence }
        lastTimestamp = envelope.sample.timestamp
        if let energy = envelope.sample.activeEnergyKcal { lastActiveEnergyKcal = energy }
        return .accepted
    }
}

enum WatchMessageDecoder {
    static func event(from message: [String: Any]) -> WatchWorkoutEventEnvelope? {
        guard message["type"] as? String == "event",
              let rawEvent = message["event"] as? String,
              let event = MirroredWorkoutEvent(rawValue: rawEvent),
              let rawSessionID = message["sessionID"] as? String,
              let sessionID = UUID(uuidString: rawSessionID) else { return nil }
        return WatchWorkoutEventEnvelope(sessionID: sessionID, event: event)
    }

    static func acknowledgement(from message: [String: Any]) -> WatchWorkoutAcknowledgement? {
        guard message["type"] as? String == "acknowledgement",
              let rawSessionID = message["sessionID"] as? String,
              let sessionID = UUID(uuidString: rawSessionID),
              let accepted = message["accepted"] as? Bool else { return nil }
        return WatchWorkoutAcknowledgement(
            sessionID: sessionID,
            accepted: accepted,
            reason: message["reason"] as? String ?? (accepted ? "accepted" : "rejected"),
            timestamp: (message["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .now
        )
    }
}

enum WatchMetricMerger {
    static func reconciledActiveEnergy(
        liveCumulativeKcal: Double?,
        finalizedHealthKitKcal: Double?
    ) -> Double? {
        if let finalizedHealthKitKcal, finalizedHealthKitKcal >= 0 { return finalizedHealthKitKcal }
        return liveCumulativeKcal
    }

    static func merge(existing: [WatchMetricEnvelope], incoming: [WatchMetricEnvelope]) -> [WatchMetricEnvelope] {
        var result = existing
        for candidate in incoming {
            if let index = result.firstIndex(where: { sameMetric($0, candidate) }) {
                if priority(candidate.sample.provenance.source) > priority(result[index].sample.provenance.source) {
                    result[index] = candidate
                }
            } else {
                result.append(candidate)
            }
        }
        return result.sorted { $0.sample.timestamp < $1.sample.timestamp }
    }

    static func deduplicateEvents(_ events: [MirroredWorkoutEvent]) -> [MirroredWorkoutEvent] {
        var seen = Set<MirroredWorkoutEvent>()
        return events.filter { seen.insert($0).inserted }
    }

    private static func sameMetric(_ lhs: WatchMetricEnvelope, _ rhs: WatchMetricEnvelope) -> Bool {
        lhs.sessionID == rhs.sessionID
            && abs(lhs.sample.timestamp.timeIntervalSince(rhs.sample.timestamp)) <= 1
            && (lhs.sample.heartRateBPM != nil) == (rhs.sample.heartRateBPM != nil)
    }

    private static func priority(_ source: MetricSource) -> Int {
        switch source {
        case .appleWatch: 4
        case .bluetooth: 3
        case .phoneSensor: 2
        case .phoneEstimate, .historicalModel: 1
        default: 0
        }
    }
}
