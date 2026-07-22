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
        WorkoutActivitySnapshot(
            sessionID: draft.id,
            startedAt: draft.startedAt,
            title: draft.modality.title,
            currentItem: "有氧训练",
            progress: draft.intensity.title,
            heartRate: heartRate.map { Int($0.rounded()) },
            restEndsAt: nil,
            isCardio: true,
            distanceMeters: draft.distanceMeters > 0 ? draft.distanceMeters : nil,
            cadence: draft.metricSamples.compactMap(\.cadence).last
        )
    }
}

enum WorkoutActivityAction: String, Codable, Hashable {
    case nextSet
}

struct WorkoutActivityDeepLink: Codable, Hashable {
    var action: WorkoutActivityAction
    var sessionID: UUID
}
