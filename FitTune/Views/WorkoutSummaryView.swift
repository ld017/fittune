import SwiftUI
import Charts

struct WorkoutSummaryView: View {
    let presentation: WorkoutSummaryPresentation
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    heartRateCard
                    if let strength = presentation.summary.strength { strengthCard(strength) }
                    if let cardio = presentation.summary.cardio { cardioCard(cardio) }
                    estimateCard
                    provenanceCard
                }
                .padding(18)
            }
            .background(FitBackground())
            .navigationTitle("训练总结")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 58)).foregroundStyle(FitTheme.accent)
            Text(presentation.title).font(.title.bold())
            Text(presentation.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: metricColumns(spacing: 10), spacing: 10) {
                MetricChip(value: presentation.summary.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "—", label: "平均 bpm")
                    .frame(minHeight: 72)
                MetricChip(value: presentation.summary.maximumHeartRate.map { "\(Int($0.rounded()))" } ?? "—", label: "最大 bpm", tint: FitTheme.danger)
                    .frame(minHeight: 72)
                MetricChip(value: presentation.summary.dataCoverage.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", label: "数据覆盖", tint: FitTheme.accentBlue)
                    .frame(minHeight: 72)
            }
            if let source = presentation.summary.heartRateSourceName {
                Text("心率来源：\(source) · \(confidenceText(presentation.summary.heartRateConfidence ?? .estimated))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let zones = presentation.summary.heartRateZones {
                Text(zones.sorted(by: { $0.key < $1.key }).map { "\($0.key) \(Int(($0.value * 100).rounded()))%" }.joined(separator: " · "))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .fitCard(padding: 20)
    }

    @ViewBuilder
    private var heartRateCard: some View {
        let points = (presentation.summary.heartRateCurve ?? []).compactMap { sample in
            sample.heartRateBPM.map { (sample.timestamp, $0) }
        }
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                Text("心率曲线").font(.headline)
                Chart(Array(points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("时间", point.0), y: .value("bpm", point.1))
                        .foregroundStyle(FitTheme.danger)
                }
                .frame(height: 170)
            }
            .fitCard()
        }
    }

    private func strengthCard(_ value: StrengthSummaryMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("力量训练表现").font(.headline)
            LazyVGrid(columns: metricColumns(spacing: 8), spacing: 8) {
                MetricChip(value: "\(value.workingSetCount)", label: "正式组")
                MetricChip(value: "\(value.warmupSetCount)", label: "热身组", tint: FitTheme.warning)
                MetricChip(value: "\(Int((value.failureRate * 100).rounded()))%", label: "正式组力竭率", tint: FitTheme.danger)
            }
            if let sessionRPE = matchingStrengthRecord?.sessionRPE {
                LabeledContent("整场 session-RPE", value: sessionRPE.formatted(.number.precision(.fractionLength(0...1))))
            } else {
                LabeledContent("整场 session-RPE", value: "未记录")
                    .foregroundStyle(FitTheme.warning)
            }
            Text("有效训练量 \(Int(value.volumeLoadKg.rounded())) kg")
            if let target = value.targetWorkingSetCount,
               let completion = value.targetSetCompletion {
                LabeledContent("目标正式组完成", value: "\(value.workingSetCount)/\(target) · \(completion.formatted(.percent.precision(.fractionLength(0))))")
            }
            if let e1RM = value.bestE1RMKg {
                Text("最佳估算 1RM \(e1RM.formatted(.number.precision(.fractionLength(1)))) kg · \(confidenceText(value.e1RMConfidence))")
                    .foregroundStyle(FitTheme.accentBlue)
            } else {
                Text("e1RM 不可用：高次数或输入范围不适合可靠估算。")
                    .foregroundStyle(FitTheme.warning)
            }
            ForEach(value.muscleLoad.sorted(by: { $0.value > $1.value }).prefix(4), id: \.key) { item in
                LabeledContent(item.key, value: "\(Int(item.value.rounded())) kg·次")
                    .font(.caption)
            }
            if value.averageSetDurationSeconds != nil
                || value.averageActualRestSeconds != nil
                || value.workToRestRatio != nil
                || value.performanceRetention != nil {
                Divider()
                Text("真实训练时间线").font(.subheadline.bold())
                if let seconds = value.averageSetDurationSeconds {
                    LabeledContent("平均每组", value: durationText(seconds))
                }
                if let seconds = value.averageActualRestSeconds {
                    LabeledContent("平均实际休息", value: durationText(seconds))
                }
                if let ratio = value.workToRestRatio {
                    LabeledContent("训练 : 休息", value: "1 : \((1 / max(ratio, 0.001)).formatted(.number.precision(.fractionLength(1))))")
                }
                if let retention = value.performanceRetention {
                    LabeledContent("可比组表现保留", value: retention.formatted(.percent.precision(.fractionLength(0))))
                }
            }
            if let responseSets = value.heartRateResponseSets, !responseSets.isEmpty {
                Divider()
                Text("逐组峰值与恢复").font(.subheadline.bold())
                ForEach(Array(responseSets.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(item.exerciseName) · 第 \(item.setNumber) 组 · 峰值 \(Int(item.response.peakBPM.rounded())) bpm · 延后 \(item.response.peakDelaySeconds) 秒")
                            .font(.caption.bold().monospacedDigit())
                        Text(heartRateRecoveryText(item.response))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let responses = value.heartRateResponses, !responses.isEmpty {
                Divider()
                Text("逐组峰值与恢复").font(.subheadline.bold())
                ForEach(Array(responses.enumerated()), id: \.offset) { index, response in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("恢复记录 \(index + 1) · 峰值 \(Int(response.peakBPM.rounded())) bpm · 延后 \(response.peakDelaySeconds) 秒")
                            .font(.caption.bold().monospacedDigit())
                        Text(heartRateRecoveryText(response))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let decisions = value.heartRateDecisions, !decisions.isEmpty {
                Divider()
                Text("心率建议记录").font(.subheadline.bold())
                ForEach(decisions) { decision in
                    Text("\(decision.secondsAfterSet) 秒恢复 \(Int(decision.recoveryBPM.rounded())) bpm · \(decision.effect)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .fitCard()
    }

    private func cardioCard(_ value: CardioSummaryMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("有氧表现").font(.headline)
            if let distance = value.distanceKm { LabeledContent("距离", value: String(format: "%.2f km", distance)) }
            if let pace = value.paceSecondsPerKm { LabeledContent("平均配速", value: "\(Int(pace) / 60)'\(String(format: "%02d", Int(pace) % 60))\" /km") }
            if let cadence = value.averageCadence { LabeledContent("平均步频/踏频", value: "\(Int(cadence.rounded())) /min") }
            if let strokes = value.strokeCount { LabeledContent("划水次数", value: "\(Int(strokes.rounded()))") }
            if let zones = value.secondsByIntensityZone {
                Divider()
                Text("心率强度分布").font(.subheadline.bold())
                ForEach(HeartRateIntensityZone.allCases, id: \.self) { zone in
                    if let seconds = zones[zone], seconds > 0 {
                        let percentage = value.percentageByIntensityZone?[zone] ?? 0
                        LabeledContent(
                            intensityZoneTitle(zone),
                            value: "\(minutesText(seconds / 60)) · \(percentage.formatted(.percent.precision(.fractionLength(0))))"
                        )
                        .font(.caption)
                    }
                }
                Text(value.usedHeartRateReserve == true ? "强度方法：心率储备 HRR" : "强度方法：估算最大心率 %HRmax")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let zoneLoad = value.zoneLoadAU {
                LabeledContent("心率区间负荷", value: "\(zoneLoad.formatted(.number.precision(.fractionLength(1)))) AU")
            }
            if let minutes = value.aerobicBaseMinutes {
                LabeledContent("有氧基础时间", value: minutesText(minutes))
            }
            if let minutes = value.vigorousMinutes {
                LabeledContent("较高强度时间", value: minutesText(minutes))
            }
            if let minutes = value.fatOxidationOpportunityMinutes {
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent("脂肪氧化机会窗口", value: minutesText(minutes))
                    Text("仅表示处于个人 HRR 40–65% 的时间，不等于脂肪克数。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let drift = value.heartRateDriftPercent {
                LabeledContent(
                    "稳定负荷心率漂移",
                    value: "\(drift.formatted(.number.precision(.fractionLength(1))))% · \(confidenceText(value.heartRateDriftConfidence ?? .estimated))"
                )
            }
            if let coverage = value.workloadCoverage {
                LabeledContent("专项负荷覆盖", value: coverage.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption)
            }
            Text(value.vo2Max == nil ? "数据条件不足，未强行生成 VO₂max。" : "VO₂max \(value.vo2Max!.formatted(.number.precision(.fractionLength(1))))")
                .font(.caption).foregroundStyle(value.vo2Max == nil ? FitTheme.warning : FitTheme.accent)
        }
        .fitCard()
    }

    private var estimateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("效果与恢复").font(.headline)
            metricRangeRow("主动消耗", presentation.summary.activeEnergyKcal, unit: "kcal")
            metricRangeRow("预计恢复", presentation.summary.estimatedRecoveryHours, unit: "小时")
            metricRangeRow("训练效果", presentation.summary.trainingEffect, unit: "/100")
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("主动能量主模型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(energyDiagnostics?.primaryModel ?? presentation.summary.activeEnergyKcal?.provenance.sourceName ?? "数据不足")
            }
            if let coverage = energyDiagnostics?.dataCoverage {
                LabeledContent("模型数据覆盖", value: coverage.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption)
            }
            if let comparison = energyDiagnostics?.comparisonEstimateKcal {
                LabeledContent("设备主动能量对照", value: "\(Int(comparison.rounded())) kcal")
                    .font(.caption)
            } else {
                LabeledContent("设备主动能量对照", value: "未提供")
                    .font(.caption)
            }
            if let warnings = energyDiagnostics?.warnings, !warnings.isEmpty {
                ForEach(warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(FitTheme.warning)
                }
            }
        }
        .fitCard()
    }

    private var provenanceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("数据来源与限制", systemImage: "info.circle.fill").font(.headline)
            Text("所有结果均显示合理区间、来源和可信度。热量、恢复时间、训练效果与 e1RM 是带假设的估计，不是医疗诊断。")
                .font(.caption).foregroundStyle(.secondary)
            Text("算法版本：\(presentation.summary.algorithmVersion)").font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
        .fitCard()
    }

    @ViewBuilder
    private func metricRangeRow(_ title: String, _ range: MetricRange?, unit: String) -> some View {
        if let range {
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent(title, value: "\(Int(range.value.rounded())) \(unit)")
                Text("\(Int(range.lowerBound.rounded()))–\(Int(range.upperBound.rounded())) \(unit) · \(range.provenance.sourceName) · \(confidenceText(range.provenance.confidence))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            LabeledContent(title, value: "数据不足")
        }
    }

    private func confidenceText(_ value: DataConfidence) -> String {
        switch value {
        case .measured: "实测/高可信度"
        case .derived: "推导/中可信度"
        case .estimated: "估算/较低可信度"
        case .unavailable: "不可用"
        }
    }

    private var matchingStrengthRecord: WorkoutRecord? {
        guard presentation.summary.strength != nil,
              let record = store.workoutHistory.first(where: {
                  $0.sessionName == presentation.title
                      && abs($0.completedAt.timeIntervalSince(presentation.date)) < 2
              }) else { return nil }
        return store.currentEnergyRecord(record)
    }

    private var matchingCardioRecord: CardioWorkoutRecord? {
        guard presentation.summary.cardio != nil,
              let record = store.cardioWorkouts.first(where: {
                  $0.modality.title == presentation.title
                      && abs($0.date.timeIntervalSince(presentation.date)) < 2
              }) else { return nil }
        return store.currentEnergyRecord(record)
    }

    private var energyDiagnostics: EnergyEstimateDiagnostics? {
        matchingStrengthRecord?.energyDiagnostics ?? matchingCardioRecord?.energyDiagnostics
    }

    private func metricColumns(spacing: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: spacing),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 3
        )
    }

    private func intensityZoneTitle(_ zone: HeartRateIntensityZone) -> String {
        switch zone {
        case .veryLight: "很轻"
        case .light: "轻"
        case .moderate: "中等"
        case .vigorous: "较高"
        case .nearMaximum: "接近最大"
        }
    }

    private func minutesText(_ minutes: Double) -> String {
        "\(minutes.formatted(.number.precision(.fractionLength(1)))) 分钟"
    }

    private func durationText(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        return rounded >= 60
            ? "\(rounded / 60)分 \(rounded % 60)秒"
            : "\(rounded)秒"
    }

    private func heartRateRecoveryText(_ response: SetHeartRateResponse) -> String {
        var values: [String] = []
        if let hrr60 = response.hrr60 {
            values.append("峰后 60 秒恢复 \(Int(hrr60.rounded())) bpm")
        }
        if let hrr120 = response.hrr120 {
            values.append("峰后 120 秒恢复 \(Int(hrr120.rounded())) bpm")
        }
        return values.isEmpty ? "恢复样本不足" : values.joined(separator: " · ")
    }
}
