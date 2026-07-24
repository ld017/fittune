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
                if let snapshot = current.planSnapshot { LabeledContent("计划快照", value: "\(snapshot.split.title) · \(snapshot.sourcePlanRuleVersion)") }
            }
            Section("组明细") {
                ForEach(current.sets) { set in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(set.exerciseName) · \(set.resolvedSetKind.title)")
                        Text("第 \(set.setNumber) 组 · \(set.loadKg.formatted(.number.precision(.fractionLength(0...1)))) kg × \(set.reps) · RIR \(set.rir)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
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
