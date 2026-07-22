import Foundation

enum DataConfidence: String, Codable, Equatable, CaseIterable {
    case measured
    case derived
    case estimated
    case unavailable
}

enum MetricSource: String, Codable, Equatable {
    case appleWatch
    case huaweiHealth
    case bluetooth
    case appleHealth
    case phoneSensor
    case phoneEstimate
    case manual
    case historicalModel
    case unknown
}

struct MetricProvenance: Codable, Equatable {
    var source: MetricSource
    var sourceName: String
    var confidence: DataConfidence
    var coverage: Double
    var sampledAt: Date?
    var algorithmVersion: String?

    init(
        source: MetricSource,
        sourceName: String,
        confidence: DataConfidence,
        coverage: Double,
        sampledAt: Date? = nil,
        algorithmVersion: String? = nil
    ) {
        self.source = source
        self.sourceName = sourceName
        self.confidence = confidence
        self.coverage = min(1, max(0, coverage))
        self.sampledAt = sampledAt
        self.algorithmVersion = algorithmVersion
    }
}

enum RecoveryValueProvenance: String, Codable, Equatable {
    case manual
    case appleHealth
    case huaweiHealth
    case estimated
    case unavailable
}

struct RecoveryDimensionValue: Codable, Equatable {
    var automaticValue: Double?
    var manualValue: Double?
    var resolvedValue: Double?
    var provenance: RecoveryValueProvenance

    init(
        automaticValue: Double? = nil,
        manualValue: Double? = nil,
        resolvedValue: Double? = nil,
        provenance: RecoveryValueProvenance
    ) {
        self.automaticValue = automaticValue
        self.manualValue = manualValue
        self.resolvedValue = resolvedValue
        self.provenance = provenance
    }
}

struct RecoveryCheckIn: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date
    var sleep: RecoveryDimensionValue
    var soreness: RecoveryDimensionValue
    var stress: RecoveryDimensionValue
    var motivation: RecoveryDimensionValue

    init(
        id: UUID = UUID(),
        date: Date,
        sleep: RecoveryDimensionValue,
        soreness: RecoveryDimensionValue,
        stress: RecoveryDimensionValue,
        motivation: RecoveryDimensionValue
    ) {
        self.id = id
        self.date = date
        self.sleep = sleep
        self.soreness = soreness
        self.stress = stress
        self.motivation = motivation
    }
}

enum RecoveryDimension: String, Codable, Equatable, CaseIterable {
    case sleep
    case soreness
    case stress
    case motivation
}

struct RecoveryContribution: Codable, Equatable {
    var dimension: RecoveryDimension
    var resolvedValue: Double
    var provenance: RecoveryValueProvenance
    var weightedPoints: Double
}

struct RecoveryAssessmentResult: Codable, Equatable {
    var score: Int
    var level: ReadinessLevel
    var summary: String
    var loadMultiplier: Double
    var setReduction: Int
    var contributions: [RecoveryContribution]
    var restingHeartRateBaseline: Double?
    var currentRestingHeartRate: Double?
    var restingHeartRateAdjustment: Int
}

struct RestingHeartRateSample: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date
    var bpm: Double
    var source: MetricSource
    var sourceName: String
    var externalID: String?

    init(
        id: UUID = UUID(),
        date: Date,
        bpm: Double,
        source: MetricSource,
        sourceName: String,
        externalID: String? = nil
    ) {
        self.id = id
        self.date = date
        self.bpm = bpm
        self.source = source
        self.sourceName = sourceName
        self.externalID = externalID
    }
}

struct WorkoutMetricSample: Identifiable, Codable, Equatable {
    var id: UUID
    var timestamp: Date
    var heartRateBPM: Double?
    var cadence: Double?
    var steps: Int?
    var distanceMeters: Double?
    var activeEnergyKcal: Double?
    var swimmingStrokeCount: Double?
    var provenance: MetricProvenance

    init(
        id: UUID = UUID(),
        timestamp: Date,
        heartRateBPM: Double? = nil,
        cadence: Double? = nil,
        steps: Int? = nil,
        distanceMeters: Double? = nil,
        activeEnergyKcal: Double? = nil,
        swimmingStrokeCount: Double? = nil,
        provenance: MetricProvenance
    ) {
        self.id = id
        self.timestamp = timestamp
        self.heartRateBPM = heartRateBPM
        self.cadence = cadence
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.activeEnergyKcal = activeEnergyKcal
        self.swimmingStrokeCount = swimmingStrokeCount
        self.provenance = provenance
    }
}

