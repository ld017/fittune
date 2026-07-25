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

enum HandrailSupport: String, CaseIterable, Codable, Identifiable {
    case none
    case occasional
    case sustained

    var id: String { rawValue }
}

enum CardioWorkloadSource: String, Codable {
    case userEntered
    case device
    case derived
}

struct CardioWorkloadSegment: Identifiable, Codable, Equatable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date? = nil
    var speedKph: Double? = nil
    var inclinePercent: Double? = nil
    var powerWatts: Double? = nil
    var handrailSupport: HandrailSupport = .none
    var source: CardioWorkloadSource

    var durationSeconds: TimeInterval? {
        endedAt.map { max(0, $0.timeIntervalSince(startedAt)) }
    }
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
    var workloadSegments: [CardioWorkloadSegment] = []
    var confirmedDistanceMeters: Double? = nil
    var workloadWarnings: [String] = []
}

extension CardioSessionDraft {
    private enum CodingKeys: String, CodingKey {
        case id
        case modality
        case intensity
        case startedAt
        case updatedAt
        case metricSamples
        case distanceMeters
        case dataGapReason
        case workloadSegments
        case confirmedDistanceMeters
        case workloadWarnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        modality = try container.decode(CardioModality.self, forKey: .modality)
        intensity = try container.decode(CardioIntensity.self, forKey: .intensity)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        metricSamples = try container.decode([WorkoutMetricSample].self, forKey: .metricSamples)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        dataGapReason = try container.decodeIfPresent(String.self, forKey: .dataGapReason)
        workloadSegments = try container.decodeIfPresent([CardioWorkloadSegment].self, forKey: .workloadSegments) ?? []
        confirmedDistanceMeters = try container.decodeIfPresent(Double.self, forKey: .confirmedDistanceMeters)
        workloadWarnings = try container.decodeIfPresent([String].self, forKey: .workloadWarnings) ?? []
    }
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
    case exerciseReordered
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
