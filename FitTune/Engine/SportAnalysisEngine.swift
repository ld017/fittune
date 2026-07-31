import Foundation

enum SportAnalysisEngine {
    static let algorithmVersion = "2.0.0-sport-analysis-1"

    static func capabilities(
        kind: SportKind,
        environment: SportEnvironment,
        hasHeartRate: Bool,
        hasLocation: Bool,
        hasPedometer: Bool,
        hasElevation: Bool
    ) -> Set<SportMetricCapability> {
        var result: Set<SportMetricCapability> = [.duration, .activeEnergy]
        if hasHeartRate { result.insert(.heartRate) }

        switch kind {
        case .badminton, .tableTennis:
            if hasPedometer {
                result.formUnion([.steps, .cadence])
            }

        case .soccer:
            if hasPedometer {
                result.formUnion([.steps, .cadence])
            }
            if environment == .outdoor, hasLocation {
                result.formUnion([.distance, .speed])
            }

        case .climbing:
            if environment == .outdoor, hasLocation, hasElevation {
                result.formUnion([.altitude, .elevationGain])
            }

        case .hiking:
            if hasPedometer { result.insert(.steps) }
            if environment == .outdoor, hasLocation {
                result.formUnion([.distance, .pace])
            }
            if environment == .outdoor, hasLocation, hasElevation {
                result.formUnion([.altitude, .elevationGain])
            }

        case .mountaineering:
            if hasPedometer { result.insert(.steps) }
            if environment == .outdoor, hasLocation {
                result.formUnion([.distance, .movingTime])
            }
            if environment == .outdoor, hasLocation, hasElevation {
                result.formUnion([.altitude, .elevationGain])
            }

        case .trailRunning:
            if hasPedometer { result.insert(.cadence) }
            if environment == .outdoor, hasLocation {
                result.formUnion([.distance, .pace])
            }
            if environment == .outdoor, hasLocation, hasElevation {
                result.formUnion([.altitude, .elevationGain])
            }
        }

        return result
    }

    static func analyze(
        draft: SportSessionDraft,
        completedAt: Date,
        sessionRPE: Double,
        weightKg: Double,
        restingHeartRate: Double?,
        maximumHeartRate: Double?
    ) -> SportAnalysisResult {
        let pauseIntervals = normalizedPauseIntervals(draft: draft, completedAt: completedAt)
        let elapsedSeconds = max(0, completedAt.timeIntervalSince(draft.startedAt))
        let pausedSeconds = pauseIntervals.reduce(0.0) {
            $0 + $1.end.timeIntervalSince($1.start)
        }
        let effectiveSeconds = max(0, elapsedSeconds - pausedSeconds)
        let activeMinutes = effectiveSeconds / 60
        let validSamples = draft.metricSamples.filter { sample in
            sample.timestamp >= draft.startedAt
                && sample.timestamp <= completedAt
                && !pauseIntervals.contains { sample.timestamp >= $0.start && sample.timestamp < $0.end }
        }

        let met = metRange(kind: draft.kind, intensity: draft.intensity)
        let energyProvenance = MetricProvenance(
            source: .phoneEstimate,
            sourceName: "2024 Adult Compendium MET 净主动能量估算",
            confidence: .estimated,
            coverage: effectiveSeconds > 0 && weightKg > 0 ? 1 : 0,
            sampledAt: completedAt,
            algorithmVersion: algorithmVersion
        )
        let energy = MetricRange(
            value: activeEnergy(met: met.center, weightKg: weightKg, activeMinutes: activeMinutes),
            lowerBound: activeEnergy(met: met.lower, weightKg: weightKg, activeMinutes: activeMinutes),
            upperBound: activeEnergy(met: met.upper, weightKg: weightKg, activeMinutes: activeMinutes),
            provenance: energyProvenance
        )

        let boundedRPE = min(10, max(1, sessionRPE))
        let sessionRPELoad = activeMinutes * boundedRPE
        let heartRateSummary = HeartRateAnalysisEngine.intensitySummary(
            samples: validSamples,
            startedAt: draft.startedAt,
            completedAt: completedAt,
            restingHeartRate: restingHeartRate,
            maximumHeartRate: maximumHeartRate
        )
        let validHeartRates = validSamples.compactMap(\.heartRateBPM).filter { (40...220).contains($0) }

        let recovery = recoveryRange(
            kind: draft.kind,
            sessionRPELoad: sessionRPELoad,
            heartRateLoad: heartRateSummary?.zoneLoadAU,
            completedAt: completedAt
        )

        var warnings = [
            "主动能量来自运动特异 MET 范围估算，不是直接生理实测。",
            "恢复时间是低精度计划范围，不用于诊断或自动限制运动。"
        ]
        warnings.append(contentsOf: draft.dataGapReasons)
        if sessionRPE != boundedRPE {
            warnings.append("session-RPE 已限制在 1–10。")
        }

        let heartRateGapCount = countHeartRateGaps(in: validSamples)
        if heartRateGapCount > 0 {
            warnings.append("心率样本间隔超过 15 秒的时段未计入心率区间。")
        } else if validHeartRates.isEmpty {
            warnings.append("未获得可用心率，心率区间与负荷置信度降低。")
        } else if heartRateSummary == nil {
            warnings.append("缺少有效最大心率，未生成心率区间。")
        }

        let sampleProvenance = validSamples.map(\.provenance)
        let provenance = uniqueProvenance(sampleProvenance + [energyProvenance, recovery.provenance])
        let sensorCoverage = sampleProvenance.map(\.coverage).max() ?? 0

        return SportAnalysisResult(
            effectiveDurationSeconds: effectiveSeconds,
            activeEnergyKcal: energy,
            sessionRPELoadAU: sessionRPELoad,
            heartRateIntensity: heartRateSummary,
            estimatedRecoveryHours: recovery,
            averageHeartRate: validHeartRates.isEmpty
                ? nil
                : validHeartRates.reduce(0, +) / Double(validHeartRates.count),
            maximumHeartRate: validHeartRates.max(),
            distanceMeters: validSamples.compactMap(\.distanceMeters).filter { $0 >= 0 }.max(),
            steps: validSamples.compactMap(\.steps).filter { $0 >= 0 }.max(),
            averageCadence: average(validSamples.compactMap(\.cadence).filter { $0 >= 0 }),
            elevationGainMeters: validSamples.compactMap(\.elevationGainMeters).filter { $0 >= 0 }.max(),
            provenance: provenance,
            dataCoverage: min(1, max(0, heartRateSummary?.coverage ?? sensorCoverage)),
            warnings: warnings,
            algorithmVersion: algorithmVersion
        )
    }

