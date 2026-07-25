import Foundation

enum StrengthEnergyEstimator {
    private static let compoundPatterns: Set<MovementPattern> = [
        .squat, .hinge, .horizontalPush, .horizontalPull,
        .verticalPush, .verticalPull, .singleLeg
    ]

    private struct HeartRateInterval {
        var startedAt: Date
        var endedAt: Date
        var bpm: Double

        var seconds: Double { endedAt.timeIntervalSince(startedAt) }
    }

    private struct CompletedPause {
        var startedAt: Date
        var endedAt: Date

        var seconds: Double { endedAt.timeIntervalSince(startedAt) }
    }

    static func estimate(
        record: WorkoutRecord,
        weightKg: Double,
        profile: UserProfile?
    ) -> EnergyEstimate {
        let wallClockSeconds = max(0, record.completedAt.timeIntervalSince(record.startedAt))
        let completedPauses = completedPauses(record.pauseIntervals ?? [], record: record)
        let pauseSeconds = completedPauses.reduce(0) { $0 + $1.seconds }
        let effectiveSeconds = max(0, wallClockSeconds - pauseSeconds)
        let workingSets = record.sets.filter { $0.resolvedSetKind != .warmup }
        let effectiveMinutes = effectiveSeconds / 60
        let density = Double(workingSets.count) / max(effectiveMinutes, 1)
        let compoundCount = workingSets.filter(isCompound).count
        let compoundShare = Double(compoundCount) / Double(max(workingSets.count, 1))
        let met = structuralMET(
            workingSetCount: workingSets.count,
            density: density,
            compoundShare: compoundShare,
            sessionRPE: record.sessionRPE
        )
        let structuralKcal = validInput(wallClockSeconds: wallClockSeconds, effectiveSeconds: effectiveSeconds, weightKg: weightKg)
            ? TrainingEngine.netActiveEnergy(met: met, weightKg: weightKg, minutes: effectiveMinutes)
            : 0
        let heartRate = heartRateComparison(
            record: record,
            weightKg: weightKg,
            profile: profile,
            structuralKcal: structuralKcal,
            effectiveSeconds: effectiveSeconds,
            pauses: completedPauses
        )
        let center = heartRate?.kcal ?? structuralKcal
        let hasTimeline = !workingSets.isEmpty && workingSets.allSatisfy { $0.startedAt != nil }
        let spread = record.sessionRPE == nil || !hasTimeline ? 0.35 : 0.25
        var warnings = ["EPOC 未计入本次主动热量"]
        if record.sessionRPE == nil { warnings.append("缺少真实 session-RPE，已扩大不确定性范围。") }
        if !hasTimeline { warnings.append("缺少完整正式组时间线，已扩大不确定性范围。") }

        var inputs = [
            "体重：\(weightKg.formatted(.number.precision(.fractionLength(1)))) kg",
            "有效训练时长：\(effectiveMinutes.formatted(.number.precision(.fractionLength(1)))) min",
            "已完成暂停：\(pauseSeconds.formatted(.number.precision(.fractionLength(1)))) s",
            "正式组数量：\(workingSets.count)",
            "正式组密度：\(density.formatted(.number.precision(.fractionLength(2)))) 组/min",
            "复合组占比：\(compoundShare.formatted(.percent.precision(.fractionLength(0))))"
        ]
        if record.sessionRPE != nil { inputs.append("真实 session-RPE") }
        if heartRate != nil { inputs.append("心率样本") }
        if record.deviceActiveEnergyEstimateKcal != nil || record.measuredActiveEnergyKcal != nil {
            inputs.append("设备主动能量（对照）")
        }

        return EnergyEstimate(
            kilocalories: center,
            lowerBound: max(0, center * (1 - spread)),
            upperBound: max(0, center * (1 + spread)),
            method: "2024 Adult Compendium 力量训练结构模型",
            confidence: spread == 0.25 ? "中" : "低至中",
            diagnostics: EnergyEstimateDiagnostics(
                primaryModel: "2024 Adult Compendium 力量训练（\(met.formatted(.number.precision(.fractionLength(1)))) MET）",
                inputsUsed: inputs,
                warnings: warnings,
                comparisonEstimateKcal: deviceComparison(record),
                dataCoverage: heartRate?.coverage ?? (hasTimeline ? 1 : 0)
            )
        )
    }

    private static func validInput(wallClockSeconds: Double, effectiveSeconds: Double, weightKg: Double) -> Bool {
        wallClockSeconds > 0 && effectiveSeconds > 0 && weightKg > 0
    }

    private static func completedPauses(_ intervals: [WorkoutPauseInterval], record: WorkoutRecord) -> [CompletedPause] {
        let clipped = intervals.compactMap { interval -> CompletedPause? in
            guard let endedAt = interval.endedAt else { return nil }
            let start = max(record.startedAt, interval.startedAt)
            let end = min(record.completedAt, endedAt)
            guard end > start else { return nil }
            return CompletedPause(startedAt: start, endedAt: end)
        }.sorted { $0.startedAt < $1.startedAt }

        var merged: [CompletedPause] = []
        for pause in clipped {
            if let last = merged.last, pause.startedAt <= last.endedAt {
                merged[merged.count - 1].endedAt = max(last.endedAt, pause.endedAt)
            } else {
                merged.append(pause)
            }
        }
        return merged
    }

