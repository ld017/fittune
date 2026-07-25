import Foundation

struct CardioEnergyInput {
    var modality: CardioModality
    var intensity: CardioIntensity
    var startedAt: Date
    var completedAt: Date
    var weightKg: Double
    var profile: UserProfile?
    var confirmedDistanceKm: Double?
    var sensorDistanceKm: Double?
    var workloadSegments: [CardioWorkloadSegment]
    var metricSamples: [WorkoutMetricSample]
    var deviceEstimateKcal: Double?
    var deviceEnergySource: MetricSource?
    var importedDeviceOnly: Bool
}

enum CardioEnergyEstimator {
    private struct Segment {
        var startedAt: Date
        var endedAt: Date
        var speedKph: Double?
        var inclinePercent: Double?
        var powerWatts: Double?
        var handrailSupport: HandrailSupport

        var seconds: Double { endedAt.timeIntervalSince(startedAt) }
    }

    private struct HeartRateInterval {
        var startedAt: Date
        var endedAt: Date
        var bpm: Double

        var seconds: Double { endedAt.timeIntervalSince(startedAt) }
    }

    static func estimate(_ input: CardioEnergyInput) -> EnergyEstimate {
        let durationSeconds = max(0, input.completedAt.timeIntervalSince(input.startedAt))
        guard durationSeconds > 0, input.weightKg > 0 else {
            return estimate(value: 0, spread: 0.25, method: "有氧输入不足", confidence: "低", diagnostics: diagnostics(input, primaryModel: "无可用模型", coverage: 0))
        }

        let segments = normalizedSegments(input)
        let fallback = metEnergy(input: input)
        let deviceComparison = usableDeviceEnergy(input)
        let hasSustainedHandrail = segments.contains { $0.handrailSupport == .sustained }
        let acsm = acsmCandidate(input: input, segments: segments)
        var warnings: [String] = []
        var requiredSpread = 0.0

        if let acsm, !hasSustainedHandrail {
            let distanceWarning = distanceWarning(input: input, segments: segments)
            if distanceWarning != nil {
                warnings.append(distanceWarning!)
                requiredSpread = 0.25
            }
            if segments.contains(where: { $0.handrailSupport == .occasional }) {
                warnings.append("偶尔扶把会增加坡度走耗能的不确定性。")
                requiredSpread = max(requiredSpread, 0.25)
            }
            let diagnostics = diagnostics(
                input,
                primaryModel: "ACSM 速度/坡度分段",
                coverage: acsm.coverage,
                warnings: warnings,
                comparison: deviceComparison
            )
            return estimate(
                value: acsm.kcal,
                spread: max(0.15, requiredSpread),
                method: acsm.method,
                confidence: acsm.coverage >= 0.8 ? "中高" : "中",
                diagnostics: diagnostics
            )
        }

        if hasSustainedHandrail, let acsm {
            warnings.append("持续扶把会降低坡度走的实际耗能；未扶把 ACSM \(acsm.kcal.rounded()) kcal 仅作上限参考。")
        }
        if let power = cyclingPowerCandidate(input: input, segments: segments) {
            let diagnostics = diagnostics(
                input,
                primaryModel: "骑行功率效率范围",
                coverage: power.coverage,
                warnings: warnings,
                comparison: deviceComparison
            )
            return EnergyEstimate(
                kilocalories: power.value,
                lowerBound: power.lower,
                upperBound: power.upper,
                method: "骑行功率效率模型（18%–25%）",
                confidence: power.coverage >= 0.8 ? "中高" : "中",
                diagnostics: diagnostics
            )
        }

        if let heartRate = heartRateCandidate(input: input, fallbackKcalPerMinute: fallback / (durationSeconds / 60)) {
            let diagnostics = diagnostics(
                input,
                primaryModel: "Keytel 心率 + MET 缺口填补",
                coverage: heartRate.coverage,
                warnings: warnings,
                comparison: deviceComparison
            )
            let result = estimate(value: heartRate.kcal, spread: heartRate.coverage >= 0.8 ? 0.20 : 0.25, method: "Keytel 心率 + 有氧 MET 缺口填补", confidence: heartRate.coverage >= 0.8 ? "中" : "低至中", diagnostics: diagnostics)
            return includingUnsupportedACSMUpperCheck(result, acsm: hasSustainedHandrail ? acsm : nil)
        }

        if input.importedDeviceOnly, let device = deviceComparison {
            return estimate(
                value: device,
                spread: 0.25,
                method: deviceMethod(source: input.deviceEnergySource),
                confidence: "中",
                diagnostics: diagnostics(input, primaryModel: "设备导入主动能量", coverage: 1, warnings: warnings)
            )
        }

        let diagnostics = diagnostics(
            input,
            primaryModel: "2024 Adult Compendium MET",
            coverage: 1,
            warnings: warnings,
            comparison: deviceComparison
        )
        let result = estimate(value: fallback, spread: hasSustainedHandrail ? 0.30 : 0.25, method: "2024 Adult Compendium MET", confidence: "低至中", diagnostics: diagnostics)
        return includingUnsupportedACSMUpperCheck(result, acsm: hasSustainedHandrail ? acsm : nil)
    }

