import Foundation

enum MirroredWorkoutEvent: String, Codable, Equatable, Hashable {
    case started
    case paused
    case resumed
    case ended
}

struct WatchMetricEnvelope: Codable, Equatable {
    var sessionID: UUID
    var sample: WorkoutMetricSample
}

struct WatchWorkoutEventEnvelope: Codable, Equatable {
    var sessionID: UUID
    var event: MirroredWorkoutEvent
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
}

enum WatchMetricMerger {
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