    private static func structuralMET(
        workingSetCount: Int,
        density: Double,
        compoundShare: Double,
        sessionRPE: Double?
    ) -> Double {
        if workingSetCount <= 4 || density < 0.08 { return 3.0 }
        if (sessionRPE ?? 0) >= 8,
           workingSetCount >= 10,
           density >= 0.15,
           compoundShare >= 0.5 {
            return 6.0
        }
        return 3.5
    }

    private static func isCompound(_ set: SetResult) -> Bool {
        set.isCompound ?? set.movementPattern.map { compoundPatterns.contains($0) } ?? false
    }

    private static func deviceComparison(_ record: WorkoutRecord) -> Double? {
        [record.deviceActiveEnergyEstimateKcal, record.measuredActiveEnergyKcal]
            .compactMap { $0 }
            .first { $0 > 0 }
    }

    private static func heartRateComparison(
        record: WorkoutRecord,
        weightKg: Double,
        profile: UserProfile?,
        structuralKcal: Double,
        effectiveSeconds: Double,
        pauses: [CompletedPause]
    ) -> (kcal: Double, coverage: Double)? {
        guard let profile,
              effectiveSeconds > 0,
              let samples = record.metricSamples else { return nil }
        let intervals = dominantHeartRateIntervals(
            samples,
            startedAt: record.startedAt,
            completedAt: record.completedAt,
            pauses: pauses
        )
        let coverage = intervals.reduce(0) { $0 + $1.seconds } / effectiveSeconds
        guard coverage >= 0.6,
              let first = intervals.first,
              TrainingEngine.heartRateActiveEnergy(
                averageHeartRate: first.bpm,
                minutes: 1,
                weightKg: weightKg,
                profile: profile
              ) != nil else { return nil }

        let structuralRate = structuralKcal / (effectiveSeconds / 60)
        var heartRateKcal = structuralKcal
        for interval in intervals {
            guard let rate = TrainingEngine.heartRateActiveEnergy(
                averageHeartRate: interval.bpm,
                minutes: 1,
                weightKg: weightKg,
                profile: profile
            ) else { continue }
            heartRateKcal += (rate - structuralRate) * interval.seconds / 60
        }
        let lower = structuralKcal * 0.85
        let upper = structuralKcal * 1.15
        return (min(upper, max(lower, heartRateKcal)), min(1, coverage))
    }

    private static func dominantHeartRateIntervals(
        _ samples: [WorkoutMetricSample],
        startedAt: Date,
        completedAt: Date,
        pauses: [CompletedPause]
    ) -> [HeartRateInterval] {
        let valid = samples.compactMap { sample -> (date: Date, bpm: Double, source: String)? in
            guard let bpm = sample.heartRateBPM,
                  (60...210).contains(bpm),
                  sample.timestamp >= startedAt,
                  sample.timestamp <= completedAt else { return nil }
            return (sample.timestamp, bpm, sample.provenance.sourceName)
        }
        let candidates = Dictionary(grouping: valid, by: \.source).values.map { values -> [HeartRateInterval] in
            let sorted = values.sorted { $0.date < $1.date }
            let segments = zip(sorted, sorted.dropFirst()).map { left, right -> [HeartRateInterval] in
                let seconds = right.date.timeIntervalSince(left.date)
                guard seconds > 0, seconds <= 15 else { return [] }
                let interval = HeartRateInterval(startedAt: left.date, endedAt: right.date, bpm: (left.bpm + right.bpm) / 2)
                return activeSegments(of: interval, excluding: pauses)
            }
            return segments.flatMap { $0 }
        }
        return candidates.max { left, right in
            left.reduce(0) { $0 + $1.seconds } < right.reduce(0) { $0 + $1.seconds }
        } ?? []
    }

    private static func activeSegments(
        of interval: HeartRateInterval,
        excluding pauses: [CompletedPause]
    ) -> [HeartRateInterval] {
        var cursor = interval.startedAt
        var segments: [HeartRateInterval] = []
        for pause in pauses where pause.endedAt > cursor {
            guard pause.startedAt < interval.endedAt else { break }
            let activeEnd = min(interval.endedAt, pause.startedAt)
            if activeEnd > cursor {
                segments.append(HeartRateInterval(startedAt: cursor, endedAt: activeEnd, bpm: interval.bpm))
            }
            cursor = max(cursor, pause.endedAt)
            if cursor >= interval.endedAt { return segments }
        }
        if cursor < interval.endedAt {
            segments.append(HeartRateInterval(startedAt: cursor, endedAt: interval.endedAt, bpm: interval.bpm))
        }
        return segments
    }
}
