import Foundation

enum SummaryEngine {
    static let algorithmVersion = "1.2.0-workout-effect-1"

    static func strengthSummary(for record: WorkoutRecord, bodyWeightKg: Double, maximumHeartRate: Double? = nil) -> WorkoutSummary {
        let samples = record.metricSamples ?? []
        let heartRates = samples.compactMap(\.heartRateBPM)
        let working = record.sets.filter { $0.resolvedSetKind == .working }
        let warmups = record.sets.filter { $0.resolvedSetKind == .warmup }
        let validE1RMs = working.compactMap { set -> Double? in
            guard set.reps + set.rir <= 12, set.rir <= 4 else { return nil }
            return TrainingEngine.estimatedOneRepMax(loadKg: set.loadKg, reps: set.reps, rir: set.rir)
        }
        let bestE1RM = validE1RMs.max()
        let volume = working.reduce(0.0) { $0 + $1.loadKg * Double($1.reps) }
        let failureRate = working.isEmpty ? 0 : Double(working.filter { $0.rir == 0 }.count) / Double(working.count)
        let setDurations = validSetDurations(in: working, record: record)
        let actualRests = working.compactMap { rest -> Double? in
            guard let value = rest.actualRestSeconds, value >= 0 else { return nil }
            return value
        }
        let totalSetTime = setDurations.reduce(0, +)
        let totalRestTime = actualRests.reduce(0, +)
        let strength = StrengthSummaryMetrics(
            volumeLoadKg: volume,
            workingSetCount: working.count,
            warmupSetCount: warmups.count,
            failureRate: failureRate,
            bestE1RMKg: bestE1RM,
            relativeStrength: bestE1RM.flatMap { bodyWeightKg > 0 ? $0 / bodyWeightKg : nil },
            e1RMConfidence: bestE1RM == nil ? .unavailable : .derived,
            muscleLoad: muscleLoad(for: working),
            heartRateDecisions: record.heartRateDecisionLog,
            averageSetDurationSeconds: average(setDurations),
            averageActualRestSeconds: average(actualRests),
            workToRestRatio: totalRestTime > 0 && !setDurations.isEmpty && !actualRests.isEmpty
                ? totalSetTime / totalRestTime
                : nil,
            performanceRetention: TrainingEngine.comparableSetPerformanceRetention(for: working),
            heartRateResponses: record.sets.compactMap(\.heartRateResponse)
        )
        let energyMeasured = record.measuredActiveEnergyKcal.map { $0 > 0 } ?? false
        return WorkoutSummary(
            generatedAt: .now,
            algorithmVersion: algorithmVersion,
            averageHeartRate: average(heartRates),
            maximumHeartRate: heartRates.max(),
            activeEnergyKcal: energyRange(
                value: record.activeEnergyKcal,
                lowerBound: record.energyLowerBoundKcal,
                upperBound: record.energyUpperBoundKcal,
                source: energyMeasured ? .appleWatch : .historicalModel,
                sourceName: record.energyMethod ?? "力量训练估算",
                confidence: energyMeasured
                    ? .measured
                    : energyConfidence(method: record.energyMethod),
                algorithmVersion: record.energyAlgorithmVersion
            ),
            estimatedRecoveryHours: metricRange(value: Double(record.effect?.estimatedRecoveryHours ?? 24), spread: 0.30, source: .historicalModel, name: "训练量与接近力竭模型", confidence: .estimated),
            trainingEffect: record.effect.map { metricRange(value: Double(max($0.strengthScore, $0.hypertrophyScore)), spread: 0.15, source: .historicalModel, name: "训练效果规则", confidence: .derived) },
            dataCoverage: heartRateTimeCoverage(samples, startedAt: record.startedAt, completedAt: record.completedAt),
            strength: strength,
            heartRateCurve: samples,
            heartRateSourceName: dominantHeartRateSource(samples),
            heartRateConfidence: heartRateConfidence(samples),
            heartRateZones: heartRateZones(samples, maximumHeartRate: maximumHeartRate),
            heartRateGapCount: heartRateGapCount(samples)
        )
    }

