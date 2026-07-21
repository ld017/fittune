import SwiftUI
import Charts

struct WorkoutSummaryView: View {
    let presentation: WorkoutSummaryPresentation
    @Environment(\.dismiss) private var dismiss

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
            HStack(spacing: 10) {
                MetricChip(value: presentation.summary.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "—", label: "平均 bpm")
                MetricChip(value: presentation.summary.maximumHeartRate.map { "\(Int($0.rounded()))" } ?? "—", label: "最大 bpm", tint: FitTheme.danger)
                MetricChip(value: presentation.summary.dataCoverage.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", label: "数据覆盖", tint: FitTheme.accentBlue)
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
            HStack(spacing: 8) {
                MetricChip(value: "\(value.workingSetCount)", label: "正式组")
                MetricChip(value: "\(value.warmupSetCount)", label: "热身组", tint: FitTheme.warning)
                MetricChip(value: "\(Int((value.failureRate * 100).rounded()))%", label: "正式组力竭率", tint: FitTheme.danger)
            }
            Text("有效训练量 \(Int(value.volumeLoadKg.rounded())) kg")
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
}
