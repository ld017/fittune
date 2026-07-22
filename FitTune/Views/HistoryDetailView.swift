import SwiftUI

struct StrengthHistoryDetailView: View {
    let record: WorkoutRecord
    let bodyWeightKg: Double

    var body: some View {
        List {
            Section("训练信息") {
                LabeledContent("状态", value: record.resolvedCompletionStatus.title)
                LabeledContent("开始", value: record.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("完成组数", value: "\(record.sets.count)")
                if let snapshot = record.planSnapshot { LabeledContent("计划快照", value: "\(snapshot.split.title) · \(snapshot.sourcePlanRuleVersion)") }
            }
            Section("组明细") {
                ForEach(record.sets) { set in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(set.exerciseName) · \(set.resolvedSetKind.title)")
                        Text("第 \(set.setNumber) 组 · \(set.loadKg.formatted(.number.precision(.fractionLength(0...1)))) kg × \(set.reps) · RIR \(set.rir)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("总结") {
                NavigationLink("查看完整总结") {
                    WorkoutSummaryView(presentation: .init(title: record.sessionName, date: record.completedAt, summary: record.summary ?? SummaryEngine.strengthSummary(for: record, bodyWeightKg: bodyWeightKg)))
                }
            }
            if let revisions = record.summaryRevisions, !revisions.isEmpty {
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
    let record: CardioWorkoutRecord

    var body: some View {
        List {
            Section("训练信息") {
                LabeledContent("状态", value: (record.completionStatus ?? .completed).title)
                LabeledContent("开始", value: record.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("方式", value: record.modality.title)
                LabeledContent("强度", value: record.intensity.title)
                LabeledContent("时长", value: "\(record.durationMinutes) 分钟")
                if let distance = record.distanceKm { LabeledContent("距离", value: String(format: "%.2f km", distance)) }
                if let heartRate = record.averageHeartRate { LabeledContent("平均心率", value: "\(Int(heartRate.rounded())) bpm") }
                LabeledContent("主动消耗", value: "\(Int(record.activeEnergyKcal.rounded())) kcal")
                LabeledContent("数据来源", value: record.source)
                if let gap = record.dataGapReason { Label(gap, systemImage: "exclamationmark.triangle.fill").foregroundStyle(FitTheme.warning) }
            }
            if let samples = record.metricSamples, !samples.isEmpty {
                Section("采集详情") {
                    LabeledContent("样本", value: "\(samples.count)")
                    if let maxHeartRate = samples.compactMap(\.heartRateBPM).max() { LabeledContent("最大心率", value: "\(Int(maxHeartRate.rounded())) bpm") }
                    if let cadence = samples.compactMap(\.cadence).last { LabeledContent("末次步频/踏频", value: "\(Int(cadence.rounded())) /min") }
                    if let steps = samples.compactMap(\.steps).max() { LabeledContent("本次运动步数", value: "\(steps)") }
                }
            }
            Section("总结") {
                NavigationLink("查看完整总结") {
                    WorkoutSummaryView(presentation: .init(title: record.modality.title, date: record.date, summary: record.summary ?? SummaryEngine.cardioSummary(for: record)))
                }
            }
            if let revisions = record.summaryRevisions, !revisions.isEmpty {
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
        .navigationTitle(record.modality.title)
    }
}
