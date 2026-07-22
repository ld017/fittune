import Foundation

enum SummaryEngine {
    static let algorithmVersion = "1.1.1-summary-hr-1"

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
        let strength = StrengthSummaryMetrics(
            volumeLoadKg: volume,
            workingSetCount: working.count,
            warmupSetCount: warmups.count,
            failureRate: failureRate,
            bestE1RMKg: bestE1RM,
            relativeStrength: bestE1RM.flatMap { bodyWeightKg > 0 ? $0 / bodyWeightKg : nil },
            e1RMConfidence: bestE1RM == nil ? .unavailable : .derived,
            muscleLoad: muscleLoad(for: working),
            heartRateDecisions: record.heartRateDecisionLog
        )
        let duration = max(1, record.completedAt.timeIntervalSince(record.startedAt))
        return WorkoutSummary(
            generatedAt: .now,
            algorithmVersion: algorithmVersion,
            averageHeartRate: average(heartRates),
            maximumHeartRate: heartRates.max(),
            activeEnergyKcal: energyRange(value: record.activeEnergyKcal, measured: record.measuredActiveEnergyKcal != nil, sourceName: record.energyMethod ?? "力量训练估算"),
            estimatedRecoveryHours: metricRange(value: Double(record.effect?.estimatedRecoveryHours ?? 24), spread: 0.30, source: .historicalModel, name: "训练量与接近力竭模型", confidence: .estimated),
            trainingEffect: record.effect.map { metricRange(value: Double(max($0.strengthScore, $0.hypertrophyScore)), spread: 0.15, source: .historicalModel, name: "训练效果规则", confidence: .derived) },
            dataCoverage: min(1, Double(heartRates.count) / max(1, duration / 5)),
            strength: strength,
            heartRateCurve: samples,
            heartRateSourceName: dominantHeartRateSource(samples),
            heartRateConfidence: heartRateConfidence(samples),
            heartRateZones: heartRateZones(samples, maximumHeartRate: maximumHeartRate),
            heartRateGapCount: heartRateGapCount(samples)
        )
    }

    static func cardioSummary(for record: CardioWorkoutRecord, maximumHeartRate: Double? = nil) -> WorkoutSummary {
        let samples = record.metricSamples ?? []
        let heartRates = samples.compactMap(\.heartRateBPM)
        let cadences = samples.compactMap(\.cadence)
        let distance = record.distanceKm ?? samples.compactMap(\.distanceMeters).max().map { $0 / 1000 }
        let pace = distance.flatMap { $0 > 0 ? Double(record.durationMinutes * 60) / $0 : nil }
        let strokes = samples.compactMap(\.swimmingStrokeCount).max()
        let cardio = CardioSummaryMetrics(
            distanceKm: distance,
            paceSecondsPerKm: pace,
            averageCadence: average(cadences),
            strokeCount: strokes,
            heartRateRecovery60: nil,
            vo2Max: nil,
            vo2MaxConfidence: .unavailable
        )
        let source = sourceForCardio(record.source)
        let confidence: DataConfidence = source == .phoneEstimate ? .estimated : .measured
        let duration = max(1, Double(record.durationMinutes * 60))
        return WorkoutSummary(
            generatedAt: .now,
            algorithmVersion: algorithmVersion,
            averageHeartRate: heartRates.isEmpty ? record.averageHeartRate : average(heartRates),
            maximumHeartRate: heartRates.max(),
            activeEnergyKcal: metricRange(value: record.activeEnergyKcal, spread: confidence == .measured ? 0.10 : 0.25, source: source, name: record.source, confidence: confidence),
            estimatedRecoveryHours: metricRange(value: Double(record.effect?.estimatedRecoveryHours ?? 12), spread: 0.35, source: .historicalModel, name: "有氧负荷模型", confidence: .estimated),
            trainingEffect: record.effect.map { metricRange(value: Double($0.aerobicScore), spread: 0.15, source: .historicalModel, name: "有氧效果规则", confidence: .derived) },
            dataCoverage: min(1, Double(heartRates.count) / max(1, duration / 5)),
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

    private static func energyRange(value: Double?, measured: Bool, sourceName: String) -> MetricRange? {
        value.map { metricRange(value: $0, spread: measured ? 0.10 : 0.25, source: measured ? .appleHealth : .phoneEstimate, name: sourceName, confidence: measured ? .measured : .estimated) }
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
