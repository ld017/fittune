import Foundation

enum DailyHealthSnapshotReducer {
    static func reduce(
        samples: [DailyHealthSample],
        day: Date,
        timeZone: TimeZone,
        permissions: [DailyHealthMetric: Bool] = [:],
        now: Date = .now
    ) -> DailyHealthSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)

        let currentSamples = latestVersions(samples)
            .filter { !$0.isDeleted && $0.sampleDate >= start && $0.sampleDate < end && $0.value >= 0 }
        let deduplicated = removeSensorDuplicates(currentSamples)

        return DailyHealthSnapshot(
            day: start,
            timeZoneIdentifier: timeZone.identifier,
            restingHeartRate: doubleValue(
                metric: .restingHeartRate,
                samples: deduplicated,
                permission: permissions[.restingHeartRate] ?? true,
                now: now,
                aggregation: .latest
            ),
            steps: intValue(
                metric: .steps,
                samples: deduplicated,
                permission: permissions[.steps] ?? true,
                now: now
            ),
            walkingDistanceKm: doubleValue(
                metric: .walkingDistanceKm,
                samples: deduplicated,
                permission: permissions[.walkingDistanceKm] ?? true,
                now: now,
                aggregation: .sum
            ),
            activeEnergyKcal: doubleValue(
                metric: .activeEnergyKcal,
                samples: deduplicated,
                permission: permissions[.activeEnergyKcal] ?? true,
                now: now,
                aggregation: .sum
            )
        )
    }

    private enum Aggregation { case latest, sum }

    private static func latestVersions(_ samples: [DailyHealthSample]) -> [DailyHealthSample] {
        var latest: [String: DailyHealthSample] = [:]
        for sample in samples {
            let key = "\(sample.metric.rawValue):\(sample.externalID)"
            if latest[key] == nil || sample.updatedAt > latest[key]!.updatedAt {
                latest[key] = sample
            }
        }
        return Array(latest.values)
    }

    private static func removeSensorDuplicates(_ samples: [DailyHealthSample]) -> [DailyHealthSample] {
        var preferred: [String: DailyHealthSample] = [:]
        for sample in samples {
            let timestamp = Int(sample.sampleDate.timeIntervalSince1970.rounded())
            let value = Int((sample.value * 1_000).rounded())
            let key = "\(sample.metric.rawValue):\(timestamp):\(value)"
            if let current = preferred[key] {
                if sourcePriority(sample.source) > sourcePriority(current.source) {
                    preferred[key] = sample
                }
            } else {
                preferred[key] = sample
            }
        }
        return Array(preferred.values)
    }

    private static func intValue(
        metric: DailyHealthMetric,
        samples: [DailyHealthSample],
        permission: Bool,
        now: Date
    ) -> SourcedHealthValue<Int> {
        let matching = samples.filter { $0.metric == metric }
        guard permission else { return missing(syncState: .permissionMissing, now: now) }
        guard let representative = representative(in: matching) else { return missing(syncState: .unavailable, now: now) }
        return SourcedHealthValue(
            value: Int(matching.reduce(0) { $0 + $1.value }.rounded()),
            provenance: provenance(for: representative),
            sampleDate: matching.map(\.sampleDate).max(),
            updatedAt: matching.map(\.updatedAt).max() ?? now,
            syncState: syncState(for: representative, latestSample: matching.map(\.sampleDate).max(), now: now)
        )
    }

    private static func doubleValue(
        metric: DailyHealthMetric,
        samples: [DailyHealthSample],
        permission: Bool,
        now: Date,
        aggregation: Aggregation
    ) -> SourcedHealthValue<Double> {
        let matching = samples.filter { $0.metric == metric }
        guard permission else { return missing(syncState: .permissionMissing, now: now) }
        guard let representative = representative(in: matching) else { return missing(syncState: .unavailable, now: now) }
        let value: Double
        switch aggregation {
        case .latest:
            value = matching.max(by: { $0.sampleDate < $1.sampleDate })?.value ?? representative.value
        case .sum:
            value = matching.reduce(0) { $0 + $1.value }
        }
        return SourcedHealthValue(
            value: value,
            provenance: provenance(for: representative),
            sampleDate: matching.map(\.sampleDate).max(),
            updatedAt: matching.map(\.updatedAt).max() ?? now,
            syncState: syncState(for: representative, latestSample: matching.map(\.sampleDate).max(), now: now)
        )
    }

    private static func representative(in samples: [DailyHealthSample]) -> DailyHealthSample? {
        samples.max { left, right in
            let leftPriority = sourcePriority(left.source)
            let rightPriority = sourcePriority(right.source)
            return leftPriority == rightPriority ? left.sampleDate < right.sampleDate : leftPriority < rightPriority
        }
    }

    private static func provenance(for sample: DailyHealthSample) -> MetricProvenance {
        MetricProvenance(
            source: sample.source,
            sourceName: normalizedSourceName(sample.source, fallback: sample.sourceName),
            confidence: .measured,
            coverage: 1,
            sampledAt: sample.sampleDate,
            algorithmVersion: "1.1-health-daily-1"
        )
    }

    private static func syncState(for sample: DailyHealthSample, latestSample: Date?, now: Date) -> HealthSyncState {
        if sample.source == .huaweiHealth { return .delayed }
        if let latestSample, now.timeIntervalSince(latestSample) > 36 * 3_600 { return .delayed }
        return .current
    }

    private static func normalizedSourceName(_ source: MetricSource, fallback: String) -> String {
        switch source {
        case .appleWatch, .appleHealth: "Apple 健康"
        case .huaweiHealth: "华为健康"
        default: fallback
        }
    }

    private static func sourcePriority(_ source: MetricSource) -> Int {
        switch source {
        case .appleWatch: 5
        case .appleHealth: 4
        case .huaweiHealth: 3
        case .phoneSensor: 2
        case .phoneEstimate: 1
        default: 0
        }
    }

    private static func missing<Value: Codable & Equatable>(
        syncState: HealthSyncState,
        now: Date
    ) -> SourcedHealthValue<Value> {
        SourcedHealthValue(
            value: nil,
            provenance: MetricProvenance(
                source: .unknown,
                sourceName: syncState == .permissionMissing ? "未授权" : "暂无数据",
                confidence: .unavailable,
                coverage: 0,
                algorithmVersion: "1.1-health-daily-1"
            ),
            sampleDate: nil,
            updatedAt: now,
            syncState: syncState
        )
    }
}
