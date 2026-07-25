import Foundation

struct WorkoutActivitySnapshot: Codable, Hashable {
    var sessionID: UUID
    var startedAt: Date
    var title: String
    var currentItem: String
    var progress: String
    var heartRate: Int?
    var restEndsAt: Date?
    var isCardio: Bool = false
    var distanceMeters: Double? = nil
    var cadence: Double? = nil

    var nextSetURL: URL {
        URL(string: "fittune://workout?action=nextSet&session=\(sessionID.uuidString)")!
    }

    static func parseActionURL(_ url: URL) -> WorkoutActivityDeepLink? {
        guard url.scheme == "fittune", url.host == "workout",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let actionValue = components.queryItems?.first(where: { $0.name == "action" })?.value,
              let action = WorkoutActivityAction(rawValue: actionValue),
              let sessionValue = components.queryItems?.first(where: { $0.name == "session" })?.value,
              let sessionID = UUID(uuidString: sessionValue) else { return nil }
        return WorkoutActivityDeepLink(action: action, sessionID: sessionID)
    }

    static func strength(draft: WorkoutDraft, heartRate: Double?) -> WorkoutActivitySnapshot {
        let exercise = draft.currentExercise
        return WorkoutActivitySnapshot(
            sessionID: draft.id,
            startedAt: draft.startedAt,
            title: draft.session.name,
            currentItem: exercise.name,
            progress: "\(draft.currentSetKind.title) \(draft.currentPhaseOrdinal) / \(draft.currentPhaseTotal)",
            heartRate: heartRate.map { Int($0.rounded()) },
            restEndsAt: draft.restStartedAt.map { $0.addingTimeInterval(TimeInterval(draft.restRecommendation?.recommendedSeconds ?? draft.recommendation?.restSeconds ?? 0)) },
            isCardio: false
        )
    }

    static func cardio(draft: CardioSessionDraft, heartRate: Double?) -> WorkoutActivitySnapshot {
        let workload = draft.currentWorkload
        return WorkoutActivitySnapshot(
            sessionID: draft.id,
            startedAt: draft.startedAt,
            title: draft.modality.title,
            currentItem: cardioWorkloadText(workload),
            progress: draft.modality == .inclineWalking
                ? workload.map { "\(draft.intensity.title) · 扶把：\($0.handrailSupport.title)" } ?? draft.intensity.title
                : draft.intensity.title,
            heartRate: heartRate.map { Int($0.rounded()) },
            restEndsAt: nil,
            isCardio: true,
            distanceMeters: draft.distanceMeters > 0 ? draft.distanceMeters : nil,
            cadence: draft.metricSamples.compactMap(\.cadence).last
        )
    }

    private static func cardioWorkloadText(_ workload: CardioWorkloadSegment?) -> String {
        guard let workload else { return "有氧训练" }
        var values: [String] = []
        if let speed = workload.speedKph {
            values.append("\(speed.formatted(.number.precision(.fractionLength(1)))) km/h")
        }
        if workload.resolvedInclineInputMode == .machineLevel, let level = workload.inclineLevel {
            values.append("档位 \(Int(level.rounded()))")
        } else if let grade = workload.resolvedInclinePercent {
            values.append("\(grade.formatted(.number.precision(.fractionLength(1))))%")
        }
        if let power = workload.powerWatts {
            values.append("\(Int(power.rounded())) W")
        }
        return values.isEmpty ? "有氧训练" : values.joined(separator: " · ")
    }
}

enum WorkoutActivityAction: String, Codable, Hashable {
    case nextSet
}

struct WorkoutActivityDeepLink: Codable, Hashable {
    var action: WorkoutActivityAction
    var sessionID: UUID
}