struct MetricRange: Codable, Equatable {
    var value: Double
    var lowerBound: Double
    var upperBound: Double
    var provenance: MetricProvenance
}

struct StrengthSummaryMetrics: Codable, Equatable {
    var volumeLoadKg: Double
    var workingSetCount: Int
    var warmupSetCount: Int
    var failureRate: Double
    var bestE1RMKg: Double?
    var relativeStrength: Double?
    var e1RMConfidence: DataConfidence
    var muscleLoad: [String: Double]
    var heartRateDecisions: [HeartRateDecisionEvent]? = nil
}

struct HeartRateDecisionEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var setResultID: UUID
    var secondsAfterSet: Int
    var peakBPM: Double
    var currentBPM: Double
    var recoveryBPM: Double
    var sourceName: String
    var effect: String
}

struct CardioSummaryMetrics: Codable, Equatable {
    var distanceKm: Double?
    var paceSecondsPerKm: Double?
    var averageCadence: Double?
    var strokeCount: Double?
    var heartRateRecovery60: Double?
    var vo2Max: Double?
    var vo2MaxConfidence: DataConfidence
}

struct WorkoutSummary: Codable, Equatable {
    var generatedAt: Date
    var algorithmVersion: String
    var averageHeartRate: Double?
    var maximumHeartRate: Double?
    var activeEnergyKcal: MetricRange?
    var estimatedRecoveryHours: MetricRange?
    var trainingEffect: MetricRange?
    var dataCoverage: Double?
    var strength: StrengthSummaryMetrics? = nil
    var cardio: CardioSummaryMetrics? = nil
    var heartRateCurve: [WorkoutMetricSample]? = nil
    var heartRateSourceName: String? = nil
    var heartRateConfidence: DataConfidence? = nil
    var heartRateZones: [String: Double]? = nil
    var heartRateGapCount: Int? = nil

    init(
        generatedAt: Date,
        algorithmVersion: String,
        averageHeartRate: Double? = nil,
        maximumHeartRate: Double? = nil,
        activeEnergyKcal: MetricRange? = nil,
        estimatedRecoveryHours: MetricRange? = nil,
        trainingEffect: MetricRange? = nil,
        dataCoverage: Double? = nil,
        strength: StrengthSummaryMetrics? = nil,
        cardio: CardioSummaryMetrics? = nil,
        heartRateCurve: [WorkoutMetricSample]? = nil,
        heartRateSourceName: String? = nil,
        heartRateConfidence: DataConfidence? = nil,
        heartRateZones: [String: Double]? = nil,
        heartRateGapCount: Int? = nil
    ) {
        self.generatedAt = generatedAt
        self.algorithmVersion = algorithmVersion
        self.averageHeartRate = averageHeartRate
        self.maximumHeartRate = maximumHeartRate
        self.activeEnergyKcal = activeEnergyKcal
        self.estimatedRecoveryHours = estimatedRecoveryHours
        self.trainingEffect = trainingEffect
        self.dataCoverage = dataCoverage
        self.strength = strength
        self.cardio = cardio
        self.heartRateCurve = heartRateCurve
        self.heartRateSourceName = heartRateSourceName
        self.heartRateConfidence = heartRateConfidence
        self.heartRateZones = heartRateZones
        self.heartRateGapCount = heartRateGapCount
    }
}

struct SummaryRevision: Identifiable, Codable, Equatable {
    var id: UUID
    var revisedAt: Date
    var reason: String
    var summary: WorkoutSummary

    init(id: UUID = UUID(), revisedAt: Date = .now, reason: String, summary: WorkoutSummary) {
        self.id = id
        self.revisedAt = revisedAt
        self.reason = reason
        self.summary = summary
    }
}

struct WorkoutSummaryPresentation: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var date: Date
    var summary: WorkoutSummary
}

struct PersonalSafetySettings: Codable, Equatable {
    var avoidedRegions: Set<BodyRegion> = []
    var disabledExerciseIDs: Set<String> = []
    var painAlertThreshold: Int = 2
    var maximumHeartRateAlert: Int? = nil
}