    static func cardioSummary(
        for record: CardioWorkoutRecord,
        restingHeartRate: Double? = nil,
        maximumHeartRate: Double? = nil
    ) -> WorkoutSummary {
        let samples = record.metricSamples ?? []
        let heartRates = samples.compactMap(\.heartRateBPM)
        let cadences = samples.compactMap(\.cadence)
        let distance = record.distanceKm ?? samples.compactMap(\.distanceMeters).max().map { $0 / 1000 }
        let pace = distance.flatMap { $0 > 0 ? Double(record.durationMinutes * 60) / $0 : nil }
        let strokes = samples.compactMap(\.swimmingStrokeCount).max()
        let startedAt = record.date
        let completedAt = startedAt.addingTimeInterval(Double(record.durationMinutes) * 60)
        let intensity = HeartRateAnalysisEngine.intensitySummary(
            samples: samples,
            startedAt: startedAt,
            completedAt: completedAt,
            restingHeartRate: restingHeartRate,
            maximumHeartRate: maximumHeartRate
        )
        let drift = HeartRateAnalysisEngine.drift(
            samples: samples,
            workloads: record.workloadSegments ?? [],
            startedAt: startedAt,
            completedAt: completedAt
        )
        let cardio = CardioSummaryMetrics(
            distanceKm: distance,
            paceSecondsPerKm: pace,
            averageCadence: average(cadences),
            strokeCount: strokes,
            heartRateRecovery60: nil,
            vo2Max: nil,
            vo2MaxConfidence: .unavailable,
            secondsByIntensityZone: intensity?.secondsByZone,
            zoneLoadAU: intensity?.zoneLoadAU,
            aerobicBaseMinutes: intensity?.aerobicBaseMinutes,
            vigorousMinutes: intensity?.vigorousMinutes,
            fatOxidationOpportunityMinutes: intensity?.fatOxidationOpportunityMinutes,
            heartRateDriftPercent: drift?.percent,
            heartRateDriftConfidence: drift?.confidence,
            heartRateCoverage: intensity?.coverage,
            workloadCoverage: workoutCoverage(
                record.workloadSegments ?? [],
                startedAt: startedAt,
                completedAt: completedAt
            )
        )
        let source = sourceForCardio(record.source)
        let measured = record.energyMethod?.contains("设备实测") == true
            || (record.energyMethod == nil && source != .phoneEstimate)
        let confidence: DataConfidence = measured
            ? .measured
            : energyConfidence(method: record.energyMethod)
        return WorkoutSummary(
            generatedAt: .now,
            algorithmVersion: algorithmVersion,
            averageHeartRate: heartRates.isEmpty ? record.averageHeartRate : average(heartRates),
            maximumHeartRate: heartRates.max(),
            activeEnergyKcal: energyRange(
                value: record.activeEnergyKcal,
                lowerBound: record.energyLowerBoundKcal,
                upperBound: record.energyUpperBoundKcal,
                source: measured ? source : .historicalModel,
                sourceName: record.energyMethod ?? record.source,
                confidence: confidence,
                algorithmVersion: record.energyAlgorithmVersion
            ),
            estimatedRecoveryHours: metricRange(value: Double(record.effect?.estimatedRecoveryHours ?? 12), spread: 0.35, source: .historicalModel, name: "有氧负荷模型", confidence: .estimated),
            trainingEffect: record.effect.map { metricRange(value: Double($0.aerobicScore), spread: 0.15, source: .historicalModel, name: "有氧效果规则", confidence: .derived) },
            dataCoverage: intensity?.coverage,
            cardio: cardio,
            heartRateCurve: samples,
            heartRateSourceName: dominantHeartRateSource(samples),
            heartRateConfidence: heartRateConfidence(samples),
            heartRateZones: heartRateZones(samples, maximumHeartRate: maximumHeartRate),
            heartRateGapCount: heartRateGapCount(samples)
        )
    }

