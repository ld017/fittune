import Foundation

enum SportKind: String, CaseIterable, Codable, Equatable, Hashable, Identifiable {
    case badminton
    case tableTennis
    case soccer
    case climbing
    case hiking
    case mountaineering
    case trailRunning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .badminton: "羽毛球"
        case .tableTennis: "乒乓球"
        case .soccer: "足球"
        case .climbing: "攀岩"
        case .hiking: "徒步"
        case .mountaineering: "登山"
        case .trailRunning: "越野跑"
        }
    }

    var symbol: String {
        switch self {
        case .badminton: "figure.badminton"
        case .tableTennis: "figure.table.tennis"
        case .soccer: "figure.soccer"
        case .climbing: "figure.climbing"
        case .hiking: "figure.hiking"
        case .mountaineering: "mountain.2"
        case .trailRunning: "figure.run"
        }
    }

    /// A platform-neutral key translated to HKWorkoutActivityType by the Watch adapter.
    var watchActivityKey: String {
        switch self {
        case .badminton: "badminton"
        case .tableTennis: "tableTennis"
        case .soccer: "soccer"
        case .climbing: "climbing"
        case .hiking, .mountaineering: "hiking"
        case .trailRunning: "running"
        }
    }

    var defaultEnvironment: SportEnvironment {
        switch self {
        case .badminton, .tableTennis, .climbing: .indoor
        case .soccer, .hiking, .mountaineering, .trailRunning: .outdoor
        }
    }

    var availableEnvironments: [SportEnvironment] {
        switch self {
        case .badminton, .tableTennis:
            [.indoor]
        case .soccer, .climbing:
            [.indoor, .outdoor]
        case .hiking, .mountaineering, .trailRunning:
            [.outdoor]
        }
    }
}

enum SportEnvironment: String, CaseIterable, Codable, Equatable, Hashable {
    case indoor
    case outdoor

    var title: String {
        switch self {
        case .indoor: "室内"
        case .outdoor: "户外"
        }
    }
}

enum SportIntensity: String, CaseIterable, Codable, Equatable, Hashable {
    case social
    case training
    case competition

    var title: String {
        switch self {
        case .social: "休闲"
        case .training: "训练"
        case .competition: "比赛"
        }
    }
}

enum SportMetricCapability: String, CaseIterable, Codable, Equatable, Hashable {
    case duration
    case movingTime
    case heartRate
    case activeEnergy
    case steps
    case cadence
    case distance
    case pace
    case speed
    case altitude
    case elevationGain
}

struct SportPauseInterval: Codable, Equatable {
    var startedAt: Date
    var endedAt: Date
}

struct SportSessionDraft: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: SportKind
    var environment: SportEnvironment
    var intensity: SportIntensity
    var startedAt: Date
    var updatedAt: Date
    var pauseIntervals: [SportPauseInterval]
    var pausedAt: Date?
    var metricSamples: [WorkoutMetricSample]
    var dataGapReasons: [String]
    var sourceNames: [String]
    var lastCheckpointAt: Date?

    init(
        id: UUID = UUID(),
        kind: SportKind,
        environment: SportEnvironment,
        intensity: SportIntensity,
        startedAt: Date = .now,
        updatedAt: Date? = nil,
        pauseIntervals: [SportPauseInterval] = [],
        pausedAt: Date? = nil,
        metricSamples: [WorkoutMetricSample] = [],
        dataGapReasons: [String] = [],
        sourceNames: [String] = [],
        lastCheckpointAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.environment = environment
        self.intensity = intensity
        self.startedAt = startedAt
        self.updatedAt = updatedAt ?? startedAt
        self.pauseIntervals = pauseIntervals
        self.pausedAt = pausedAt
        self.metricSamples = metricSamples
        self.dataGapReasons = dataGapReasons
        self.sourceNames = sourceNames
        self.lastCheckpointAt = lastCheckpointAt
    }
}

struct SportAnalysisResult: Codable, Equatable {
    var effectiveDurationSeconds: TimeInterval
    var activeEnergyKcal: MetricRange
    var sessionRPELoadAU: Double
    var heartRateIntensity: HeartRateIntensitySummary?
    var estimatedRecoveryHours: MetricRange
    var averageHeartRate: Double?
    var maximumHeartRate: Double?
    var distanceMeters: Double?
    var steps: Int?
    var averageCadence: Double?
    var elevationGainMeters: Double?
    var provenance: [MetricProvenance]
    var dataCoverage: Double
    var warnings: [String]
    var algorithmVersion: String
}

struct SportSessionRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: SportKind
    var environment: SportEnvironment
    var intensity: SportIntensity
    var startedAt: Date
    var completedAt: Date
    var completionStatus: WorkoutCompletionStatus
    var sessionRPE: Double
    var analysis: SportAnalysisResult
    var metricSamples: [WorkoutMetricSample]
    var summary: String
    var summaryRevisions: [SummaryRevision]

    init(
        id: UUID = UUID(),
        kind: SportKind,
        environment: SportEnvironment,
        intensity: SportIntensity,
        startedAt: Date,
        completedAt: Date,
        completionStatus: WorkoutCompletionStatus,
        sessionRPE: Double,
        analysis: SportAnalysisResult,
        metricSamples: [WorkoutMetricSample] = [],
        summary: String = "",
        summaryRevisions: [SummaryRevision] = []
    ) {
        self.id = id
        self.kind = kind
        self.environment = environment
        self.intensity = intensity
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.completionStatus = completionStatus
        self.sessionRPE = sessionRPE
        self.analysis = analysis
        self.metricSamples = metricSamples
        self.summary = summary
        self.summaryRevisions = summaryRevisions
    }
}
