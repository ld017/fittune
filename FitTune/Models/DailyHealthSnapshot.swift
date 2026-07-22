import Foundation

enum HealthSyncState: String, Codable, Equatable {
    case unavailable
    case permissionMissing
    case syncing
    case current
    case delayed
    case estimated
    case failed
}

enum DailyHealthMetric: String, CaseIterable, Codable, Hashable {
    case restingHeartRate
    case steps
    case walkingDistanceKm
    case activeEnergyKcal
}

struct SourcedHealthValue<Value: Codable & Equatable>: Codable, Equatable {
    var value: Value?
    var provenance: MetricProvenance
    var sampleDate: Date?
    var updatedAt: Date
    var syncState: HealthSyncState
}

struct DailyHealthSnapshot: Codable, Equatable {
    var day: Date
    var timeZoneIdentifier: String
    var restingHeartRate: SourcedHealthValue<Double>
    var steps: SourcedHealthValue<Int>
    var walkingDistanceKm: SourcedHealthValue<Double>
    var activeEnergyKcal: SourcedHealthValue<Double>
}

struct DailyHealthSample: Codable, Equatable {
    var externalID: String
    var metric: DailyHealthMetric
    var value: Double
    var sampleDate: Date
    var updatedAt: Date
    var source: MetricSource
    var sourceName: String
    var isDeleted: Bool

    init(
        externalID: String,
        metric: DailyHealthMetric,
        value: Double,
        sampleDate: Date,
        updatedAt: Date,
        source: MetricSource,
        sourceName: String,
        isDeleted: Bool = false
    ) {
        self.externalID = externalID
        self.metric = metric
        self.value = value
        self.sampleDate = sampleDate
        self.updatedAt = updatedAt
        self.source = source
        self.sourceName = sourceName
        self.isDeleted = isDeleted
    }
}