    private static func dominantHeartRateSource(_ samples: [WorkoutMetricSample]) -> String? {
        let names = samples.filter { $0.heartRateBPM != nil }.map { $0.provenance.sourceName }
        return Dictionary(grouping: names, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key
    }

    private static func heartRateConfidence(_ samples: [WorkoutMetricSample]) -> DataConfidence? {
        let values = samples.filter { $0.heartRateBPM != nil }.map { $0.provenance.confidence }
        guard !values.isEmpty else { return nil }
        if values.contains(.estimated) { return .estimated }
        if values.contains(.derived) { return .derived }
        return .measured
    }

    private static func heartRateGapCount(_ samples: [WorkoutMetricSample]) -> Int? {
        let dates = samples.filter { $0.heartRateBPM != nil }.map(\.timestamp).sorted()
        guard !dates.isEmpty else { return nil }
        return zip(dates, dates.dropFirst()).filter { $1.timeIntervalSince($0) > 15 }.count
    }

    private static func heartRateZones(_ samples: [WorkoutMetricSample], maximumHeartRate: Double?) -> [String: Double]? {
        guard let maximumHeartRate, maximumHeartRate > 0 else { return nil }
        let values = samples.compactMap(\.heartRateBPM)
        guard !values.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for bpm in values {
            let ratio = bpm / maximumHeartRate
            let zone = ratio < 0.60 ? "Z1" : ratio < 0.70 ? "Z2" : ratio < 0.80 ? "Z3" : ratio < 0.90 ? "Z4" : "Z5"
            counts[zone, default: 0] += 1
        }
        return counts.mapValues { Double($0) / Double(values.count) }
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func validSetDurations(in sets: [SetResult], record: WorkoutRecord) -> [Double] {
        sets.compactMap { set -> Double? in
            guard let startedAt = set.startedAt,
                  startedAt >= record.startedAt,
                  set.completedAt <= record.completedAt else {
                return nil
            }
            let duration = set.completedAt.timeIntervalSince(startedAt)
            return duration > 0 ? duration : nil
        }
    }

    private static func heartRateTimeCoverage(
        _ samples: [WorkoutMetricSample],
        startedAt: Date,
        completedAt: Date
    ) -> Double? {
        guard completedAt > startedAt else { return nil }
        let timestamps = samples.compactMap { sample -> Date? in
            guard let bpm = sample.heartRateBPM,
                  (40...220).contains(bpm),
                  sample.timestamp >= startedAt,
                  sample.timestamp <= completedAt else {
                return nil
            }
            return sample.timestamp
        }
        let sorted = timestamps.sorted()
        guard sorted.count >= 2 else { return nil }
        let covered = zip(sorted, sorted.dropFirst()).reduce(0.0) { total, pair in
            total + min(15, max(0, pair.1.timeIntervalSince(pair.0)))
        }
        return min(1, covered / completedAt.timeIntervalSince(startedAt))
    }

    private static func workoutCoverage(
        _ segments: [CardioWorkloadSegment],
        startedAt: Date,
        completedAt: Date
    ) -> Double? {
        let duration = completedAt.timeIntervalSince(startedAt)
        guard duration > 0, !segments.isEmpty else { return nil }
        let intervals = segments.compactMap { segment -> (start: Date, end: Date)? in
            let start = max(segment.startedAt, startedAt)
            let end = min(segment.endedAt ?? completedAt, completedAt)
            return end > start ? (start, end) : nil
        }
        .sorted { $0.start < $1.start }
        guard !intervals.isEmpty else { return nil }

        var covered = 0.0
        var current = intervals[0]
        for interval in intervals.dropFirst() {
            if interval.start <= current.end {
                current.end = max(current.end, interval.end)
            } else {
                covered += current.end.timeIntervalSince(current.start)
                current = interval
            }
        }
        covered += current.end.timeIntervalSince(current.start)
        return min(1, covered / duration)
    }

    private static func energyRange(
        value: Double?,
        lowerBound: Double?,
        upperBound: Double?,
        source: MetricSource,
        sourceName: String,
        confidence: DataConfidence,
        algorithmVersion: String?
    ) -> MetricRange? {
        guard let value else { return nil }
        let spread = confidence == .measured ? 0.05 : 0.25
        return MetricRange(
            value: value,
            lowerBound: lowerBound ?? max(0, value * (1 - spread)),
            upperBound: upperBound ?? value * (1 + spread),
            provenance: MetricProvenance(
                source: source,
                sourceName: sourceName,
                confidence: confidence,
                coverage: confidence == .measured ? 1 : 0.5,
                sampledAt: .now,
                algorithmVersion: algorithmVersion
            )
        )
    }

    private static func energyConfidence(method: String?) -> DataConfidence {
        guard let method else { return .estimated }
        return method.contains("心率") || method.contains("ACSM")
            ? .derived
            : .estimated
    }

    private static func metricRange(value: Double, spread: Double, source: MetricSource, name: String, confidence: DataConfidence) -> MetricRange {
        MetricRange(
            value: value,
            lowerBound: max(0, value * (1 - spread)),
            upperBound: value * (1 + spread),
            provenance: MetricProvenance(source: source, sourceName: name, confidence: confidence, coverage: confidence == .measured ? 1 : 0.5, sampledAt: .now, algorithmVersion: algorithmVersion)
        )
    }

    private static func sourceForCardio(_ value: String) -> MetricSource {
        let lower = value.lowercased()
        if lower.contains("华为") || lower.contains("huawei") { return .huaweiHealth }
        if lower.contains("watch") { return .appleWatch }
        if lower.contains("apple") || lower.contains("健康") { return .appleHealth }
        return .phoneEstimate
    }

    private static func muscleLoad(for sets: [SetResult]) -> [String: Double] {
        var result: [String: Double] = [:]
        for set in sets {
            let load = set.loadKg * Double(set.reps)
            let allocations: [(String, Double)]
            switch set.movementPattern {
            case .horizontalPush: allocations = [("胸", 0.60), ("肱三头", 0.25), ("前三角", 0.15)]
            case .horizontalPull: allocations = [("背", 0.65), ("肱二头", 0.20), ("后三角", 0.15)]
            case .verticalPush: allocations = [("肩", 0.65), ("肱三头", 0.25), ("上胸", 0.10)]
            case .verticalPull: allocations = [("背", 0.70), ("肱二头", 0.25), ("后三角", 0.05)]
            case .squat, .singleLeg: allocations = [("股四头", 0.55), ("臀", 0.30), ("后链", 0.15)]
            case .hinge: allocations = [("后链", 0.55), ("臀", 0.30), ("背", 0.15)]
            case .arms: allocations = [("手臂", 1)]
            case .core: allocations = [("核心", 1)]
            case .chestIsolation: allocations = [("胸", 1)]
            case .shoulderIsolation: allocations = [("肩", 1)]
            case .kneeFlexion: allocations = [("腘绳肌", 1)]
            case .calves: allocations = [("小腿", 1)]
            case .conditioning: allocations = [("全身", 1)]
            case .none: allocations = [("未分类", 1)]
            }
            for (muscle, ratio) in allocations { result[muscle, default: 0] += load * ratio }
        }
        return result
    }
}
