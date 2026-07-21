import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(HealthKitService.self) private var healthKit

    @State private var sleepHours = 7.5
    @State private var sleepQuality = 3
    @State private var soreness = 2
    @State private var stress = 2
    @State private var motivation = 4
    @State private var savedFeedback = false
    @State private var showCardioEntry = false
    @State private var cardioModality: CardioModality = .inclineWalking
    @State private var cardioIntensity: CardioIntensity = .zone2
    @State private var cardioMinutes = 30
    @State private var cardioDistanceKm = 0.0
    @State private var cardioAverageHR = 0.0
    @State private var cardioMeasuredKcal = 0.0
    @State private var cardioSpeedKph = 0.0
    @State private var cardioInclinePercent = 0.0
    @State private var cardioPowerWatts = 0.0
    @State private var cardioFloors = 0.0
    @State private var cardioSessionRPE = 5.0

    private var draftInput: ReadinessInput {
        ReadinessInput(
            date: .now,
            sleepHours: sleepHours,
            soreness: soreness,
            stress: stress,
            motivation: motivation,
            sleepQuality: sleepQuality
        )
    }

    private var assessment: ReadinessAssessment {
        TrainingEngine.assessReadiness(draftInput)
    }

    var body: some View {
        ZStack {
            FitBackground()
            ScrollView {
                VStack(spacing: 18) {
                    greeting
                    todayEnergyCard
                    readinessCard
                    dailyDecisionCard
                    switch store.todayChoice.intent {
                    case .train:
                        if let session = store.todaySession {
                            sessionCard(session)
                        } else {
                            unavailableSessionCard
                        }
                    case .rest:
                        recoveryDayCard
                    case .undecided:
                        EmptyView()
                    }
                    cardioPlanCard
                    overview
                    scienceGuardrail
                    recentHistory
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            sleepHours = store.readiness.sleepHours
            sleepQuality = store.readiness.sleepQuality ?? 3
            soreness = store.readiness.soreness
            stress = store.readiness.stress
            motivation = store.readiness.motivation
        }
        .sheet(isPresented: $showCardioEntry) { cardioEntrySheet }
    }

    private var greeting: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FitTheme.accent)
                Text(store.profile?.nickname.isEmpty == false ? "你好，\(store.profile?.nickname ?? "")" : "今天，练得更聪明")
                    .font(.largeTitle.bold())
                    .minimumScaleFactor(0.75)
            }
            Spacer()
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.title2.weight(.semibold))
                .foregroundStyle(FitTheme.background)
                .frame(width: 50, height: 50)
                .background(FitTheme.accent, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(.top, 16)
    }

    private var readinessCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(assessment.score) / 100)
                        .stroke(readinessColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(assessment.score)")
                            .font(.title2.bold().monospacedDigit())
                        Text("状态分")
                            .font(.caption2)
                            .foregroundStyle(FitTheme.secondaryText)
                    }
                }
                .frame(width: 86, height: 86)

                VStack(alignment: .leading, spacing: 7) {
                    Label(assessment.level.title, systemImage: assessment.level.symbol)
                        .font(.headline)
                        .foregroundStyle(readinessColor)
                    Text(assessment.summary)
                        .font(.subheadline)
                        .foregroundStyle(FitTheme.secondaryText)
                }
            }

            VStack(spacing: 14) {
                HStack {
                    Label("昨晚睡眠", systemImage: "bed.double.fill")
                    Spacer()
                    Stepper(value: $sleepHours, in: 3...12, step: 0.5) {
                        Text("\(sleepHours, specifier: "%.1f") h")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(FitTheme.accent)
                    }
                    .fixedSize()
                }
                Divider().overlay(Color.white.opacity(0.08))
                scoreRow(title: "睡眠质量", symbol: "moon.stars.fill", value: $sleepQuality, highIsGood: true)
                Divider().overlay(Color.white.opacity(0.08))
                scoreRow(title: "肌肉酸痛", symbol: "waveform.path.ecg", value: $soreness, highIsGood: false)
                scoreRow(title: "心理压力", symbol: "brain.head.profile", value: $stress, highIsGood: false)
                scoreRow(title: "训练意愿", symbol: "bolt.heart.fill", value: $motivation, highIsGood: true)
            }

            Button {
                store.updateReadiness(draftInput)
                withAnimation { savedFeedback = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    withAnimation { savedFeedback = false }
                }
            } label: {
                Label(savedFeedback ? "状态已保存" : "更新今日状态", systemImage: savedFeedback ? "checkmark" : "arrow.triangle.2.circlepath")
                    .font(.subheadline.bold())
                    .foregroundStyle(FitTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(FitTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
        }
        .fitCard(padding: 18)
    }

    private var todayEnergyCard: some View {
        let energy = store.todayEnergySummary
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("今日热量消耗").font(.title2.bold())
                    Text("静息 + 力量 + 有氧 + 步行/步数 + 其他主动消耗")
                        .font(.caption)
                        .foregroundStyle(FitTheme.secondaryText)
                }
                Spacer()
                Text(energy.totalKcal.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(FitTheme.accent)
            }
            HStack(spacing: 8) {
                MetricChip(value: energy.restingKcal.map { "\(Int($0.rounded()))" } ?? "待补全", label: "基础 kcal")
                MetricChip(value: "\(Int(energy.strengthKcal.rounded()))", label: "力量 kcal", tint: FitTheme.accentBlue)
                MetricChip(value: "\(Int(energy.cardioKcal.rounded()))", label: "有氧 kcal", tint: FitTheme.warning)
            }
            HStack(spacing: 8) {
                MetricChip(value: "\(Int(energy.walkingStepsKcal.rounded()))", label: "步行 kcal", tint: FitTheme.accent)
                MetricChip(value: "\(energy.steps)", label: "今日步数", tint: FitTheme.accentBlue)
                MetricChip(value: "\(Int(energy.otherWearableKcal.rounded()))", label: "其他活动 kcal", tint: FitTheme.warning)
            }
            if energy.otherWearableKcal > 0 {
                Label("Apple Watch 其余主动消耗 \(Int(energy.otherWearableKcal.rounded())) kcal", systemImage: "applewatch")
                    .font(.caption.bold())
                    .foregroundStyle(FitTheme.accentBlue)
            }
            let restingMethod = store.profile.flatMap { TrainingEngine.restingEnergyEstimate(profile: $0, weightKg: store.latestWeight)?.method }
            Text(energy.restingKcal == nil
                 ? "请到“我的”补充身体参数。运动消耗仍可独立记录。"
                 : "静息采用 \(restingMethod ?? "可用模型")；运动按设备实测、速度/坡度、平均心率、MET 的证据层级选择。步数已避免与 Watch 主动能量重复相加。")
                .font(.caption)
                .foregroundStyle(FitTheme.secondaryText)
        }
        .fitCard(padding: 18)
    }

    private func scoreRow(title: String, symbol: String, value: Binding<Int>, highIsGood: Bool) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 7) {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        value.wrappedValue = score
                    } label: {
                        Text("\(score)")
                            .font(.caption.bold().monospacedDigit())
                            .frame(width: 27, height: 27)
                            .background(value.wrappedValue == score ? FitTheme.accent : FitTheme.elevated, in: Circle())
                            .foregroundStyle(value.wrappedValue == score ? FitTheme.background : FitTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(score) 分")
                }
            }
        }
    }

    private var dailyDecisionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("今天怎么安排？")
                        .font(.title2.bold())
                    Text("先决定训练或恢复，再临场选择部位。")
                        .font(.caption)
                        .foregroundStyle(FitTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                    .foregroundStyle(FitTheme.accent)
            }

            HStack(spacing: 10) {
                intentButton(.train, symbol: "figure.strengthtraining.traditional", tint: FitTheme.accent)
                intentButton(.rest, symbol: "bed.double.fill", tint: FitTheme.accentBlue)
            }

            if store.todayChoice.intent == .undecided {
                Label("尚未决定，不会自动把固定计划算作今日任务。", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(FitTheme.secondaryText)
            }

            if store.todayChoice.intent == .train {
                Divider().overlay(Color.white.opacity(0.08))
                Text("今天练哪里")
                    .font(.subheadline.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(DailyTrainingFocus.allCases) { focus in
                        focusButton(focus)
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))
                VStack(alignment: .leading, spacing: 8) {
                    Text("今天避开（可多选）")
                        .font(.subheadline.bold())
                    HStack(spacing: 8) {
                        ForEach(BodyRegion.allCases) { region in
                            let isAvoided = store.todayChoice.avoidedRegions.contains(region)
                            Button {
                                store.toggleAvoidedRegion(region)
                            } label: {
                                Text(region.title)
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(isAvoided ? FitTheme.danger.opacity(0.18) : FitTheme.elevated, in: RoundedRectangle(cornerRadius: 11))
                                    .foregroundStyle(isAvoided ? FitTheme.danger : FitTheme.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isAvoided ? "取消避开\(region.title)" : "今天避开\(region.title)")
                        }
                    }
                    Text("被避开的部位会从今日动作中移除；疼痛或异常不适不应仅靠改练其他部位处理。")
                        .font(.caption2)
                        .foregroundStyle(FitTheme.secondaryText)
                }
            }
        }
        .fitCard(padding: 18)
    }

    private func intentButton(_ intent: TodayTrainingIntent, symbol: String, tint: Color) -> some View {
        let isSelected = store.todayChoice.intent == intent
        return Button {
            store.setTodayIntent(intent)
        } label: {
            Label(intent.title, systemImage: symbol)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? tint : FitTheme.elevated, in: RoundedRectangle(cornerRadius: 13))
                .foregroundStyle(isSelected ? FitTheme.background : FitTheme.secondaryText)
        }
        .buttonStyle(.plain)
    }

    private func focusButton(_ focus: DailyTrainingFocus) -> some View {
        let isSelected = store.todayChoice.focus == focus
        let blocked = focus.primaryRegion.map(store.todayChoice.avoidedRegions.contains) ?? false
        return Button {
            store.setTodayFocus(focus)
        } label: {
            Label(focus.title, systemImage: focus.symbol)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? FitTheme.accent.opacity(0.18) : FitTheme.elevated, in: RoundedRectangle(cornerRadius: 11))
                .foregroundStyle(isSelected ? FitTheme.accent : FitTheme.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .opacity(blocked ? 0.35 : 1)
        .accessibilityLabel("选择今日训练：\(focus.title)")
    }

    private var recoveryDayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("今天已设为恢复日", systemImage: "moon.zzz.fill")
                .font(.title2.bold())
                .foregroundStyle(FitTheme.accentBlue)
            Text("不会推进力量计划。需要改练时，随时在上方切回“今天训练”。")
                .font(.subheadline)
                .foregroundStyle(FitTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(padding: 18)
    }

    private var unavailableSessionCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("当前选择没有可用动作", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(FitTheme.warning)
            Text("请换一个训练部位，或取消一个“今天避开”的部位。")
                .font(.subheadline)
                .foregroundStyle(FitTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard()
    }

    private func sessionCard(_ session: TrainingSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日力量训练")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FitTheme.accentBlue)
                    Text(session.name)
                        .font(.title.bold())
                    Text(session.focus)
                        .foregroundStyle(FitTheme.secondaryText)
                }
                Spacer()
                Text("约 \(session.estimatedMinutes) 分钟")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(FitTheme.accentBlue.opacity(0.12), in: Capsule())
                    .foregroundStyle(FitTheme.accentBlue)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(session.exercises) { exercise in
                        let suggestion = store.loadRecommendation(for: exercise)
                        Text("\(exercise.name) · \(suggestion.displayLoad)")
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(FitTheme.elevated, in: Capsule())
                    }
                }
            }

            Button {
                store.updateReadiness(draftInput)
                store.startWorkout(session)
            } label: {
                Label("开始训练", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
        .fitCard(padding: 18)
    }

    private var cardioPlanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("有氧训练")
                        .font(.caption.bold())
                        .foregroundStyle(FitTheme.accentBlue)
                    Text("独立心肺模块")
                        .font(.title2.bold())
                }
                Spacer()
                Image(systemName: "heart.circle.fill")
                    .font(.title)
                    .foregroundStyle(FitTheme.accentBlue)
            }
            ForEach(store.cardioPlan) { cardio in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: cardio.intensity == .intervals ? "bolt.heart.fill" : "figure.run")
                        .foregroundStyle(cardio.intensity == .intervals ? FitTheme.warning : FitTheme.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(cardio.name) · \(cardio.minutes) 分钟")
                            .font(.subheadline.bold())
                        Text("\(cardio.modality) · \(cardio.intensity.title)")
                            .font(.caption)
                            .foregroundStyle(FitTheme.secondaryText)
                    }
                }
            }
            HStack(spacing: 10) {
                Button { showCardioEntry = true } label: {
                    Label("选择并记录有氧", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(FitTheme.accentBlue)
                Button { syncWatchWorkouts() } label: {
                    Image(systemName: "applewatch")
                        .frame(width: 42, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(healthKit.state == .requesting)
                .accessibilityLabel("同步 Apple Watch 今日训练")
            }
            if let latest = store.cardioWorkouts.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近：\(latest.modality.title) · \(latest.durationMinutes) 分钟 · \(Int(latest.activeEnergyKcal.rounded())) kcal")
                        .font(.subheadline.bold())
                    if let effect = latest.effect {
                        Text("有氧负荷 \(effect.aerobicScore)/100 · 恢复 \(effect.recoveryLowerHours ?? effect.estimatedRecoveryHours)–\(effect.recoveryUpperHours ?? effect.estimatedRecoveryHours) 小时")
                            .font(.caption)
                            .foregroundStyle(FitTheme.secondaryText)
                    }
                }
                .padding(12)
                .background(FitTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
            }
            Text("可选爬坡、楼梯、游泳、跑步、骑行、划船、椭圆机、快走或跳绳；手表主动消耗优先于 MET 估算。")
                .font(.caption)
                .foregroundStyle(FitTheme.secondaryText)
        }
        .fitCard(padding: 18)
    }

    private var cardioEntrySheet: some View {
        NavigationStack {
            ZStack {
                FitBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        Picker("运动方式", selection: $cardioModality) {
                            ForEach(CardioModality.allCases) { item in Text(item.title).tag(item) }
                        }
                        .pickerStyle(.menu)
                        Picker("训练强度", selection: $cardioIntensity) {
                            ForEach(CardioIntensity.allCases) { item in Text(item.title).tag(item) }
                        }
                        .pickerStyle(.segmented)
                        VStack(spacing: 12) {
                            IntegerInputControl(title: "时长", value: $cardioMinutes, range: 1...600, step: 5, unit: "分钟")
                            NumericInputControl(title: "距离（可选）", value: $cardioDistanceKm, range: 0...300, step: 0.1, unit: "km")
                            if [.running, .briskWalking, .inclineWalking].contains(cardioModality) {
                                NumericInputControl(title: "平均速度（可选）", value: $cardioSpeedKph, range: 0...30, step: 0.1, unit: "km/h")
                                NumericInputControl(title: "坡度（可选）", value: $cardioInclinePercent, range: 0...40, step: 0.5, unit: "%")
                            }
                            if [.cycling, .rowing].contains(cardioModality) {
                                NumericInputControl(title: "平均功率（可选）", value: $cardioPowerWatts, range: 0...1000, step: 5, unit: "W")
                            }
                            if cardioModality == .stairClimber {
                                NumericInputControl(title: "楼层（可选）", value: $cardioFloors, range: 0...1000, step: 1, unit: "层")
                            }
                            NumericInputControl(title: "平均心率（可直接输入）", value: $cardioAverageHR, range: 0...220, step: 1, unit: "bpm")
                            NumericInputControl(title: "session-RPE", value: $cardioSessionRPE, range: 1...10, step: 0.5, unit: "/10")
                            NumericInputControl(title: "设备主动消耗（可选）", value: $cardioMeasuredKcal, range: 0...3000, step: 5, unit: "kcal")
                        }
                        .fitCard(padding: 14)
                        let estimate = TrainingEngine.cardioEnergyEstimate(
                            modality: cardioModality,
                            intensity: cardioIntensity,
                            minutes: cardioMinutes,
                            weightKg: store.latestWeight ?? 70,
                            profile: store.profile,
                            distanceKm: cardioDistanceKm > 0 ? cardioDistanceKm : nil,
                            averageHeartRate: cardioAverageHR > 0 ? cardioAverageHR : nil,
                            speedKph: cardioSpeedKph > 0 ? cardioSpeedKph : nil,
                            inclinePercent: cardioInclinePercent > 0 ? cardioInclinePercent : nil,
                            measuredActiveEnergy: cardioMeasuredKcal > 0 ? cardioMeasuredKcal : nil
                        )
                        VStack(alignment: .leading, spacing: 5) {
                            Text("主动消耗约 \(Int(estimate.kilocalories.rounded())) kcal")
                                .font(.headline).foregroundStyle(FitTheme.accent)
                            Text("合理区间 \(Int(estimate.lowerBound.rounded()))–\(Int(estimate.upperBound.rounded())) kcal · \(estimate.method) · \(estimate.confidence)置信度")
                                .font(.caption).foregroundStyle(FitTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fitCard(padding: 14)
                        Button("保存有氧训练") {
                            let record = TrainingEngine.makeCardioWorkout(
                                modality: cardioModality,
                                intensity: cardioIntensity,
                                minutes: cardioMinutes,
                                weightKg: store.latestWeight ?? 70,
                                profile: store.profile,
                                distanceKm: cardioDistanceKm > 0 ? cardioDistanceKm : nil,
                                averageHeartRate: cardioAverageHR > 0 ? cardioAverageHR : nil,
                                speedKph: cardioSpeedKph > 0 ? cardioSpeedKph : nil,
                                inclinePercent: cardioInclinePercent > 0 ? cardioInclinePercent : nil,
                                powerWatts: cardioPowerWatts > 0 ? cardioPowerWatts : nil,
                                floorsClimbed: cardioFloors > 0 ? cardioFloors : nil,
                                sessionRPE: cardioSessionRPE,
                                measuredActiveEnergy: cardioMeasuredKcal > 0 ? cardioMeasuredKcal : nil
                            )
                            store.addCardioWorkout(record)
                            showCardioEntry = false
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                    }
                    .padding(20)
                }
            }
            .navigationTitle("记录有氧训练")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showCardioEntry = false } } }
        }
    }

    private func syncWatchWorkouts() {
        healthKit.fetchTodayWorkoutData(weightKg: store.latestWeight ?? 70) { energy, workouts, stepEntry, strengthWorkouts in
            if let energy { store.importWearableActiveEnergy(energy) }
            workouts.forEach(store.addCardioWorkout)
            strengthWorkouts.forEach(store.mergeWearableStrengthWorkout)
            if let stepEntry {
                store.importDailySteps(steps: stepEntry.steps, distanceKm: stepEntry.distanceKm, weightKg: store.latestWeight ?? 70, source: stepEntry.source)
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(eyebrow: "本地进展", title: "你的训练概览")
            HStack(spacing: 10) {
                MetricChip(value: "\(store.workoutHistory.count)", label: "训练记录")
                MetricChip(value: "\(store.totalCompletedSets)", label: "有效记录组", tint: FitTheme.accentBlue)
                MetricChip(value: "\(store.recoveryHistory.last?.readinessScore ?? assessment.score)", label: "恢复分", tint: FitTheme.warning)
            }
        }
    }

    private var scienceGuardrail: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(FitTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("恢复分是辅助信号")
                    .font(.subheadline.bold())
                Text("App 会把睡眠、间隔、完成次数、RIR 和动作质量合并判断，不会只凭单次体重或一晚睡眠大幅改计划。")
                    .font(.caption)
                    .foregroundStyle(FitTheme.secondaryText)
            }
        }
        .fitCard()
    }

    @ViewBuilder
    private var recentHistory: some View {
        if !store.workoutHistory.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(eyebrow: "历史", title: "最近完成")
                ForEach(store.workoutHistory.prefix(3)) { record in
                    HStack {
                        Image(systemName: record.resolvedCompletionStatus == .partial ? "circle.lefthalf.filled" : "checkmark.seal.fill")
                            .foregroundStyle(record.resolvedCompletionStatus == .partial ? FitTheme.warning : FitTheme.accent)
                        VStack(alignment: .leading) {
                            HStack(spacing: 6) {
                                Text(record.sessionName).font(.subheadline.bold())
                                if record.resolvedCompletionStatus == .partial {
                                    Text("部分完成")
                                        .font(.caption2.bold())
                                        .foregroundStyle(FitTheme.warning)
                                }
                            }
                            Text(record.completedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(FitTheme.secondaryText)
                        }
                        Spacer()
                        Text("\(record.sets.count) 组")
                            .font(.caption.bold())
                    }
                    .fitCard(padding: 13)
                }
            }
        }
    }

    private var readinessColor: Color {
        switch assessment.level {
        case .ready: FitTheme.accent
        case .moderate: FitTheme.warning
        case .low: FitTheme.danger
        }
    }
}
