import Foundation

enum LiveSensorKind: String, Codable, Equatable {
    case appleWatch
    case bluetooth
}

struct LiveSourceDescriptor: Identifiable, Codable, Equatable {
    var id: String
    var kind: LiveSensorKind
    var name: String
}

enum LiveConnectionState: String, Codable, Equatable {
    case none
    case scanning
    case connecting
    case connected
    case reconnecting
    case stale
    case estimated
    case failed
}

enum LiveMetricValidity: String, Codable, Equatable {
    case valid
    case stale
    case outOfRange
    case implausibleJump
    case poorContact
    case missing
}

enum LiveMetricValidator {
    static func validate(
        _ sample: WorkoutMetricSample,
        previous: WorkoutMetricSample?,
        contactDetected: Bool?,
        now: Date = .now
    ) -> LiveMetricValidity {
        guard now.timeIntervalSince(sample.timestamp) <= 15 else { return .stale }
        guard contactDetected != false else { return .poorContact }
        guard let bpm = sample.heartRateBPM else { return .missing }
        guard (30...240).contains(bpm) else { return .outOfRange }
        if let previousBPM = previous?.heartRateBPM,
           abs(sample.timestamp.timeIntervalSince(previous?.timestamp ?? sample.timestamp)) <= 5,
           abs(bpm - previousBPM) > 40 {
            return .implausibleJump
        }
        return .valid
    }
}
