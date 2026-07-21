import Foundation

enum RecoveryEngine {
    static let algorithmVersion = "1.0-recovery-1"

    static func assess(
        checkIn: RecoveryCheckIn,
        restingHeartRates: [RestingHeartRateSample],
        calendar: Calendar = .current
    ) -> RecoveryAssessmentResult {
        let dimensions: [(RecoveryDimension, RecoveryDimensionValue, Double, Bool)] = [
            (.sleep, checkIn.sleep, 0.30, true),
            (.soreness, checkIn.soreness, 0.25, false),
            (.stress, checkIn.stress, 0.20, false),
            (.motivation, checkIn.motivation, 0.25, true)
        ]
        let resolved = dimensions.compactMap { dimension, value, weight, highIsGood -> (RecoveryDimension, Double, RecoveryValueProvenance, Double, Bool)? in
            if let manual = value.manualValue {
                return (dimension, clamped(manual), .manual, weight, highIsGood)
            }
            if let automatic = value.automaticValue {
                return (dimension, clamped(automatic), value.provenance, weight, highIsGood)
            }
            if let explicit = value.resolvedValue {
                return (dimension, clamped(explicit), value.provenance, weight, highIsGood)
            }
            return nil
        }
        let availableWeight = resolved.reduce(0.0) { $0 + $1.3 }
        let contributions = resolved.map { dimension, value, provenance, weight, highIsGood in
            let normalized = highIsGood ? value * 20 : (6 - value) * 20
            let weighted = availableWeight > 0 ? normalized * weight / availableWeight : 0
            return RecoveryContribution(
                dimension: dimension,
                resolvedValue: value,
                provenance: provenance,
                weightedPoints: weighted
            )
        }

        let heartRate = restingHeartRateContext(on: checkIn.date, samples: restingHeartRates, calendar: calendar)
        let baseScore = contributions.reduce(0.0) { $0 + $1.weightedPoints }
        let score = min(100, max(0, Int(baseScore.rounded()) + heartRate.adjustment))
        let level: ReadinessLevel = score >= 72 ? .ready : (score >= 52 ? .moderate : .low)
        let summary: String
        let multiplier: Double
        let setReduction: Int
        switch level {
        case .ready:
            summary = "恢复指标支持按原计划训练，仍以热身和首组表现确认负荷。"
            multiplier = 1
            setReduction = 0
        case .moderate:
            summary = "恢复信号一般，建议保守选择首组重量并延长必要休息。"
            multiplier = 0.95
            setReduction = 0
        case .low:
            summary = "恢复信号偏低，建议降低负荷或容量；是否调整仍由你决定。"
            multiplier = 0.90
            setReduction = 1
        }
        return RecoveryAssessmentResult(
            score: score,
            level: level,
            summary: summary,
            loadMultiplier: multiplier,
            setReduction: setReduction,
            contributions: contributions,
            restingHeartRateBaseline: heartRate.baseline,
            currentRestingHeartRate: heartRate.current,
            restingHeartRateAdjustment: heartRate.adjustment
        )
    }

    private static func clamped(_ value: Double) -> Double {
        min(5, max(1, value))
    }

    private static func restingHeartRateContext(
        on date: Date,
        samples: [RestingHeartRateSample],
        calendar: Calendar
    ) -> (baseline: Double?, current: Double?, adjustment: Int) {
        let dayStart = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date.addingTimeInterval(86_400)
        let current = samples
            .filter { $0.date >= dayStart && $0.date < nextDay && $0.bpm > 0 }
            .sorted { $0.date > $1.date }
            .first?.bpm
        guard let windowStart = calendar.date(byAdding: .day, value: -21, to: dayStart) else {
            return (nil, current, 0)
        }
        let candidates = samples.filter { $0.date >= windowStart && $0.date < dayStart && $0.bpm > 0 }
        let grouped = Dictionary(grouping: candidates) { calendar.startOfDay(for: $0.date) }
        let dailyValues = grouped.values.map { daySamples in
            daySamples.map(\.bpm).reduce(0, +) / Double(daySamples.count)
        }
        guard dailyValues.count >= 7, let current else { return (nil, current, 0) }
        let sorted = dailyValues.sorted()
        let midpoint = sorted.count / 2
        let baseline = sorted.count.isMultiple(of: 2)
            ? (sorted[midpoint - 1] + sorted[midpoint]) / 2
            : sorted[midpoint]
        let delta = current - baseline
        let adjustment = delta >= 10 ? -10 : (delta >= 5 ? -5 : 0)
        return (baseline, current, adjustment)
    }
}