    private static func normalizedSegments(_ input: CardioEnergyInput) -> [Segment] {
        var cursor = input.startedAt
        return input.workloadSegments
            .sorted { $0.startedAt < $1.startedAt }
            .compactMap { workload in
                let start = max(cursor, max(input.startedAt, workload.startedAt))
                let end = min(input.completedAt, workload.endedAt ?? input.completedAt)
                guard end > start else { return nil }
                cursor = end
                return Segment(
                    startedAt: start,
                    endedAt: end,
                    speedKph: workload.speedKph,
                    inclinePercent: workload.inclinePercent,
                    powerWatts: workload.powerWatts,
                    handrailSupport: workload.handrailSupport
                )
            }
    }

    private static func acsmCandidate(input: CardioEnergyInput, segments: [Segment]) -> (kcal: Double, coverage: Double, method: String)? {
        guard [.inclineWalking, .briskWalking, .running].contains(input.modality) else { return nil }
        let valid = segments.filter { segment in
            guard let speed = segment.speedKph else { return false }
            return (1...25).contains(speed)
        }
        let seconds = valid.reduce(0) { $0 + $1.seconds }
        guard seconds > 0 else { return nil }
        let usesRunning = valid.contains { input.modality == .running || ($0.speedKph ?? 0) >= 8 }
        let usesWalking = valid.contains { input.modality != .running && ($0.speedKph ?? 0) < 8 }
        let kcal = valid.reduce(0.0) { total, segment in
            let running = input.modality == .running || (segment.speedKph ?? 0) >= 8
            return total + acsmActiveKcal(
                speedKph: segment.speedKph ?? 0,
                inclinePercent: segment.inclinePercent ?? 0,
                minutes: segment.seconds / 60,
                weightKg: input.weightKg,
                running: running
            )
        } + metEnergy(input: input, seconds: input.completedAt.timeIntervalSince(input.startedAt) - seconds)
        let method: String
        if usesRunning && usesWalking { method = "ACSM 步行/跑步速度/坡度分段公式" }
        else if usesRunning { method = "ACSM 跑步速度/坡度分段公式" }
        else { method = "ACSM 步行速度/坡度分段公式" }
        return (kcal, min(1, seconds / input.completedAt.timeIntervalSince(input.startedAt)), method)
    }

    private static func acsmActiveKcal(speedKph: Double, inclinePercent: Double, minutes: Double, weightKg: Double, running: Bool) -> Double {
        let speed = speedKph * 1_000 / 60
        let grade = min(0.40, max(0, inclinePercent / 100))
        let netVO2 = running
            ? 0.2 * speed + 0.9 * speed * grade
            : 0.1 * speed + 1.8 * speed * grade
        return max(0, netVO2 * weightKg / 1_000 * 5 * minutes)
    }

    private static func cyclingPowerCandidate(input: CardioEnergyInput, segments: [Segment]) -> (value: Double, lower: Double, upper: Double, coverage: Double)? {
        guard input.modality == .cycling else { return nil }
        let powered = segments.filter { ($0.powerWatts ?? 0) > 0 }
        let seconds = powered.reduce(0) { $0 + $1.seconds }
        let duration = input.completedAt.timeIntervalSince(input.startedAt)
        guard seconds > 0 else { return nil }
        let powers = powered.compactMap(\.powerWatts)
        let mean = powers.reduce(0, +) / Double(powers.count)
        guard mean > 0, (powers.max() ?? mean) - (powers.min() ?? mean) <= mean * 0.10 else { return nil }

        let mechanicalKcal = powered.reduce(0.0) { $0 + ($1.powerWatts ?? 0) * $1.seconds } / 4_184
        let restingDuringPower = restingEnergy(input: input, seconds: seconds)
        let fallback = metEnergy(input: input, seconds: duration - seconds)
        return (
            max(0, mechanicalKcal / 0.215 - restingDuringPower) + fallback,
            max(0, mechanicalKcal / 0.25 - restingDuringPower) + fallback,
            max(0, mechanicalKcal / 0.18 - restingDuringPower) + fallback,
            min(1, seconds / duration)
        )
    }

    private static func heartRateCandidate(input: CardioEnergyInput, fallbackKcalPerMinute: Double) -> (kcal: Double, coverage: Double)? {
        guard let profile = input.profile else { return nil }
        let intervals = dominantHeartRateIntervals(input)
        let duration = input.completedAt.timeIntervalSince(input.startedAt)
        let coverage = intervals.reduce(0) { $0 + $1.seconds } / duration
        guard coverage >= 0.6 else { return nil }
        guard let sampleRate = TrainingEngine.heartRateActiveEnergy(averageHeartRate: intervals[0].bpm, minutes: 1, weightKg: input.weightKg, profile: profile), sampleRate >= 0 else { return nil }

        var kcal = 0.0
        var cursor = input.startedAt
        for interval in intervals {
            if interval.startedAt > cursor {
                kcal += fallbackKcalPerMinute * interval.startedAt.timeIntervalSince(cursor) / 60
            }
            let rate = TrainingEngine.heartRateActiveEnergy(averageHeartRate: interval.bpm, minutes: 1, weightKg: input.weightKg, profile: profile) ?? fallbackKcalPerMinute
            kcal += min(fallbackKcalPerMinute * 1.25, max(fallbackKcalPerMinute * 0.75, rate)) * interval.seconds / 60
            cursor = interval.endedAt
        }
        if cursor < input.completedAt {
            kcal += fallbackKcalPerMinute * input.completedAt.timeIntervalSince(cursor) / 60
        }
        return (kcal, min(1, coverage))
    }

