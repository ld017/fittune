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
