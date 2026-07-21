import Foundation

enum CardioMetricKind: String, Codable, Equatable, Hashable {
    case heartRate
    case distance
    case pace
    case cadence
    case steps
    case incline
    case floors
    case power
    case strokeCount
}

enum CardioSessionCapabilities {
    static func metrics(for modality: CardioModality, hasWatch: Bool) -> Set<CardioMetricKind> {
        var result: Set<CardioMetricKind> = [.heartRate]
        switch modality {
        case .running, .briskWalking:
            result.formUnion([.distance, .pace, .cadence, .steps])
        case .inclineWalking:
            result.formUnion([.distance, .pace, .cadence, .steps, .incline])
        case .stairClimber:
            result.formUnion([.cadence, .steps, .floors])
        case .cycling:
            result.formUnion([.distance, .pace, .cadence, .power])
        case .rowing:
            result.formUnion([.cadence, .power])
        case .swimming:
            if hasWatch { result.formUnion([.distance, .pace, .strokeCount]) }
        case .elliptical, .jumpRope:
            result.formUnion([.cadence, .steps])
        }
        return result
    }

    static func unavailableMetrics(for modality: CardioModality, hasWatch: Bool) -> Set<CardioMetricKind> {
        modality == .swimming && !hasWatch ? [.strokeCount] : []
    }
}

struct CardioSessionDraft: Identifiable, Codable, Equatable {
    var id = UUID()
    var modality: CardioModality
    var intensity: CardioIntensity
    var startedAt: Date = .now
    var updatedAt: Date = .now
    var metricSamples: [WorkoutMetricSample] = []
    var distanceMeters: Double = 0
    var dataGapReason: String? = nil
}

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
