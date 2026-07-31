import SwiftUI

private struct LoadQuickChoice: Identifiable {
    let label: String
    let value: Double
    var id: String { "\(label)-\(value)" }
}

struct WorkoutSessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(LiveSensorCoordinator.self) private var liveSensors
    @Environment(\.dismiss) private var dismiss

    private let initialSession: TrainingSession?
    @State private var showExitDialog = false
    @State private var showDiscardConfirmation = false
    @State private var showExerciseLibrary = false
    @State private var showWorkoutEditor = false
    @State private var replacementExercise: ExercisePrescription?
    @State private var showSessionRPE = false
    @State private var pendingSaveStatus: WorkoutCompletionStatus?
    @State private var pendingSessionRPE = 7

    init(session: TrainingSession? = nil) {
        initialSession = session
    }

    var body: some View {
        ZStack {
            FitBackground()
            if let draft = store.activeWorkoutDraft,
               draft.exerciseIndex >= 0,
               draft.exerciseIndex < draft.session.exercises.count {
                workoutContent(draft)
            } else {
                ProgressView("恢复训练中…")
                    .tint(FitTheme.accent)
            }
        }
        .onAppear {
            if store.activeWorkoutDraft == nil, let initialSession {
                store.startWorkout(initialSession)
            }
            if let draft = store.activeWorkoutDraft { liveSensors.beginWorkout(sessionID: draft.id, activity: "strength") }
            appendLatestLiveSample()
            updateLiveActivity()
        }
        .onChange(of: liveSensors.latestSample?.id) { _, _ in appendLatestLiveSample(); updateLiveActivity() }
        .onChange(of: liveSensors.latestWatchEvent) { _, event in
            guard event?.sessionID == store.activeWorkoutDraft?.id, event?.event == .ended else { return }
            requestSave(status: .partial)
        }
        .onChange(of: store.activeWorkoutDraft?.updatedAt) { _, _ in updateLiveActivity() }
        .onChange(of: store.activeWorkoutDraft?.currentPauseStartedAt) { _, pauseStartedAt in
            guard pauseStartedAt != nil else { return }
            showExerciseLibrary = false
            showWorkoutEditor = false
            replacementExercise = nil
        }
        .confirmationDialog("离开当前训练？", isPresented: $showExitDialog, titleVisibility: .visible) {
            Button("继续未完成训练") { showExitDialog = false }
            Button("保存并结束") { requestSave(status: .partial) }
            Button("放弃训练", role: .destructive) { showDiscardConfirmation = true }
        } message: {
            Text("训练已自动缓存。只有保存或确认放弃后，未完成训练才会清除。")
        }
        .alert("确认放弃本次训练？", isPresented: $showDiscardConfirmation) {
            Button("返回训练", role: .cancel) {}
            Button("放弃且不保存", role: .destructive) {
                liveSensors.endWorkout()
                WorkoutActivityController.shared.end()
                store.discardWorkoutDraft()
                dismiss()
            }
        } message: {
            Text("已完成和未完成的组都不会生成训练记录，此操作无法恢复。")
        }
        .alert(
            "心率连接已中断",
            isPresented: Binding(
                get: { liveSensors.reconnectReminder != nil },
                set: { if !$0 { liveSensors.dismissReconnectReminder() } }
            )
        ) {
            Button("立即重新扫描") { liveSensors.retryPreferredSource() }
            Button("继续估算", role: .cancel) {
                liveSensors.dismissReconnectReminder()
            }
        } message: {
            Text("已尝试自动重连 \(liveSensors.reconnectReminder?.sourceName ?? "心率设备")，暂未恢复心率。可以重新扫描，训练记录不会中断。")
        }
        .sheet(isPresented: $showExerciseLibrary) { exerciseLibrarySheet }
        .sheet(isPresented: $showWorkoutEditor) {
            if let editorDraft = store.makeActiveWorkoutEditorDraft() {
                PlanEditorView(draft: editorDraft, mode: .activeWorkout)
            }
        }
        .sheet(isPresented: $showSessionRPE, onDismiss: {
            pendingSaveStatus = nil
        }) {
            sessionRPESheet
        }
        .fullScreenCover(item: $replacementExercise) { exercise in
            ExerciseReplacementView(currentPrescription: exercise, targetPhase: exercise.resolvedPhase) { option, transfer in
                guard var editor = store.makeActiveWorkoutEditorDraft(),
                      let updated = try? PlanEditingEngine.replace(
                        exerciseID: exercise.id,
                        with: option,
                        loadTransfer: transfer,
                        in: editor
                      ) else { return }
                editor = updated
                try? store.commitActiveWorkoutEditorDraft(editor)
                replacementExercise = nil
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func workoutContent(_ draft: WorkoutDraft) -> some View {
        let exercise = draft.session.exercises[draft.exerciseIndex]
        VStack(spacing: 0) {
            topBar(draft)
            ScrollView {
                VStack(spacing: 16) {
                    prominentProgress(draft, exercise: exercise)
                    exerciseCard(draft, exercise: exercise)
                    completedSetsCard(draft, exercise: exercise)
                    if draft.phase == .training || draft.phase == .setActive {
                        inputCard(draft)
                        safetyCard(draft)
                        setTimer(draft)
                        primarySetAction(draft)
                    } else if draft.phase == .resting {
                        restCard(draft)
                    } else {
                        exerciseCompleteCard(draft, exercise: exercise)
                    }
                }
                .padding(18)
                .padding(.bottom, 28)
            }
        }
    }

    private func topBar(_ draft: WorkoutDraft) -> some View {
        HStack {
            Button { showExitDialog = true } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(FitTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("退出训练")

            Spacer()
            VStack(spacing: 2) {
                Text(draft.session.name).font(.headline)
                Text(liveSensors.latestSample?.heartRateBPM.map { "实时心率 \(Int($0.rounded())) bpm" } ?? "实时自动缓存 · 心率估算")
                    .font(.caption2.bold())
                    .foregroundStyle(liveSensors.latestValidity == .valid ? FitTheme.accent : FitTheme.warning)
            }
            Spacer()
            Button {
                if draft.currentPauseStartedAt == nil {
                    store.pauseWorkout()
                } else {
                    store.resumeWorkout()
                }
            } label: {
                Image(systemName: draft.currentPauseStartedAt == nil ? "pause.fill" : "play.fill")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(FitTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(draft.currentPauseStartedAt == nil ? "暂停训练" : "继续训练")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private func prominentProgress(_ draft: WorkoutDraft, exercise: ExercisePrescription) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("动作 \(draft.exerciseIndex + 1) / \(draft.session.exercises.count)")
                    .font(.caption.bold())
                    .foregroundStyle(FitTheme.accent)
                Spacer()
                Text("整场已完成 \(draft.results.count) 组")
                    .font(.caption.bold())
                    .foregroundStyle(FitTheme.secondaryText)
            }
            Text("\(setKindText(draft)) \(draft.currentPhaseOrdinal) / \(draft.currentPhaseTotal)")
                .font(.system(size: 42, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("当前\(setKindText(draft))第 \(draft.currentPhaseOrdinal) 组，共 \(draft.currentPhaseTotal) 组")
            ProgressView(value: Double(min(draft.setNumber, draft.totalPlannedSets)), total: Double(max(1, draft.totalPlannedSets)))
                .tint(FitTheme.accent)
        }
        .fitCard(padding: 18)
    }

    private func exerciseCard(_ draft: WorkoutDraft, exercise: ExercisePrescription) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name).font(.title.bold()).minimumScaleFactor(0.72)
                    Text(exercise.targetText).font(.subheadline).foregroundStyle(FitTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2).foregroundStyle(FitTheme.accent)
            }

            HStack(spacing: 10) {
                Button { store.returnDraftToPreviousExercise() } label: {
                    Label("上个动作", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(draft.currentPauseStartedAt != nil || draft.exerciseIndex == 0)
                Button {
                    if !store.advanceDraftToNextExercise() {
                        requestSave(status: .partial)
                    }
                } label: {
                    Label("下个动作", systemImage: "chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(draft.currentPauseStartedAt != nil)
            }

            HStack(spacing: 10) {
                Button { replacementExercise = exercise } label: {
                    Label("更换动作/器械", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(draft.results.contains { $0.exerciseID == exercise.id })

                Button { showExerciseLibrary = true } label: {
                    Label("增加动作", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button { showWorkoutEditor = true } label: {
                Label("调整剩余动作与顺序", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(FitTheme.accentBlue)

            Button(role: .destructive) { store.removeDraftCurrentExercise() } label: {
                Label("移除当前动作", systemImage: "minus.circle")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
            .disabled(draft.session.exercises.count <= 1 || draft.results.contains { $0.exerciseID == exercise.id })

            Divider().overlay(Color.white.opacity(0.08))
            IntegerInputControl(
                title: "正式组数",
                value: Binding(get: { draft.totalWorkingSets }, set: { store.setDraftPlannedSets($0) }),
                range: 1...12,
                step: 1,
                unit: "组"
            )
            IntegerInputControl(
                title: "其中热身组",
                value: Binding(get: { draft.currentWarmupSets }, set: { store.setDraftWarmupSets($0) }),
                range: 0...6,
                step: 1,
                unit: "组"
            )
            Text("正式组与热身组分别计算；例如 2 个热身组 + 4 个正式组，共完成 6 组。算法不会自动减少或提前结束。")
                .font(.caption)
                .foregroundStyle(FitTheme.secondaryText)
        }
        .fitCard(padding: 18)
        .disabled(draft.currentPauseStartedAt != nil)
    }

    @ViewBuilder
    private func completedSetsCard(_ draft: WorkoutDraft, exercise: ExercisePrescription) -> some View {
        let sets = draft.results.filter { $0.exerciseID == exercise.id }
        if !sets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("本动作已完成", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(FitTheme.accent)
                ForEach(sets) { set in
                    HStack {
                        Text("第 \(set.setNumber) 组")
                            .font(.subheadline.bold().monospacedDigit())
                        Text(set.resolvedSetKind.title)
                            .font(.caption2.bold())
                            .foregroundStyle(set.resolvedSetKind == .warmup ? FitTheme.warning : FitTheme.accentBlue)
                        Spacer()
                        Text("\(set.loadKg.formatted(.number.precision(.fractionLength(0...1)))) kg × \(set.reps) · RIR \(set.rir)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(FitTheme.secondaryText)
                    }
                }
            }
            .fitCard()
        }
    }

    private func inputCard(_ draft: WorkoutDraft) -> some View {
        VStack(spacing: 4) {
            Picker("组类型", selection: Binding(get: { draft.currentSetKind }, set: { store.setDraftCurrentSetKind($0) })) {
                ForEach(SetKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.menu)
            divider
            NumericInputControl(title: "本组重量", value: doubleBinding(\.loadKg, marksLoadOverride: true), range: 0...400, step: store.profile?.loadIncrementKg ?? 2.5, unit: "kg", prominent: true)
            let choices = quickLoadChoices(for: draft)
            if !choices.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(choices) { choice in
                            Button("\(choice.label) \(choice.value.formatted(.number.precision(.fractionLength(0...2))))") {
                                store.updateWorkoutDraft {
                                    $0.loadKg = choice.value
                                    $0.userOverrodeSuggestedLoad = true
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(abs(choice.value - draft.loadKg) < 0.001 ? FitTheme.accent : FitTheme.accentBlue)
                        }
                    }
                }
            }
            divider
            IntegerInputControl(title: "完成次数", value: intBinding(\.reps), range: 1...100, step: 1, unit: "次")
            divider
            IntegerInputControl(title: "还可完成 RIR", value: intBinding(\.rir), range: draft.currentSetKind == .warmup ? 4...6 : 0...10, step: 1)
            divider
            techniqueControl(draft)
            divider
            NumericInputControl(title: "平均心率（可选）", value: doubleBinding(\.averageHeartRate), range: 0...220, step: 1, unit: "bpm")
            divider
            NumericInputControl(title: "设备主动热量（可选）", value: doubleBinding(\.measuredActiveEnergyKcal), range: 0...3000, step: 5, unit: "kcal")
            Toggle(isOn: boolBinding(\.hasPain)) {
                Label("疼痛或异常不适", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(draft.hasPain ? FitTheme.danger : FitTheme.secondaryText)
            }
            .tint(FitTheme.danger)
            .padding(.top, 12)
        }
        .fitCard(padding: 18)
        .disabled(draft.currentPauseStartedAt != nil)
    }

    @ViewBuilder
    private func safetyCard(_ draft: WorkoutDraft) -> some View {
        if draft.hasPain || draft.techniqueQuality <= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    draft.hasPain ? "建议停止并评估异常不适" : "动作质量下降",
                    systemImage: "exclamationmark.octagon.fill"
                )
                .font(.headline).foregroundStyle(FitTheme.danger)
                Text(draft.hasPain
                    ? "尖锐疼痛、胸痛、眩晕、麻木或异常气短时应停止训练并视情况寻求专业帮助。系统不会替你自动结束。"
                    : "建议检查动作幅度与控制，必要时自行减重或结束本动作；该提示不改变重量计算。")
                    .font(.subheadline).foregroundStyle(FitTheme.secondaryText)
                Button("保存当前内容并结束") { requestSave(status: .partial) }
                    .font(.subheadline.bold()).foregroundStyle(FitTheme.danger)
            }
            .fitCard()
        }
    }

    @ViewBuilder
    private func primarySetAction(_ draft: WorkoutDraft) -> some View {
        switch draft.phase {
        case .training:
            Button { store.startCurrentDraftSet() } label: {
                Label("开始本组", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(draft.currentPauseStartedAt != nil)
        case .setActive:
            Button { store.completeCurrentDraftSet() } label: {
                Label("完成本组", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(draft.currentPauseStartedAt != nil)
        case .resting, .exerciseComplete:
            EmptyView()
        }
    }

    @ViewBuilder
    private func setTimer(_ draft: WorkoutDraft) -> some View {
        if draft.phase == .setActive {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 4) {
                    Text("本组计时")
                        .font(.caption.bold())
                        .foregroundStyle(FitTheme.secondaryText)
                    Text(formatSeconds(activeSetElapsedSeconds(draft, at: context.date)))
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                        .foregroundStyle(FitTheme.accent)
                        .frame(width: 96, height: 32)
                        .accessibilityLabel("本组已进行 \(activeSetElapsedSeconds(draft, at: context.date)) 秒")
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 60)
        } else {
            Color.clear
                .frame(height: 60)
                .accessibilityHidden(true)
        }
    }

    private func restCard(_ draft: WorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let load = draft.recommendation {
                VStack(alignment: .leading, spacing: 5) {
                    Text("下一组建议重量")
                        .font(.caption.bold()).foregroundStyle(FitTheme.secondaryText)
                    Text("\(load.nextLoadKg.formatted(.number.precision(.fractionLength(0...1)))) kg")
                        .font(.title.bold().monospacedDigit()).foregroundStyle(FitTheme.accentBlue)
                    Text(load.reason).font(.caption).foregroundStyle(FitTheme.secondaryText)
                    Text("仅为参考；进入下一组后可直接修改重量。")
                        .font(.caption.bold()).foregroundStyle(FitTheme.warning)
                }
            }

            if let rest = draft.restRecommendation {
                Divider().overlay(Color.white.opacity(0.08))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = restRemaining(draft, at: context.date)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("建议组间休息").font(.headline)
                                Text("区间 \(formatSeconds(rest.lowerSeconds))–\(formatSeconds(rest.upperSeconds)) · \(rest.confidence)置信度")
                                    .font(.caption).foregroundStyle(FitTheme.secondaryText)
                            }
                            Spacer()
                            Text(formatSeconds(remaining))
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .monospacedDigit().foregroundStyle(remaining == 0 ? FitTheme.accent : .primary)
                        }
                        ForEach(rest.reasons, id: \.self) { reason in
                            Label(reason, systemImage: "info.circle")
                                .font(.caption).foregroundStyle(FitTheme.secondaryText)
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button("+30 秒") { extendRest(by: 30) }
                        .buttonStyle(.bordered)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    recoveryStatus(draft, at: context.date)
                }
                Text(liveSensors.statusMessage)
                    .font(.caption)
                    .foregroundStyle(liveSensors.latestValidity == .valid ? FitTheme.accentBlue : FitTheme.warning)
                Button { store.startNextDraftSet() } label: {
                    Label("开始下一组", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(draft.currentPauseStartedAt != nil)
            }
        }
        .fitCard(padding: 18)
        .disabled(draft.currentPauseStartedAt != nil)
    }

    private func exerciseCompleteCard(_ draft: WorkoutDraft, exercise: ExercisePrescription) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 66, weight: .bold)).foregroundStyle(FitTheme.accent)
                .symbolEffect(.bounce, value: draft.phase)
            Text("\(exercise.name) 已完成").font(.title2.bold()).multilineTextAlignment(.center)
            Text("你仍可在上方增加预计总组数；系统不会自动锁定该动作。")
                .font(.subheadline).foregroundStyle(FitTheme.secondaryText).multilineTextAlignment(.center)
            if draft.exerciseIndex < draft.session.exercises.count - 1 {
                Button { store.advanceDraftToNextExercise() } label: {
                    Label("进入下一个动作", systemImage: "arrow.right")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(draft.currentPauseStartedAt != nil)
            } else {
                Button { requestSave(status: .completed) } label: {
                    Label("完成本次训练", systemImage: "flag.checkered")
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
        }
        .fitCard(padding: 22)
    }

    private func techniqueControl(_ draft: WorkoutDraft) -> some View {
        HStack {
            Text("动作质量").font(.subheadline).foregroundStyle(FitTheme.secondaryText)
            Spacer()
            HStack(spacing: 7) {
                ForEach(1...5, id: \.self) { score in
                    Button { store.updateWorkoutDraft { $0.techniqueQuality = score } } label: {
                        Text("\(score)")
                            .font(.caption.bold().monospacedDigit())
                            .frame(width: 30, height: 30)
                            .background(draft.techniqueQuality == score ? FitTheme.accent : FitTheme.elevated, in: Circle())
                            .foregroundStyle(draft.techniqueQuality == score ? FitTheme.background : FitTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var exerciseLibrarySheet: some View {
        NavigationStack {
            List {
                ForEach(ExerciseCategory.allCases) { category in
                    let categoryItems = (TrainingEngine.allExerciseOptions + store.customExercises)
                        .filter { $0.resolvedCategory == category }
                        .sorted {
                            let leftFavorite = store.favoriteExerciseIDs.contains($0.id)
                            let rightFavorite = store.favoriteExerciseIDs.contains($1.id)
                            if leftFavorite != rightFavorite { return leftFavorite }
                            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                        }
                    if !categoryItems.isEmpty {
                        Section(category.title) {
                            ForEach(EquipmentKind.allCases) { equipment in
                                let items = categoryItems.filter { $0.equipment == equipment }
                                if !items.isEmpty {
                                    DisclosureGroup(equipment.title) {
                                        ForEach(items) { option in
                                            HStack {
                                                Button {
                                                    store.addDraftExercise(option)
                                                    showExerciseLibrary = false
                                                } label: {
                                                    HStack {
                                                        Text(option.name)
                                                        if option.source == .custom {
                                                            Text("自定义").font(.caption2).foregroundStyle(FitTheme.warning)
                                                        }
                                                        Spacer()
                                                    }
                                                }
                                                .disabled(store.activeWorkoutDraft?.currentPauseStartedAt != nil)
                                                Button { store.toggleFavoriteExercise(option.id) } label: {
                                                    Image(systemName: store.favoriteExerciseIDs.contains(option.id) ? "star.fill" : "star")
                                                        .foregroundStyle(store.favoriteExerciseIDs.contains(option.id) ? FitTheme.warning : FitTheme.secondaryText)
                                                }
                                                .buttonStyle(.plain)
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

    private var divider: some View {
        Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 8)
    }

    private func setKindText(_ draft: WorkoutDraft) -> String {
        if draft.currentSetKind == .warmup {
            return "热身组 \(draft.setNumber) / \(max(1, draft.currentWarmupSets))"
        }
        return "\(draft.currentSetKind.title) \(draft.workingSetOrdinal) / \(max(1, draft.totalWorkingSets))"
    }

    private func restRemaining(_ draft: WorkoutDraft, at date: Date) -> Int {
        guard let rest = draft.restRecommendation, let started = draft.restStartedAt else { return 0 }
        return max(0, rest.recommendedSeconds - Int(date.timeIntervalSince(started)))
    }

    private func activeSetElapsedSeconds(_ draft: WorkoutDraft, at date: Date) -> Int {
        guard let startedAt = draft.currentSetStartedAt else { return 0 }
        return Int(WorkoutTimeline.effectiveDuration(
            from: startedAt,
            to: max(startedAt, date),
            pauseIntervals: draft.pauseIntervals,
            currentPauseStartedAt: draft.currentPauseStartedAt
        ))
    }

    @ViewBuilder
    private func recoveryStatus(_ draft: WorkoutDraft, at date: Date) -> some View {
        if let set = draft.results.last(where: { $0.exerciseID == draft.currentExercise.id }) {
            let response = set.heartRateResponse
            let recovery = TrainingEngine.personalRecoveryComparison(
                currentResponse: response,
                currentSet: set,
                history: store.workoutHistory
            )
            VStack(alignment: .leading, spacing: 6) {
                Label(recoveryMeasurementText(response, draft: draft, at: date), systemImage: "waveform.path.ecg")
                    .font(.caption.bold())
                    .foregroundStyle(response == nil ? FitTheme.warning : FitTheme.accentBlue)
                if response != nil {
                    Label(
                        recovery.calibrationPairs >= 5
                            ? "已结合个人同动作恢复"
                            : "个人校准中 \(recovery.calibrationPairs)/5",
                        systemImage: recovery.calibrationPairs >= 5 ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.clock"
                    )
                    .font(.caption)
                    .foregroundStyle(FitTheme.secondaryText)
                }
                Text("心率与休息均为参考，不会锁定下一组、自动结束或替你改变重量。")
                    .font(.caption2)
                    .foregroundStyle(FitTheme.secondaryText)
            }
        }
    }

    private func recoveryMeasurementText(_ response: SetHeartRateResponse?, draft: WorkoutDraft, at date: Date) -> String {
        guard let response else {
            if let restStartedAt = draft.restStartedAt,
               date.timeIntervalSince(restStartedAt) <= 120,
               liveSensors.latestValidity == .valid {
                return "正在确认组后心率峰值"
            }
            return "样本不足，保持基础休息建议"
        }
        if let hrr60 = response.hrr60 {
            return "峰后 60 秒恢复 \(Int(hrr60.rounded())) bpm"
        }
        if response.peakDelaySeconds > 0 {
            return "峰值延后 \(response.peakDelaySeconds) 秒"
        }
        return "正在确认组后心率峰值"
    }

    private func extendRest(by seconds: Int) {
        store.updateWorkoutDraft { draft in
            guard var rest = draft.restRecommendation else { return }
            rest.recommendedSeconds = min(600, rest.recommendedSeconds + seconds)
            rest.upperSeconds = max(rest.upperSeconds, rest.recommendedSeconds)
            rest.reasons.append("用户主动延长 \(seconds) 秒")
            draft.restRecommendation = rest
        }
    }

    private func appendLatestLiveSample() {
        guard let sample = liveSensors.latestSample else { return }
        store.appendLiveMetricSample(sample, validity: liveSensors.latestValidity)
    }

    private func quickLoadChoices(for draft: WorkoutDraft) -> [LoadQuickChoice] {
        let exercise = draft.currentExercise
        var choices: [LoadQuickChoice] = []
        var used: [Double] = []
        func append(_ label: String, _ value: Double?) {
            guard let value, value > 0, !used.contains(where: { abs($0 - value) < 0.001 }) else { return }
            used.append(value)
            choices.append(LoadQuickChoice(label: label, value: value))
        }
        append("建议", draft.recommendation?.nextLoadKg ?? exercise.suggestedLoadKg)
        append("上组", draft.results.last(where: { $0.exerciseID == exercise.id })?.loadKg)
        let historical = store.workoutHistory
            .sorted { $0.completedAt > $1.completedAt }
            .flatMap { $0.sets.reversed() }
            .filter { set in
                if let left = TrainingEngine.canonicalExercise(named: set.exerciseName),
                   let right = TrainingEngine.canonicalExercise(named: exercise.name) {
                    return left.id == right.id
                }
                return set.exerciseName == exercise.name
            }
        append("上次", historical.first?.loadKg)
        for value in historical.map(\.loadKg) where choices.count < 5 { append("最近", value) }
        return choices
    }

    private func formatSeconds(_ value: Int) -> String {
        "\(value / 60):\(String(format: "%02d", value % 60))"
    }

    private var sessionRPESheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("这是一项整场主观用力感受，不会从每组 RIR 自动推算。")
                    .font(.subheadline)
                    .foregroundStyle(FitTheme.secondaryText)
                    .multilineTextAlignment(.center)
                Text("\(pendingSessionRPE)")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(FitTheme.accent)
                    .frame(height: 64)
                    .accessibilityLabel("整场主观用力程度 \(pendingSessionRPE)")
                Stepper("session-RPE \(pendingSessionRPE)", value: $pendingSessionRPE, in: 1...10)
                    .font(.headline)
                Button("确认并保存") {
                    guard let status = pendingSaveStatus else { return }
                    store.setWorkoutSessionRPE(Double(pendingSessionRPE))
                    performSaveAndExit(status: status)
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
            .padding(24)
            .navigationTitle("整场用力程度 1–10")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showSessionRPE = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func requestSave(status: WorkoutCompletionStatus) {
        pendingSaveStatus = status
        pendingSessionRPE = Int((store.activeWorkoutDraft?.sessionRPE ?? 7).rounded())
        showSessionRPE = true
    }

    private func performSaveAndExit(status: WorkoutCompletionStatus) {
        showSessionRPE = false
        liveSensors.endWorkout()
        WorkoutActivityController.shared.end()
        store.saveActiveWorkout(status: status)
        dismiss()
    }

    private func updateLiveActivity() {
        guard let draft = store.activeWorkoutDraft else { return }
        WorkoutActivityController.shared.startOrUpdate(.strength(draft: draft, heartRate: liveSensors.latestValidity == .valid ? liveSensors.latestSample?.heartRateBPM : nil))
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<WorkoutDraft, Double>, marksLoadOverride: Bool = false) -> Binding<Double> {
        Binding(
            get: { store.activeWorkoutDraft?[keyPath: keyPath] ?? 0 },
            set: { value in
                store.updateWorkoutDraft {
                    $0[keyPath: keyPath] = value
                    if marksLoadOverride { $0.userOverrodeSuggestedLoad = true }
                }
            }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<WorkoutDraft, Int>) -> Binding<Int> {
        Binding(
            get: { store.activeWorkoutDraft?[keyPath: keyPath] ?? 0 },
            set: { value in store.updateWorkoutDraft { $0[keyPath: keyPath] = value } }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<WorkoutDraft, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.activeWorkoutDraft?[keyPath: keyPath] ?? false },
            set: { value in store.updateWorkoutDraft { $0[keyPath: keyPath] = value } }
        )
    }
}
