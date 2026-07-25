import SwiftUI

struct StrengthHistoryDetailView: View {
    @Environment(AppStore.self) private var store
    let record: WorkoutRecord
    let bodyWeightKg: Double

    var body: some View {
        let current = store.currentEnergyRecord(record)
        List {
            Section("训练信息") {
                LabeledContent("状态", value: current.resolvedCompletionStatus.title)
                LabeledContent("开始", value: current.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("完成组数", value: "\(current.sets.count)")
                LabeledContent(
                    "整场 session-RPE",
                    value: current.sessionRPE?.formatted(.number.precision(.fractionLength(0...1))) ?? "未记录"
                )
                if let snapshot = current.planSnapshot { LabeledContent("计划快照", value: "\(snapshot.split.title) · \(snapshot.sourcePlanRuleVersion)") }
            }
            Section("组明细") {
                ForEach(current.sets) { set in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(set.exerciseName) · \(set.resolvedSetKind.title)")
                        Text("第 \(set.setNumber) 组 · \(set.loadKg.formatted(.number.precision(.fractionLength(0...1)))) kg × \(set.reps) · RIR \(set.rir)")
                            .font(.caption).foregroundStyle(.secondary)
                        if let startedAt = set.startedAt {
                            Text("本组 \(formatDuration(set.completedAt.timeIntervalSince(startedAt)))\(set.actualRestSeconds.map { " · 实际休息 \(formatDuration($0))" } ?? "")")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let response = set.heartRateResponse {
                            Text(heartRateResponseText(response))
                                .font(.caption2)
                                .foregroundStyle(FitTheme.accentBlue)
                        }
                    }
                }
            }
            energySection(
                method: current.energyMethod,
                value: current.activeEnergyKcal,
                lower: current.energyLowerBoundKcal,
                upper: current.energyUpperBoundKcal,
                diagnostics: current.energyDiagnostics
            )
            Section("总结") {
                NavigationLink("查看完整总结") {
                    WorkoutSummaryView(presentation: .init(title: current.sessionName, date: current.completedAt, summary: current.summary ?? SummaryEngine.strengthSummary(for: current, bodyWeightKg: bodyWeightKg)))
                }
            }
            if let revisions = current.summaryRevisions, !revisions.isEmpty {
                Section("总结修订") {
                    ForEach(revisions) { revision in
                        VStack(alignment: .leading) {
                            Text(revision.reason)
                            Text(revision.revisedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(record.sessionName)
    }
}

struct CardioHistoryDetailView: View {
    @Environment(AppStore.self) private var store
    let record: CardioWorkoutRecord

    var body: some View {
        let current = store.currentEnergyRecord(record)
        List {
            Section("训练信息") {
                LabeledContent("状态", value: (current.completionStatus ?? .completed).title)
                LabeledContent("开始", value: current.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("方式", value: current.modality.title)
                LabeledContent("强度", value: current.intensity.title)
                LabeledContent("时长", value: "\(current.durationMinutes) 分钟")
                if let distance = current.distanceKm { LabeledContent("距离", value: String(format: "%.2f km", distance)) }
                if let heartRate = current.averageHeartRate { LabeledContent("平均心率", value: "\(Int(heartRate.rounded())) bpm") }
                LabeledContent("主动消耗", value: "\(Int(current.activeEnergyKcal.rounded())) kcal")
                LabeledContent("数据来源", value: current.source)
                if let gap = current.dataGapReason { Label(gap, systemImage: "exclamationmark.triangle.fill").foregroundStyle(FitTheme.warning) }
            }
            if let samples = current.metricSamples, !samples.isEmpty {
                Section("采集详情") {
                    LabeledContent("样本", value: "\(samples.count)")
                    if let maxHeartRate = samples.compactMap(\.heartRateBPM).max() { LabeledContent("最大心率", value: "\(Int(maxHeartRate.rounded())) bpm") }
                    if let cadence = samples.compactMap(\.cadence).last { LabeledContent("末次步频/踏频", value: "\(Int(cadence.rounded())) /min") }
                    if let steps = samples.compactMap(\.steps).max() { LabeledContent("本次运动步数", value: "\(steps)") }
                }
            }
            energySection(
                method: current.energyMethod,
                value: current.activeEnergyKcal,
                lower: current.energyLowerBoundKcal,
                upper: current.energyUpperBoundKcal,
                diagnostics: current.energyDiagnostics
            )
            Section("总结") {
                NavigationLink("查看完整总结") {
                    WorkoutSummaryView(presentation: .init(title: current.modality.title, date: current.date, summary: current.summary ?? SummaryEngine.cardioSummary(for: current)))
                }
            }
            if let revisions = current.summaryRevisions, !revisions.isEmpty {
                Section("总结修订") {
                    ForEach(revisions) { revision in
                        VStack(alignment: .leading) {
                            Text(revision.reason)
                            Text(revision.revisedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(current.modality.title)
    }
}

@ViewBuilder
private func energySection(
    method: String?,
    value: Double?,
    lower: Double?,
    upper: Double?,
    diagnostics: EnergyEstimateDiagnostics?
) -> some View {
    Section("主动能量模型") {
        VStack(alignment: .leading, spacing: 3) {
            Text("主模型")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(diagnostics?.primaryModel ?? method ?? "数据不足")
        }
        if let value {
            if let lower, let upper {
                LabeledContent(
                    "估算与区间",
                    value: "\(Int(value.rounded())) kcal · \(Int(lower.rounded()))–\(Int(upper.rounded())) kcal"
                )
            } else {
                LabeledContent("估算", value: "\(Int(value.rounded())) kcal")
            }
        }
        if let comparison = diagnostics?.comparisonEstimateKcal {
            LabeledContent("设备主动能量对照", value: "\(Int(comparison.rounded())) kcal")
        } else {
            LabeledContent("设备主动能量对照", value: "未提供")
        }
        ForEach(diagnostics?.warnings ?? [], id: \.self) { warning in
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(FitTheme.warning)
        }
    }
}

private func formatDuration(_ seconds: Double) -> String {
    let rounded = max(0, Int(seconds.rounded()))
    return rounded >= 60
        ? "\(rounded / 60)分 \(rounded % 60)秒"
        : "\(rounded)秒"
}

private func heartRateResponseText(_ response: SetHeartRateResponse) -> String {
    var values = ["峰值 \(Int(response.peakBPM.rounded())) bpm", "延后 \(response.peakDelaySeconds) 秒"]
    if let hrr60 = response.hrr60 {
        values.append("峰后 60 秒恢复 \(Int(hrr60.rounded())) bpm")
    }
    if let hrr120 = response.hrr120 {
        values.append("峰后 120 秒恢复 \(Int(hrr120.rounded())) bpm")
    }
    return values.joined(separator: " · ")
}