    private static func dominantHeartRateIntervals(_ input: CardioEnergyInput) -> [HeartRateInterval] {
        let samples = input.metricSamples.compactMap { sample -> (Date, Double, String)? in
            guard let bpm = sample.heartRateBPM,
                  (60...210).contains(bpm),
                  sample.timestamp >= input.startedAt,
                  sample.timestamp <= input.completedAt else { return nil }
            return (sample.timestamp, bpm, sample.provenance.sourceName)
        }
        let candidates = Dictionary(grouping: samples, by: \.2).values.map { values -> [HeartRateInterval] in
            let sorted = values.sorted { $0.0 < $1.0 }
            return zip(sorted, sorted.dropFirst()).compactMap { left, right in
                let seconds = right.0.timeIntervalSince(left.0)
                guard seconds > 0, seconds <= 15 else { return nil }
                return HeartRateInterval(startedAt: left.0, endedAt: right.0, bpm: (left.1 + right.1) / 2)
            }
        }
        return candidates.max { left, right in
            left.reduce(0) { $0 + $1.seconds } < right.reduce(0) { $0 + $1.seconds }
        } ?? []
    }

    private static func metEnergy(input: CardioEnergyInput, seconds: Double? = nil) -> Double {
        TrainingEngine.netActiveEnergy(
            met: TrainingEngine.cardioMET(modality: input.modality, intensity: input.intensity),
            weightKg: input.weightKg,
            minutes: max(0, seconds ?? input.completedAt.timeIntervalSince(input.startedAt)) / 60
        )
    }

    private static func restingEnergy(input: CardioEnergyInput, seconds: Double) -> Double {
        let daily = input.profile.flatMap { TrainingEngine.restingEnergy(profile: $0, weightKg: input.weightKg) } ?? 24 * input.weightKg
        return max(0, daily * seconds / 86_400)
    }

    private static func includingUnsupportedACSMUpperCheck(_ estimate: EnergyEstimate, acsm: (kcal: Double, coverage: Double, method: String)?) -> EnergyEstimate {
        guard let acsm else { return estimate }
        var result = estimate
        result.upperBound = max(result.upperBound, acsm.kcal)
        return result
    }

    private static func distanceWarning(input: CardioEnergyInput, segments: [Segment]) -> String? {
        guard let confirmed = input.confirmedDistanceKm, confirmed > 0 else { return nil }
        let integrated = segments.reduce(0.0) { total, segment in
            total + (segment.speedKph ?? 0) * segment.seconds / 3_600
        }
        guard integrated > 0, abs(integrated - confirmed) / confirmed > 0.15 else { return nil }
        return "速度积分距离与确认距离相差超过 15%，已扩大不确定性范围。"
    }

    private static func usableDeviceEnergy(_ input: CardioEnergyInput) -> Double? {
        guard let value = input.deviceEstimateKcal, value > 0 else { return nil }
        return value
    }

    private static func diagnostics(_ input: CardioEnergyInput, primaryModel: String, coverage: Double, warnings: [String] = [], comparison: Double? = nil) -> EnergyEstimateDiagnostics {
        var inputs = ["体重", "训练时长", "项目", "强度"]
        if !input.workloadSegments.isEmpty { inputs.append("分段负荷") }
        if !input.metricSamples.isEmpty { inputs.append("心率样本") }
        if input.confirmedDistanceKm != nil { inputs.append("确认距离") }
        if comparison != nil { inputs.append("设备主动能量（对照）") }
        return EnergyEstimateDiagnostics(
            primaryModel: primaryModel,
            inputsUsed: inputs,
            warnings: warnings,
            comparisonEstimateKcal: comparison,
            dataCoverage: min(1, max(0, coverage))
        )
    }

    private static func estimate(value: Double, spread: Double, method: String, confidence: String, diagnostics: EnergyEstimateDiagnostics) -> EnergyEstimate {
        EnergyEstimate(
            kilocalories: max(0, value),
            lowerBound: max(0, value * (1 - spread)),
            upperBound: max(0, value * (1 + spread)),
            method: method,
            confidence: confidence,
            diagnostics: diagnostics
        )
    }

    private static func deviceMethod(source: MetricSource?) -> String {
        switch source {
        case .appleWatch: "Apple Watch 导入主动能量"
        case .manual: "手动导入主动能量"
        default: "设备导入主动能量"
        }
    }
}