    private static func activeEnergy(
        met: Double,
        weightKg: Double,
        activeMinutes: Double
    ) -> Double {
        max(met - 1, 0) * 3.5 * max(weightKg, 0) / 200 * max(activeMinutes, 0)
    }

    private static func metRange(
        kind: SportKind,
        intensity: SportIntensity
    ) -> (lower: Double, center: Double, upper: Double) {
        let bounds: (lower: Double, upper: Double)
        switch kind {
        case .badminton: bounds = (5.5, 9.0)
        case .tableTennis: bounds = (3.0, 6.0)
        case .soccer: bounds = (7.0, 9.5)
        case .climbing: bounds = (5.8, 8.8)
        case .hiking: bounds = (3.8, 7.8)
        case .mountaineering: bounds = (6.0, 10.3)
        case .trailRunning: bounds = (9.3, 10.5)
        }

        let center: Double
        if kind == .tableTennis {
            center = 4.0
        } else {
            switch intensity {
            case .social: center = bounds.lower
            case .training: center = (bounds.lower + bounds.upper) / 2
            case .competition: center = bounds.upper
            }
        }
        return (bounds.lower, center, bounds.upper)
    }

    private static func recoveryRange(
        kind: SportKind,
        sessionRPELoad: Double,
        heartRateLoad: Double?,
        completedAt: Date
    ) -> MetricRange {
        let sportFactor: Double
        switch kind {
        case .badminton, .tableTennis, .hiking: sportFactor = 1
        case .soccer, .climbing: sportFactor = 1.1
        case .mountaineering, .trailRunning: sportFactor = 1.2
        }
        let heartRateContribution = min(12, max(0, heartRateLoad ?? 0) / 20)
        let center = min(96, max(4, sessionRPELoad / 15 * sportFactor + heartRateContribution))
        let provenance = MetricProvenance(
            source: .historicalModel,
            sourceName: "有效时长、session-RPE 与心率区间负荷恢复范围",
            confidence: .estimated,
            coverage: heartRateLoad == nil ? 0.5 : 1,
            sampledAt: completedAt,
            algorithmVersion: algorithmVersion
        )
        return MetricRange(
            value: center,
            lowerBound: max(2, center * 0.65),
            upperBound: min(120, max(center + 4, center * 1.5)),
            provenance: provenance
        )
    }

    private static func normalizedPauseIntervals(
        draft: SportSessionDraft,
        completedAt: Date
    ) -> [(start: Date, end: Date)] {
        var intervals = draft.pauseIntervals.compactMap { interval -> (Date, Date)? in
            let start = max(draft.startedAt, interval.startedAt)
            let end = min(completedAt, interval.endedAt)
            return end > start ? (start, end) : nil
        }
        if let pausedAt = draft.pausedAt {
            let start = max(draft.startedAt, pausedAt)
            if completedAt > start { intervals.append((start, completedAt)) }
        }
        intervals.sort { $0.0 < $1.0 }

        var merged: [(start: Date, end: Date)] = []
        for interval in intervals {
            guard let last = merged.last else {
                merged.append((interval.0, interval.1))
                continue
            }
            if interval.0 <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.1)
            } else {
                merged.append((interval.0, interval.1))
            }
        }
        return merged
    }

    private static func countHeartRateGaps(in samples: [WorkoutMetricSample]) -> Int {
        let valid = samples.filter { sample in
            guard let bpm = sample.heartRateBPM else { return false }
            return (40...220).contains(bpm)
        }
        return Dictionary(grouping: valid, by: { $0.provenance.sourceName }).values.reduce(0) { count, sourceSamples in
            let sorted = sourceSamples.sorted { $0.timestamp < $1.timestamp }
            return count + zip(sorted, sorted.dropFirst()).filter {
                $0.1.timestamp.timeIntervalSince($0.0.timestamp) > 15
            }.count
        }
    }

    private static func uniqueProvenance(_ values: [MetricProvenance]) -> [MetricProvenance] {
        var keys: Set<String> = []
        return values.filter { provenance in
            keys.insert("\(provenance.source.rawValue)|\(provenance.sourceName)").inserted
        }
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
