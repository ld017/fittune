import Charts
import SwiftUI

struct SportHistoryDetailView: View {
    let record: SportSessionRecord

    var body: some View {
        ZStack {
            FitBackground()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: record.kind.symbol).font(.system(size: 42, weight: .bold)).foregroundStyle(FitTheme.accent)
                        Text(record.kind.title).font(.largeTitle.bold())
                        Text(record.completedAt.formatted(date: .complete, time: .shortened)).foregroundStyle(FitTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity).fitCard(padding: 22)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        MetricChip(value: "\(Int(record.analysis.effectiveDurationSeconds / 60))", label: "有效分钟")
                        MetricChip(value: "\(Int(record.analysis.sessionRPELoadAU.rounded()))", label: "训练负荷 AU", tint: FitTheme.accentBlue)
                        MetricChip(value: "\(Int(record.analysis.activeEnergyKcal.value.rounded()))", label: "主动热量 kcal", tint: FitTheme.warning)
                        MetricChip(value: record.analysis.maximumHeartRate.map { "\(Int($0.rounded()))" } ?? "—", label: "最大心率 bpm", tint: FitTheme.danger)
                        if let distance = record.analysis.distanceMeters { MetricChip(value: String(format: "%.2f", distance / 1_000), label: "距离 km") }
                        if let gain = record.analysis.elevationGainMeters { MetricChip(value: "\(Int(gain.rounded()))", label: "累计爬升 m") }
                    }

                    if heartRateSamples.count >= 2 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("心率曲线").font(.headline)
                            Chart(heartRateSamples) { sample in
                                LineMark(x: .value("时间", sample.timestamp), y: .value("心率", sample.heartRateBPM ?? 0))
                                    .foregroundStyle(FitTheme.danger)
                                    .interpolationMethod(.catmullRom)
                            }
                            .frame(height: 180)
                        }
                        .fitCard()
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text("本次总结").font(.headline)
                        Text(record.summary)
                        Text("恢复建议：约 \(Int(record.analysis.estimatedRecoveryHours.lowerBound.rounded()))–\(Int(record.analysis.estimatedRecoveryHours.upperBound.rounded())) 小时")
                        Text("数据来源：\(record.analysis.provenance.map(\.sourceName).uniqued().joined(separator: "、").isEmpty ? "FitTune 估算" : record.analysis.provenance.map(\.sourceName).uniqued().joined(separator: "、"))")
                            .font(.caption).foregroundStyle(FitTheme.secondaryText)
                        Text("可信度：\(record.analysis.activeEnergyKcal.provenance.confidence.rawValue) · 覆盖 \(Int(record.analysis.dataCoverage * 100))% · \(record.analysis.algorithmVersion)")
                            .font(.caption).foregroundStyle(FitTheme.secondaryText)
                        ForEach(record.analysis.warnings, id: \.self) { Label($0, systemImage: "info.circle").font(.caption).foregroundStyle(FitTheme.warning) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).fitCard()
                }
                .padding(18).padding(.bottom, 30)
            }
        }
        .navigationTitle("运动总结")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heartRateSamples: [WorkoutMetricSample] {
        record.metricSamples.filter { $0.heartRateBPM != nil }.sorted { $0.timestamp < $1.timestamp }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
