import Foundation

struct WarmupSetSuggestion: Codable, Equatable {
    var loadKg: Double
    var reps: Int
    var rir: Int = 5
}

struct PlanSnapshot: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var sourcePlanRuleVersion: String
    var sourceSessionID: UUID
    var planTitle: String
    var sessionName: String
    var goal: TrainingGoal
    var split: TrainingSplit
    var equipment: EquipmentProfile
    var exercises: [ExercisePrescription]

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        sourcePlanRuleVersion: String,
        sourceSessionID: UUID,
        planTitle: String,
        sessionName: String,
        goal: TrainingGoal,
        split: TrainingSplit,
        equipment: EquipmentProfile,
        exercises: [ExercisePrescription]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourcePlanRuleVersion = sourcePlanRuleVersion
        self.sourceSessionID = sourceSessionID
        self.planTitle = planTitle
        self.sessionName = sessionName
        self.goal = goal
        self.split = split
        self.equipment = equipment
        self.exercises = exercises
    }
}

enum WorkoutChangeKind: String, Codable, Equatable {
    case exerciseAdded
    case exerciseRemoved
    case exerciseReplaced
    case prescriptionChanged
}

struct WorkoutChangeEvent: Identifiable, Codable, Equatable {
    var id: UUID
    var timestamp: Date
    var kind: WorkoutChangeKind
    var exerciseName: String
    var detail: String

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        kind: WorkoutChangeKind,
        exerciseName: String,
        detail: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.exerciseName = exerciseName
        self.detail = detail
    }
}
