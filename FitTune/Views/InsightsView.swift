import Charts
import SwiftUI

struct InsightsView: View {
    @Environment(AppStore.self) private var store
    @Environment(HealthKitService.self) private var healthKit

    @State private var newWeight = 70.0
    @State private var showWeightEntry = false
    @State private var showCardioEntry = false
    @State private var cardioMetric: CardioMetricType = .twelveMinuteDistance
    @State private var cardioValue = 2000.0

    var body: some View {
        ZStack {
            FitBackground()
            ScrollView {
                VStack(spacing: 18) {
                    SectionHeading(
                        eyebrow: "趋势，不追逐噪音",
                        title: "身体、力量、心肺与恢复",
                        detail: "四类进展分别记录；单次波动不会直接改变训练。"
                    )
                    .padding(.top, 10)

                    summaryCards
                    if let deloadSuggestion { deloadCard(deloadSuggestion) }
                    weightCard
                    strengthCard
                    cardioCard
                    recoveryCard
                    historyCard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("进展")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showWeightEntry) { weightEntrySheet }
        .sheet(isPresented: $showCardioEntry) { cardioEntrySheet }
        .onAppear { newWeight = store.latestWeight ?? 70 }
        .onChange(of: cardioMetric) { _, metric in cardioValue = defaultValue(for: metric) }
    }

    private var summaryCards: some View {
        HStack(spacing: 10) {
            MetricChip(value: store.latestWeight.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", label: "体重 kg")
            MetricChip(value: bestE1RM.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", label: "e1RM kg", tint: FitTheme.accentBlue)
            MetricChip(value: latestRecovery.map { "\($0.readinessScore)" } ?? "—", label: "恢复分", tint: FitTheme.warning)
        }
    }

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("体重趋势").font(.headline)
                    if let trend = TrainingEngine.weightTrend(entries: store.weightHistory) {
                        Text("近期变化 \(trend >= 0 ? "+" : "")\(trend.formatted(.number.precision(.fractionLength(1)))) kg")
                            .font(.caption)
                            .foregroundStyle(trendColor(trend))
                    } else {
                        Text("至少记录 4 次后显示趋势")
                            .font(.caption)
                            .foregroundStyle(FitTheme.secondaryText)
                    }
                }
                Spacer()
                Button { showWeightEntry = true } label: {
                    Image(systemName: "plus")
                        .frame(width: 38, height: 38)
                        .background(FitTheme.accent, in: Circle())
                        .foregroundStyle(FitTheme.background)
                }
                .buttonStyle(.plain)
            }

            if recentWeightEntries.count >= 2 {
                Chart(recentWeightEntries) { entry in
                    LineMark(x: .value("日期", entry.date), y: .value("体重", entry.kilograms))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(FitTheme.accent)
                    AreaMark(x: .value("日期", entry.date), y: .value("体重", entry.kilograms))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [FitTheme.accent.opacity(0.24), .clear], startPoint: .top, endPoint: .bottom))
                }
                .frame(height: 165)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(position: .leading) }
            } else {
                ContentUnavailableView("等待更多体重记录", systemImage: "scalemass", description: Text("新增记录或从 Apple 健康同步。"))
                    .frame(height: 130)
            }

            Button {
                healthKit.fetchLatestBodyWeight { value in
                    if let value { store.addWeight(value, source: "Apple 健康") }
                }
            } label: {
                HStack {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text(healthKitButtonTitle)
                    Spacer()
                    if healthKit.state == .requesting {
                        SwiftUI.ProgressView().tint(FitTheme.accent)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .font(.subheadline.bold())
                .padding(12)
                .background(FitTheme.elevated, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            .disabled(healthKit.state == .requesting)
        }
        .fitCard(padding: 17)
    }

    private var strengthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("力量水平").font(.headline)
                    Text("近 30 天主力动作 e1RM 趋势 · \(strengthMetricTrend.sampleCount) 个有效样本")
                        .font(.caption)
                        .foregroundStyle(FitTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "dumbbell.fill").foregroundStyle(FitTheme.accentBlue)
            }
            if strengthTrendPoints.count >= 2 {
                Chart(strengthTrendPoints) { point in
                    LineMark(x: .value("日期", point.date), y: .value("e1RM", point.e1RM))
                        .foregroundStyle(FitTheme.accentBlue)
                        .symbol(.circle)
                    AreaMark(x: .value("日期", point.date), y: .value("e1RM", point.e1RM))
                        .foregroundStyle(FitTheme.accentBlue.opacity(0.12))
                }
                .frame(height: 150)
                .chartYAxis { AxisMarks(position: .leading) }
                if let name = primaryStrengthExercise {
                    Text("趋势动作：\(name)")
                        .font(.caption)
                        .foregroundStyle(FitTheme.secondaryText)
                }
            }
            if strengthLeaders.isEmpty {
                Text("完成一次带重量的训练后，这里会按动作显示基于次数与 RIR 的力量趋势。")
                    .font(.subheadline)
                    .foregroundStyle(FitTheme.secondaryText)
            } else {
                ForEach(strengthLeaders.prefix(6)) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.exerciseName).font(.subheadline.bold())
                            Text("\(item.loadKg.formatted()) kg × \(item.reps) · \(item.rir) RIR")
                                .font(.caption)
                                .foregroundStyle(FitTheme.secondaryText)
                        }
                        Spacer()
                        Text("\(item.e1RM.formatted(.number.precision(.fractionLength(1)))) kg")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(FitTheme.accentBlue)
                    }
                    if item.id != strengthLeaders.prefix(6).last?.id {
                        Divider().overlay(Color.white.opacity(0.07))
                    }
                }
            }
            Text("e1RM 只用于个人趋势；高次数组和 RIR 误差会降低准确度。")
                .font(.caption)
                .foregroundStyle(FitTheme.secondaryText)
        }
        .fitCard()
    }

    private func deloadCard(_ suggestion: DeloadSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("减量周建议", systemImage: "gauge.with.dots.needle.33percent")
                .font(.headline).foregroundStyle(FitTheme.warning)
            Text(suggestion.reason).font(.subheadline)
            Text("仅为建议，不会自动修改训练计划。")
                .font(.caption).foregroundStyle(FitTheme.secondaryText)
        }
        .fitCard()
    }

    private var cardioCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("心肺能力").font(.headline)
                    Text("近 30 天 \(recentCardioWorkouts.count) 次 · \(recentCardioWorkouts.reduce(0) { $0 + $1.durationMinutes }) 分钟")
                        .font(.caption)
                        .foregroundStyle(FitTheme.secondaryText)
                    Picker("指标", selection: $cardioMetric) {
                        ForEach(CardioMetricType.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(FitTheme.accentBlue)
                }
                Spacer()
                Button { showCardioEntry = true } label: {
                    Image(systemName: "plus")
                        .frame(width: 38, height: 38)
                        .background(FitTheme.accentBlue, in: Circle())
                        .foregroundStyle(FitTheme.background)
                }
                .buttonStyle(.plain)
            }

            if selectedCardioEntries.count >= 2 {
                Chart(selectedCardioEntries) { entry in
                    LineMark(x: .value("日期", entry.date), y: .value(cardioMetric.title, entry.value))
                        .symbol(.circle)
                        .foregroundStyle(FitTheme.accentBlue)
                }
                .frame(height: 155)
                .chartYAxis { AxisMarks(position: .leading) }
            } else if let latest = selectedCardioEntries.last {
                HStack(alignment: .firstTextBaseline) {
                    Text(latest.value.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(FitTheme.accentBlue)
                    Text(cardioMetric.unit)
                        .foregroundStyle(FitTheme.secondaryText)
                }
            } else {
                Text("记录 12 分钟跑/走距离、Apple Watch 的 VO₂ max，或静息心率，以观察心肺趋势。")
                    .font(.subheadline)
                    .foregroundStyle(FitTheme.secondaryText)
                    .padding(.vertical, 16)
            }
            Text(cardioMetric == .twelveMinuteDistance ? "12 分钟测试是最大努力测试；只在身体状况允许时进行，结果更适合做个人纵向比较。" : "设备估算与现场测试存在误差，请固定相近条件观察长期变化。")
                .font(.caption)
                .foregroundStyle(FitTheme.secondaryText)
        }
        .fitCard()
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("睡眠与恢复").font(.headline)
                    Text("保存每日睡眠时长、质量和综合恢复分")
                        .font(.caption)
                        .foregroundStyle(FitTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "moon.stars.fill").foregroundStyle(FitTheme.warning)
            }
            if recentRecoveryEntries.count >= 2 {
                Chart(recentRecoveryEntries) { entry in
                    LineMark(x: .value("日期", entry.date), y: .value("恢复分", entry.readinessScore))
                        .foregroundStyle(FitTheme.warning)
                        .symbol(.circle)
                }
                .frame(height: 155)
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(position: .leading) }
            } else if let latestRecovery {
                HStack(spacing: 18) {
                    MetricChip(value: "\(latestRecovery.readinessScore)", label: "恢复分", tint: FitTheme.warning)
                    MetricChip(value: latestRecovery.sleepHours.formatted(.number.precision(.fractionLength(1))), label: "睡眠 h", tint: FitTheme.accentBlue)
                    MetricChip(value: "\(latestRecovery.sleepQuality)/5", label: "睡眠质量")
                }
            } else {
                Text("在“今天”保存一次状态后开始记录。恢复分是训练辅助信号，不是医学诊断。")
                    .font(.subheadline)
                    .foregroundStyle(FitTheme.secondaryText)
            }
        }
        .fitCard()
    }

    @ViewBuilder
    private var historyCard: some View {
        if !store.weightHistory.isEmpty || !store.cardioHistory.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("最近指标记录").font(.headline)
                ForEach(recentMetricRows) { row in
                    HStack {
                        Text(row.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                        Spacer()
                        Text(row.label)
                            .font(.caption)
                            .foregroundStyle(FitTheme.secondaryText)
                        Text(row.value)
                            .font(.subheadline.bold().monospacedDigit())
                    }
                }
            }
            .fitCard()
        }
    }

    private var weightEntrySheet: some View {
        NavigationStack {
            ZStack {
                FitBackground()
                VStack(spacing: 24) {
                    Image(systemName: "scalemass.fill").font(.largeTitle).foregroundStyle(FitTheme.accent)
                    Text("\(newWeight, specifier: "%.1f") kg")
                        .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                    Slider(value: $newWeight, in: 35...200, step: 0.1).tint(FitTheme.accent)
                    Button("保存体重") {
                        store.addWeight(newWeight)
                        showWeightEntry = false
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("新增体重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showWeightEntry = false } } }
        }
        .presentationDetents([.medium])
    }

    private var cardioEntrySheet: some View {
        NavigationStack {
            ZStack {
                FitBackground()
                VStack(spacing: 22) {
                    Picker("心肺指标", selection: $cardioMetric) {
                        ForEach(CardioMetricType.allCases) { metric in Text(metric.title).tag(metric) }
                    }
                    .pickerStyle(.menu)
                    .tint(FitTheme.accentBlue)

                    Text(cardioValue.formatted(.number.precision(.fractionLength(cardioMetric == .twelveMinuteDistance ? 0 : 1))))
                        .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                    Text(cardioMetric.unit).foregroundStyle(FitTheme.secondaryText)
                    Slider(value: $cardioValue, in: valueRange(for: cardioMetric), step: valueStep(for: cardioMetric))
                        .tint(FitTheme.accentBlue)
                    Button("保存心肺指标") {
                        store.addCardioMetric(type: cardioMetric, value: cardioValue)
                        showCardioEntry = false
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("新增心肺记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showCardioEntry = false } } }
        }
        .presentationDetents([.medium])
    }

    private var allSets: [SetResult] {
        store.workoutHistory.flatMap(\.sets).filter { $0.loadKg > 0 }
    }

    private var strengthLeaders: [StrengthProgress] {
        Dictionary(grouping: allSets, by: \.exerciseName).compactMap { name, sets in
            guard let best = sets.max(by: { (TrainingEngine.estimatedOneRepMax(loadKg: $0.loadKg, reps: $0.reps, rir: $0.rir) ?? 0) < (TrainingEngine.estimatedOneRepMax(loadKg: $1.loadKg, reps: $1.reps, rir: $1.rir) ?? 0) }),
                  let e1RM = TrainingEngine.estimatedOneRepMax(loadKg: best.loadKg, reps: best.reps, rir: best.rir) else { return nil }
            return StrengthProgress(exerciseName: name, loadKg: best.loadKg, reps: best.reps, rir: best.rir, e1RM: e1RM)
        }
        .sorted { $0.e1RM > $1.e1RM }
    }

    private var bestE1RM: Double? { strengthLeaders.first?.e1RM }
    private var strengthMetricTrend: MetricTrend { TrendEngine.strength(records: store.workoutHistory, bodyWeightKg: store.latestWeight) }
    private var deloadSuggestion: DeloadSuggestion? { TrendEngine.deloadSuggestion(workouts: store.workoutHistory, recovery: store.recoveryHistory) }
    private var latestRecovery: RecoveryEntry? { store.recoveryHistory.max { $0.date < $1.date } }
    private var monthStart: Date { Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast }
    private var recentWeightEntries: [WeightEntry] { store.weightHistory.filter { $0.date >= monthStart }.sorted { $0.date < $1.date } }
    private var recentRecoveryEntries: [RecoveryEntry] { store.recoveryHistory.filter { $0.date >= monthStart }.sorted { $0.date < $1.date } }
    private var recentCardioWorkouts: [CardioWorkoutRecord] { store.cardioWorkouts.filter { $0.date >= monthStart } }
    private var selectedCardioEntries: [CardioMetricEntry] { store.cardioHistory.filter { $0.type == cardioMetric && $0.date >= monthStart }.sorted { $0.date < $1.date } }
    private var primaryStrengthExercise: String? { strengthLeaders.first?.exerciseName }
    private var strengthTrendPoints: [StrengthTrendPoint] {
        guard let name = primaryStrengthExercise else { return [] }
        return store.workoutHistory.filter { $0.completedAt >= monthStart }.compactMap { record in
            let values = record.sets.filter { $0.exerciseName == name }.compactMap {
                TrainingEngine.estimatedOneRepMax(loadKg: $0.loadKg, reps: $0.reps, rir: $0.rir)
            }
            guard let best = values.max() else { return nil }
            return StrengthTrendPoint(date: record.completedAt, e1RM: best)
        }.sorted { $0.date < $1.date }
    }

    private var healthKitButtonTitle: String {
        switch healthKit.state {
        case .idle: "从 Apple 健康同步体重"
        case .requesting: "正在请求权限…"
        case .success(let message), .failed(let message): message
        }
    }

    private var recentMetricRows: [MetricRow] {
        let weights = store.weightHistory.suffix(3).map { MetricRow(date: $0.date, label: "体重", value: "\($0.kilograms.formatted(.number.precision(.fractionLength(1)))) kg") }
        let cardio = store.cardioHistory.suffix(3).map { MetricRow(date: $0.date, label: $0.type.title, value: "\($0.value.formatted(.number.precision(.fractionLength(1)))) \($0.type.unit)") }
        return (weights + cardio).sorted { $0.date > $1.date }.prefix(6).map { $0 }
    }

    private func defaultValue(for metric: CardioMetricType) -> Double {
        switch metric {
        case .twelveMinuteDistance: 2000
        case .vo2Max: 40
        case .restingHeartRate: 65
        }
    }

    private func valueRange(for metric: CardioMetricType) -> ClosedRange<Double> {
        switch metric {
        case .twelveMinuteDistance: 500...5000
        case .vo2Max: 15...85
        case .restingHeartRate: 35...120
        }
    }

    private func valueStep(for metric: CardioMetricType) -> Double {
        switch metric {
        case .twelveMinuteDistance: 25
        case .vo2Max: 0.5
        case .restingHeartRate: 1
        }
    }

    private func trendColor(_ trend: Double) -> Color {
        guard let goal = store.profile?.goal else { return FitTheme.secondaryText }
        switch goal {
        case .fatLoss where trend < 0: return FitTheme.accent
        case .hypertrophy where trend > 0: return FitTheme.accent
        default: return FitTheme.warning
        }
    }
}

private struct StrengthProgress: Identifiable {
    var exerciseName: String
    var loadKg: Double
    var reps: Int
    var rir: Int
    var e1RM: Double
    var id: String { exerciseName }
}

private struct MetricRow: Identifiable {
    var date: Date
    var label: String
    var value: String
    var id: String { "\(date.timeIntervalSince1970)-\(label)" }
}

private struct StrengthTrendPoint: Identifiable {
    var date: Date
    var e1RM: Double
    var id: String { "\(date.timeIntervalSince1970)-\(e1RM)" }
}
