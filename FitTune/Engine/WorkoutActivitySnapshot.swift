import Foundation

struct WorkoutActivitySnapshot: Codable, Hashable {
    var sessionID: UUID
    var startedAt: Date
    var title: String
    var currentItem: String
    var progress: String
    var heartRate: Int?
    var restEndsAt: Date?

    static func strength(draft: WorkoutDraft, heartRate: Double?) -> WorkoutActivitySnapshot {
        let exercise = draft.currentExercise
        return WorkoutActivitySnapshot(
            sessionID: draft.id,
            startedAt: draft.startedAt,
            title: draft.session.name,
            currentItem: exercise.name,
            progress: "\(draft.currentSetKind.title) \(draft.currentPhaseOrdinal) / \(draft.currentPhaseTotal)",
            heartRate: heartRate.map { Int($0.rounded()) },
            restEndsAt: draft.restStartedAt.map { $0.addingTimeInterval(TimeInterval(draft.restRecommendation?.recommendedSeconds ?? draft.recommendation?.restSeconds ?? 0)) }
        )
    }

    static func cardio(draft: CardioSessionDraft, heartRate: Double?) -> WorkoutActivitySnapshot {
        WorkoutActivitySnapshot(sessionID: draft.id, startedAt: draft.startedAt, title: draft.modality.title, currentItem: "有氧训练", progress: draft.intensity.title, heartRate: heartRate.map { Int($0.rounded()) }, restEndsAt: nil)
    }
}
