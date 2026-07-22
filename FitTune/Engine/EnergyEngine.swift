import Foundation

struct DailyEnergyReport: Equatable {
    var resting: MetricRange?
    var strength: MetricRange
    var cardio: MetricRange
    var steps: Int
    var walking: MetricRange
    var otherActive: MetricRange
    var active: MetricRange
    var total: MetricRange
    var totalIncludesWorkoutAndStepsTwice: Bool { false }
}

enum EnergyEngine {
    static let algorithmVersion = "1.0-energy-1"

    static func dailyReport(
        resting: MetricRange?,
        strength: [MetricRange],
        cardio: [MetricRange],
        steps: Int,
        stepEstimate: MetricRange?,
        measuredDailyActive: MetricRange?
    ) -> DailyEnergyReport {
        let strengthTotal = sum(strength, label: "力量训练分项")
        let cardioTotal = sum(cardio, label: "有氧训练分项")
        let walkingEstimate = stepEstimate ?? zero(label: "无步数数据", confidence: .unavailable)
        let knownActivity = strengthTotal.value + cardioTotal.value

        let active: MetricRange
        let walking: MetricRange
        let other: MetricRange
        if var measured = measuredDailyActive, measured.value >= 0 {
            measured.provenance.confidence = .measured
            measured.provenance.algorithmVersion = algorithmVersion
            active = measured
            let residual = max(0, measured.value - knownActivity)
            let walkingValue = min(walkingEstimate.value, residual)
            walking = scaled(walkingEstimate, value: walkingValue)
            other = range(
                value: max(0, residual - walkingValue),
                lower: 0,
                upper: max(0, measured.upperBound - strengthTotal.lowerBound - cardioTotal.lowerBound - walking.lowerBound),
                source: measured.provenance.source,
                name: "设备主动能量扣除已识别训练和步行后的剩余",
                confidence: .derived
            )
        } else {
            walking = walkingEstimate
            other = zero(label: "无其他主动能量数据", confidence: .unavailable)
            active = range(
                value: knownActivity + walking.value,
                lower: strengthTotal.lowerBound + cardioTotal.lowerBound + walking.lowerBound,
                upper: strengthTotal.upperBound + cardioTotal.upperBound + walking.upperBound,
                source: .phoneEstimate,
                name: "力量 + 有氧 + 步数分项估算",
                confidence: weakest([strengthTotal, cardioTotal, walking].map(\.provenance.confidence))
            )
        }

        let rest = resting ?? zero(label: "身体参数不足，静息能量不可用", confidence: .unavailable)
        let total = range(
            value: rest.value + active.value,
            lower: rest.lowerBound + active.lowerBound,
            upper: rest.upperBound + active.upperBound,
            source: active.provenance.source,
            name: "静息能量 + 去重后主动能量",
            confidence: weakest([rest.provenance.confidence, active.provenance.confidence])
        )
        return DailyEnergyReport(resting: resting, strength: strengthTotal, cardio: cardioTotal, steps: steps, walking: walking, otherActive: other, active: active, total: total)
    }

    static func metricRange(from estimate: EnergyEstimate, source: MetricSource) -> MetricRange {
        MetricRange(value: estimate.kilocalories, lowerBound: estimate.lowerBound, upperBound: estimate.upperBound, provenance: .init(source: source, sourceName: estimate.method, confidence: confidence(from: estimate.confidence), coverage: 1, algorithmVersion: algorithmVersion))
    }

    private static func sum(_ values: [MetricRange], label: String) -> MetricRange {
        guard !values.isEmpty else { return zero(label: label, confidence: .unavailable) }
        return range(value: values.reduce(0) { $0 + $1.value }, lower: values.reduce(0) { $0 + $1.lowerBound }, upper: values.reduce(0) { $0 + $1.upperBound }, source: values.first?.provenance.source ?? .unknown, name: label, confidence: weakest(values.map(\.provenance.confidence)))
    }

    private static func scaled(_ original: MetricRange, value: Double) -> MetricRange {
        guard original.value > 0 else { return zero(label: original.provenance.sourceName, confidence: original.provenance.confidence) }
        let factor = value / original.value
        return range(value: value, lower: original.lowerBound * factor, upper: original.upperBound * factor, source: original.provenance.source, name: original.provenance.sourceName, confidence: original.provenance.confidence)
    }

    private static func range(value: Double, lower: Double, upper: Double, source: MetricSource, name: String, confidence: DataConfidence) -> MetricRange {
        MetricRange(value: max(0, value), lowerBound: max(0, lower), upperBound: max(max(0, lower), upper), provenance: .init(source: source, sourceName: name, confidence: confidence, coverage: 1, algorithmVersion: algorithmVersion))
    }

    private static func zero(label: String, confidence: DataConfidence) -> MetricRange {
        range(value: 0, lower: 0, upper: 0, source: .phoneEstimate, name: label, confidence: confidence)
    }

    private static func weakest(_ values: [DataConfidence]) -> DataConfidence {
        let rank: [DataConfidence: Int] = [.measured: 3, .derived: 2, .estimated: 1, .unavailable: 0]
        return values.min { (rank[$0] ?? 0) < (rank[$1] ?? 0) } ?? .unavailable
    }

    private static func confidence(from text: String) -> DataConfidence {
        if text.contains("高") { return .measured }
        if text.contains("中") { return .derived }
        return .estimated
    }
}
