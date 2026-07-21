import SwiftUI

struct WorkoutSessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let session: TrainingSession
    @State private var workingSession: TrainingSession

    @State private var exerciseIndex = 0
    @State private var setNumber = 1
    @State private var loadKg = 20.0
    @State private var reps = 8
    @State private var rir = 3
    @State private var techniqueQuality = 4
    @State private var results: [SetResult] = []
    @State private var recommendation: SetRecommendation?
    @State private var exerciseFinished = false
    @State private var hasPain = false
    @State private var showExitAlert = false
    @State private var startedAt = Date.now
    @State private var pendingResult: SetResult?
    @State private var showFeelingPrompt = false
    @State private var showExerciseLibrary = false
    @State private var completedEffect: TrainingEffect?
    @State private var completedEnergyKcal = 0.0
    @State private var completedEnergyLowerKcal = 0.0
    @State private var completedEnergyUpperKcal = 0.0
    @State private var completedEnergyMethod = ""
    @State private var completedEnergyConfidence = ""
    @State private var sessionAverageHR = 0.0
    @State private var sessionMeasuredKcal = 0.0
    @State private var showExerciseCompletion = false

    init(session: TrainingSession) {
        self.session = session
        _workingSession = State(initialValue: session)
    }

    private var exercise: ExercisePrescription {
        workingSession.exercises[exerciseIndex]
    }

    private var increment: Double {
        store.profile?.loadIncrementKg ?? 2.5
    }

    var body: some View {
        ZStack {
            FitBackground()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 18) {
                        progressHeader
                        sessionEditingCard
                        prescriptionCard
                        inputCard
                        if hasPain { painCard }
                        if let recommendation { recommendationCard(recommendation) }
                        actionButton
                    }
                    .padding(18)
                    .padding(.bottom, 28)
                }
            }
        }
        .onAppear { resetInputsForCurrentExercise() }
        .alert("结束本次训练？", isPresented: $showExitAlert) {
            Button("继续训练", role: .cancel) {}
            if results.isEmpty {
                Button("直接结束", role: .destructive) { dismiss() }
            } else {
                Button("保存 \(results.count) 组并结束") {
                    saveWorkout(status: .partial)
                }
                Button("放弃且不保存", role: .destructive) { dismiss() }
            }
        } message: {
            Text(results.isEmpty ? "目前还没有完成组，本次不会生成训练记录。" : "保存后会计入训练历史和重量建议，并标记为“部分完成”。")
        }
        .confirmationDialog("这组完成后的感觉？", isPresented: $showFeelingPrompt, titleVisibility: .visible) {
            ForEach(SetFeeling.currentCases) { feeling in
                Button(feeling.title, role: (feeling.rpe >= 9.5 || feeling.requiresStop) ? .destructive : nil) {
                    finalizeSet(feeling: feeling)
                }
            }
        } message: {
            Text("感受会与 RIR、动作质量和上次记录一起决定休息时间、下组重量与剩余组数。")
        }
        .sheet(isPresented: $showExerciseLibrary) { exerciseLibrarySheet }
        .sheet(item: $completedEffect) { effect in
            workoutSummarySheet(effect)
        }
        .overlay { if showExerciseCompletion { exerciseCompletionOverlay } }
    }

    private var topBar: some View {
        HStack {
            Button { showExitAlert = true } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(FitTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("结束训练")
            Spacer()
            VStack(spacing: 2) {
                Text(workingSession.name).font(.headline)
                Text("规则 \(store.plan?.ruleVersion ?? TrainingEngine.ruleVersion)")
                    .font(.caption2)
                    .foregroundStyle(FitTheme.secondaryText)
            }
            Spacer()
            Text("\(results.count) 组")
                .font(.subheadline.bold().monospacedDigit())
                .frame(width: 42, height: 42)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("动作 \(exerciseIndex + 1) / \(workingSession.exercises.count)")
                    .font(.caption.bold())
                    .foregroundStyle(FitTheme.accent)
                Spacer()
                Text("第 \(setNumber) / \(exercise.sets) 组")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(FitTheme.secondaryText)
            }
            ProgressView(value: Double(exerciseIndex) + Double(setNumber - 1) / Double(max(exercise.sets, 1)), total: Double(workingSession.exercises.count))
                .tint(FitTheme.accent)
        }
    }

    private var sessionEditingCard: some View {
        HStack(spacing: 10) {
            Button { showExerciseLibrary = true } label: {
                Label("增加动作", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(FitTheme.accent)

            Button { removeCurrentExercise() } label: {
                Label("减少动作", systemImage: "minus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(FitTheme.warning)
            .disabled(workingSession.exercises.count <= 1)
        }
        .font(.subheadline.bold())
    }

    private var prescriptionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if exercise.isPriority {
                        Text("优先动作")
                            .font(.caption2.bold())
                            .foregroundStyle(FitTheme.warning)
                    }
                    Text(exercise.name)
                        .font(.largeTitle.bold())
                        .minimumScaleFactor(0.7)
                    Text(exercise.targetText)
                        .font(.subheadline)
                        .foregroundStyle(FitTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundStyle(FitTheme.accent)
            }

            Menu {
                ForEach(EquipmentKind.allCases) { kind in
                    let options = TrainingEngine.exerciseAlternatives(for: exercise.pattern).filter { $0.equipment == kind }
                    if !options.isEmpty {
                        Section(kind.title) {
                            ForEach(options) { option in
                                Button {
                                    replaceCurrentExercise(with: option)
                                } label: {
                                    Label(option.name, systemImage: option.name == exercise.name ? "checkmark" : "arrow.triangle.2.circlepath")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Label("更换动作或器械", systemImage: "dumbbell.fill")
                        .font(.subheadline.bold())
                    Spacer()
                    Text(exercise.equipmentKind?.title ?? "未指定")
                        .font(.caption)
                        .foregroundStyle(FitTheme.secondaryText)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(FitTheme.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(FitTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("更换当前动作或器械")

            HStack(spacing: 8) {
                Label("完整幅度", systemImage: "arrow.up.and.down")
                Spacer()
                Label(recommendation.map { "建议休息 \($0.restSeconds / 60)分\($0.restSeconds % 60)秒" } ?? "完成后动态建议休息", systemImage: "timer")
            }
            .font(.caption)
            .foregroundStyle(FitTheme.secondaryText)

            IntegerInputControl(
                title: "本动作计划组数",
                value: Binding(
                    get: { exercise.sets },
                    set: { workingSession.exercises[exerciseIndex].sets = min(8, max(setNumber, $0)) }
                ),
                range: setNumber...8,
                step: 1,
                unit: "组"
            )

            let starting = store.loadRecommendation(for: exercise)
            VStack(alignment: .leading, spacing: 4) {
                Text("首组建议：\(starting.displayLoad) · \(starting.confidence)置信度")
                    .font(.subheadline.bold())
                    .foregroundStyle(FitTheme.accentBlue)
                Text(starting.reason)
                    .font(.caption)
                    .foregroundStyle(FitTheme.secondaryText)
            }
        }
        .fitCard(padding: 18)
    }

    private var inputCard: some View {
        VStack(spacing: 4) {
            NumericInputControl(title: "重量", value: $loadKg, range: 0...400, step: increment, unit: "kg")
            Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 8)
            IntegerInputControl(title: "完成次数", value: $reps, range: 1...100, step: 1, unit: "次")
            Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 8)
            IntegerInputControl(title: "还可完成 RIR", value: $rir, range: 0...10, step: 1)
            Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 8)
            techniqueQualityControl
            Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 8)
            NumericInputControl(title: "本次平均心率（可选）", value: $sessionAverageHR, range: 0...220, step: 1, unit: "bpm")
            Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 8)
            NumericInputControl(title: "设备主动热量（可选）", value: $sessionMeasuredKcal, range: 0...3000, step: 5, unit: "kcal")

            Toggle(isOn: $hasPain) {
                Label("出现疼痛或异常不适", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(hasPain ? FitTheme.danger : FitTheme.secondaryText)
            }
            .tint(FitTheme.danger)
            .padding(.top, 14)
        }
        .fitCard(padding: 18)
    }

    private var techniqueQualityControl: some View {
        HStack {
            Text("动作质量")
                .font(.subheadline)
                .foregroundStyle(FitTheme.secondaryText)
            Spacer()
            HStack(spacing: 7) {
                ForEach(1...5, id: \.self) { score in
                    Button { techniqueQuality = score } label: {
                        Text("\(score)")
                            .font(.caption.bold().monospacedDigit())
                            .frame(width: 30, height: 30)
                            .background(techniqueQuality == score ? FitTheme.accent : FitTheme.elevated, in: Circle())
                            .foregroundStyle(techniqueQuality == score ? FitTheme.background : FitTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func valueControl(label: String, valueText: String, decrease: @escaping () -> Void, increase: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(FitTheme.secondaryText)
            Spacer()
            Button(action: decrease) {
                Image(systemName: "minus")
                    .frame(width: 38, height: 38)
                    .background(FitTheme.elevated, in: Circle())
            }
            .buttonStyle(.plain)
            Text(valueText)
                .font(.title3.bold().monospacedDigit())
                .frame(minWidth: 82)
            Button(action: increase) {
                Image(systemName: "plus")
                    .frame(width: 38, height: 38)
                    .background(FitTheme.accent, in: Circle())
                    .foregroundStyle(FitTheme.background)
            }
            .buttonStyle(.plain)
        }
    }

    private var painCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("不要用“减一点重量”掩盖异常症状", systemImage: "cross.case.fill")
                .font(.headline)
                .foregroundStyle(FitTheme.danger)
            Text("若出现尖锐疼痛、胸痛、眩晕、异常气短、麻木或动作突然失控，请停止训练，并视情况寻求专业帮助。")
                .font(.subheadline)
                .foregroundStyle(FitTheme.secondaryText)
            Button(results.isEmpty ? "停止并退出" : "保存已完成的 \(results.count) 组并停止") {
                if results.isEmpty {
                    dismiss()
                } else {
                    saveWorkout(status: .partial)
                }
            }
                .font(.subheadline.bold())
                .foregroundStyle(FitTheme.danger)
        }
        .fitCard()
    }

    private func recommendationCard(_ item: SetRecommendation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.adjustment.symbol)
                .font(.headline)
                .foregroundStyle(FitTheme.background)
                .frame(width: 40, height: 40)
                .background(recommendationColor(item.adjustment), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text("\(item.adjustment.title) · 下一组 \(item.nextLoadKg.formatted(.number.precision(.fractionLength(1)))) kg")
                    .font(.headline)
                Text("休息 \(item.restSeconds / 60)分\(item.restSeconds % 60)秒 · 建议再做 \(item.suggestedRemainingSets) 组")
                    .font(.subheadline.bold())
                    .foregroundStyle(item.continuation == .continueTraining ? FitTheme.accentBlue : FitTheme.warning)
                if item.continuation != .continueTraining {
                    Label(item.continuation.title, systemImage: "exclamationmark.octagon.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(FitTheme.danger)
                }
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(FitTheme.secondaryText)
                Text("建议置信度：\(item.confidence)")
                    .font(.caption2)
                    .foregroundStyle(FitTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard()
    }

    private var actionButton: some View {
        VStack(spacing: 10) {
            Button {
                if recommendation?.continuation == .stopWorkout {
                    saveWorkout(status: .partial)
                } else if exerciseFinished {
                    advanceOrFinish()
                } else {
                    completeSet()
                }
            } label: {
                Label(
                    recommendation?.continuation == .stopWorkout ? "按建议保存并结束" : (exerciseFinished ? (exerciseIndex == workingSession.exercises.count - 1 ? "完成本次训练" : "进入下一个动作") : "完成本组"),
                    systemImage: exerciseFinished ? "arrow.right" : "checkmark"
                )
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(hasPain)
            .opacity(hasPain ? 0.45 : 1)

            Button {
                skipCurrentExercise()
            } label: {
                Label(
                    exerciseIndex == workingSession.exercises.count - 1 ? (results.isEmpty ? "结束训练" : "保存已完成内容并结束") : "跳过当前动作",
                    systemImage: exerciseIndex == workingSession.exercises.count - 1 ? "stop.circle" : "forward.end"
                )
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(FitTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .disabled(hasPain)
            .opacity(hasPain ? 0.45 : 1)
        }
    }

    private func completeSet() {
        pendingResult = SetResult(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            setNumber: setNumber,
            loadKg: loadKg,
            reps: reps,
            rir: rir,
            movementPattern: exercise.pattern,
            techniqueQuality: techniqueQuality
        )
        showFeelingPrompt = true
    }

    private func finalizeSet(feeling: SetFeeling) {
        guard var result = pendingResult else { return }
        result.feeling = feeling
        pendingResult = nil
        results.append(result)
        let next = TrainingEngine.recommendNextSet(
            prescription: exercise,
            result: result,
            readiness: store.readinessAssessment,
            increment: increment,
            exerciseHistory: results.filter { $0.exerciseID == exercise.id },
            priorRecord: store.lastWorkoutRecord(for: exercise)
        )
        withAnimation {
            recommendation = next
            if next.continuation != .continueTraining || next.suggestedRemainingSets == 0 || setNumber >= max(1, exercise.sets - store.readinessAssessment.setReduction) {
                exerciseFinished = true
                showExerciseCompletion = next.continuation != .stopWorkout
            } else {
                setNumber += 1
                if next.suggestedRemainingSets < max(0, exercise.sets - setNumber + 1) {
                    workingSession.exercises[exerciseIndex].sets = setNumber - 1 + next.suggestedRemainingSets
                }
                loadKg = next.nextLoadKg
                reps = exercise.repLower
            }
        }
    }

    private func advanceOrFinish() {
        if exerciseIndex < workingSession.exercises.count - 1 {
            withAnimation {
                exerciseIndex += 1
                setNumber = 1
                recommendation = nil
                exerciseFinished = false
                hasPain = false
                resetInputsForCurrentExercise()
            }
        } else {
            saveWorkout(status: .completed)
        }
    }

    private func skipCurrentExercise() {
        if exerciseIndex < workingSession.exercises.count - 1 {
            withAnimation {
                exerciseIndex += 1
                setNumber = 1
                recommendation = nil
                exerciseFinished = false
                hasPain = false
                resetInputsForCurrentExercise()
            }
        } else if results.isEmpty {
            dismiss()
        } else {
            saveWorkout(status: .partial)
        }
    }

    private func replaceCurrentExercise(with option: ExerciseOption) {
        guard option.pattern == exercise.pattern else { return }
        var replacement = exercise
        replacement.name = option.name
        replacement.equipmentKind = option.equipment
        replacement.suggestedLoadKg = nil
        replacement.suggestedLoadReason = "训练中临时替换，需要按新器械校准工作重量。"
        workingSession.exercises[exerciseIndex] = replacement
        setNumber = 1
        recommendation = nil
        exerciseFinished = false
        hasPain = false
        resetInputsForCurrentExercise()
    }

    private func changePlannedSets(by delta: Int) {
        workingSession.exercises[exerciseIndex].sets = min(8, max(setNumber, exercise.sets + delta))
        exerciseFinished = setNumber > workingSession.exercises[exerciseIndex].sets
    }

    private func removeCurrentExercise() {
        guard workingSession.exercises.count > 1 else { return }
        workingSession.exercises.remove(at: exerciseIndex)
        exerciseIndex = min(exerciseIndex, workingSession.exercises.count - 1)
        setNumber = 1
        recommendation = nil
        exerciseFinished = false
        resetInputsForCurrentExercise()
    }

    private func saveWorkout(status: WorkoutCompletionStatus) {
        guard !results.isEmpty else {
            dismiss()
            return
        }
        let qualities = results.compactMap(\.techniqueQuality)
        let quality = qualities.isEmpty
            ? nil
            : Int((Double(qualities.reduce(0, +)) / Double(qualities.count)).rounded())
        var record = WorkoutRecord(
            sessionName: workingSession.name,
            startedAt: startedAt,
            completedAt: .now,
            readinessScore: store.readinessAssessment.score,
            sets: results,
            sessionQuality: quality,
            completionStatus: status,
            sessionRPE: results.compactMap { $0.feeling?.rpe }.averageValue,
            averageHeartRate: sessionAverageHR > 0 ? sessionAverageHR : nil,
            measuredActiveEnergyKcal: sessionMeasuredKcal > 0 ? sessionMeasuredKcal : nil
        )
        let weight = store.latestWeight ?? store.profile?.bodyWeightKg ?? 70
        let energy = TrainingEngine.strengthEnergyEstimate(record: record, weightKg: weight, profile: store.profile)
        record.activeEnergyKcal = energy.kilocalories
        record.energyMethod = energy.method
        record.energyLowerBoundKcal = energy.lowerBound
        record.energyUpperBoundKcal = energy.upperBound
        record.effect = TrainingEngine.evaluateStrengthWorkout(record)
        store.completeWorkout(record)
        completedEnergyKcal = record.activeEnergyKcal ?? 0
        completedEnergyLowerKcal = energy.lowerBound
        completedEnergyUpperKcal = energy.upperBound
        completedEnergyMethod = energy.method
        completedEnergyConfidence = energy.confidence
        completedEffect = record.effect
    }

    private var exerciseLibrarySheet: some View {
        NavigationStack {
            List {
                ForEach(ExerciseCategory.allCases) { category in
                    let options = TrainingEngine.allExerciseOptions.filter { $0.resolvedCategory == category }
                    if !options.isEmpty {
                        Section(category.title) {
                            ForEach(EquipmentKind.allCases) { equipment in
                                let equipmentOptions = options.filter { $0.equipment == equipment }
                                if !equipmentOptions.isEmpty {
                                    DisclosureGroup(equipment.title) {
                                        ForEach(equipmentOptions) { option in
                                            Button {
                                                guard let profile = store.profile else { return }
                                                workingSession.exercises.append(TrainingEngine.makePrescription(for: option, profile: profile))
                                                showExerciseLibrary = false
                                            } label: {
                                                HStack { Text(option.name); Spacer(); Text(option.pattern.title).font(.caption).foregroundStyle(.secondary) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("增加训练动作")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showExerciseLibrary = false } } }
        }
    }

    private func workoutSummarySheet(_ effect: TrainingEffect) -> some View {
        NavigationStack {
            ZStack {
                FitBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionHeading(eyebrow: "训练已保存", title: "本次训练效果", detail: effect.summary)
                        HStack(spacing: 10) {
                            MetricChip(value: "\(effect.strengthScore)", label: "力量刺激")
                            MetricChip(value: "\(effect.hypertrophyScore)", label: "增肌刺激", tint: FitTheme.accentBlue)
                            MetricChip(value: "\(effect.fatigueScore)", label: "疲劳", tint: FitTheme.warning)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Label("预计恢复 \(effect.recoveryLowerHours ?? effect.estimatedRecoveryHours)–\(effect.recoveryUpperHours ?? effect.estimatedRecoveryHours) 小时", systemImage: "clock.arrow.circlepath")
                                .font(.title3.bold())
                            Text(effect.advice).foregroundStyle(FitTheme.secondaryText)
                            Text("主动消耗约 \(Int(completedEnergyKcal.rounded())) 千卡")
                                .font(.headline)
                                .foregroundStyle(FitTheme.accent)
                            Text("合理区间 \(Int(completedEnergyLowerKcal.rounded()))–\(Int(completedEnergyUpperKcal.rounded())) kcal · \(completedEnergyMethod) · \(completedEnergyConfidence)置信度")
                                .font(.caption).foregroundStyle(FitTheme.secondaryText)
                            if let method = effect.method { Text("效果模型：\(method)").font(.caption).foregroundStyle(FitTheme.secondaryText) }
                        }
                        .fitCard()
                        Button("完成") { completedEffect = nil; dismiss() }
                            .buttonStyle(PrimaryActionButtonStyle())
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }

    private func resetInputsForCurrentExercise() {
        let current = workingSession.exercises[exerciseIndex]
        reps = current.repLower
        rir = current.targetRIR
        techniqueQuality = 4
        let starting = store.loadRecommendation(for: current)
        if let suggestion = starting.loadKg {
            loadKg = suggestion
        } else {
            switch store.profile?.equipment {
            case .bodyweightBands: loadKg = 0
            case .dumbbells: loadKg = current.isPriority ? 10 : 6
            case .fullGym: loadKg = current.isPriority ? 20 : 12.5
            case nil: loadKg = 20
            }
        }
    }

    private func recommendationColor(_ adjustment: LoadAdjustment) -> Color {
        switch adjustment {
        case .increase: FitTheme.accent
        case .hold: FitTheme.accentBlue
        case .decrease: FitTheme.warning
        }
    }

    private var exerciseCompletionOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 84, weight: .bold))
                    .foregroundStyle(FitTheme.accent)
                    .symbolEffect(.bounce, value: showExerciseCompletion)
                Text("\(exercise.name) 完成").font(.title.bold()).multilineTextAlignment(.center)
                Text(exerciseIndex < workingSession.exercises.count - 1 ? "下一项：\(workingSession.exercises[exerciseIndex + 1].name)" : "所有动作已完成，可以生成本次训练总结。")
                    .foregroundStyle(FitTheme.secondaryText)
                    .multilineTextAlignment(.center)
                Button(exerciseIndex < workingSession.exercises.count - 1 ? "开始下一个动作" : "查看训练总结") {
                    withAnimation { showExerciseCompletion = false }
                    advanceOrFinish()
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
            .padding(24)
            .fitCard(padding: 24)
            .padding(24)
        }
    }
}

private extension Array where Element == Double {
    var averageValue: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
}
