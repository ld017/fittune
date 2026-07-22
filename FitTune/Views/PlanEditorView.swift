import SwiftUI

struct PlanEditorView: View {
    enum Mode: Equatable {
        case plan
        case activeWorkout
    }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlanEditorDraft
    @State private var catalogRequest: CatalogRequest?
    @State private var errorMessage: String?
    @State private var showTemplateConfirmation = false

    let mode: Mode

    init(draft: PlanEditorDraft, mode: Mode) {
        _draft = State(initialValue: draft)
        self.mode = mode
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("训练名称", text: $draft.sessionName)
                    TextField("训练重点", text: $draft.focus)
                } header: {
                    Text("训练信息")
                }

                ForEach(TrainingPhase.allCases) { phase in
                    Section {
                        let exercises = draft.exercises(in: phase)
                        ForEach(exercises) { exercise in
                            exerciseRow(exercise, phase: phase, sectionExercises: exercises)
                                .moveDisabled(isLocked(exercise.id))
                        }
                        .onMove { offsets, destination in
                            moveWithinPhase(phase, offsets: offsets, destination: destination)
                        }

                        Button {
                            catalogRequest = .add(phase: phase, index: exercises.count)
                        } label: {
                            Label("添加到(phase.title)", systemImage: "plus.circle.fill")
                                .foregroundStyle(FitTheme.accent)
                        }
                    } header: {
                        HStack {
                            Text(phase.title)
                            Spacer()
                            Text("\(draft.exercises(in: phase).count) 个动作")
                        }
                    } footer: {
                        Text(phaseHelp(phase))
                    }
                }

                if mode == .activeWorkout {
                    Section {
                        Button("保存为以后模板") { showTemplateConfirmation = true }
                    } footer: {
                        Text("“完成”只修改本次训练；保存为模板会另外更新以后使用的原计划。")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FitBackground())
            .environment(\.editMode, .constant(.active))
            .navigationTitle(mode == .plan ? "编辑训练编排" : "调整剩余动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { commit(saveTemplate: false) }
                        .fontWeight(.semibold)
                        .disabled(draft.exercises.isEmpty)
                }
            }
        }
        .fullScreenCover(item: $catalogRequest) { request in
            ExerciseReplacementView(
                currentPrescription: request.currentExercise(in: draft),
                targetPhase: request.phase
            ) { option, transfer in
                applyCatalogSelection(option, transfer: transfer, request: request)
                catalogRequest = nil
            }
        }
        .alert("无法保存编排", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
        .confirmationDialog("更新以后使用的训练模板？", isPresented: $showTemplateConfirmation) {
            Button("保存本次调整并更新模板") { commit(saveTemplate: true) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("训练开始时保存的历史快照不会改变。")
        }
    }

    private func exerciseRow(
        _ exercise: ExercisePrescription,
        phase: TrainingPhase,
        sectionExercises: [ExercisePrescription]
    ) -> some View {
        let locked = isLocked(exercise.id)
        let warnings = advisoryWarnings(for: exercise, phase: phase)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: locked ? "lock.fill" : "line.3.horizontal")
                    .foregroundStyle(locked ? FitTheme.secondaryText : FitTheme.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name).font(.headline)
                    Text(exercise.targetText)
                        .font(.caption)
                        .foregroundStyle(FitTheme.secondaryText)
                    if locked {
                        Text("已记录 \(completedSetCount(exercise.id)) 组 · 当前动作不可修改")
                            .font(.caption2.bold())
                            .foregroundStyle(FitTheme.warning)
                    }
                }
                Spacer()
                Menu {
                    Button {
                        catalogRequest = .replace(exerciseID: exercise.id, phase: phase)
                    } label: {
                        Label("替换动作", systemImage: "arrow.triangle.2.circlepath")
                    }
                    ForEach(TrainingPhase.allCases.filter { $0 != phase }) { destination in
                        Button {
                            move(exercise.id, to: destination, at: draft.exercises(in: destination).count)
                        } label: {
                            Label("移到\(destination.title)", systemImage: "arrow.right")
                        }
                    }
                    Button {
                        let position = (sectionExercises.firstIndex(where: { $0.id == exercise.id }) ?? 0) + 1
                        catalogRequest = .add(phase: phase, index: position)
                    } label: {
                        Label("在下方添加", systemImage: "plus")
                    }
                    Button(role: .destructive) { remove(exercise.id) } label: {
                        Label("删除动作", systemImage: "trash")
                    }
                    .disabled(draft.exercises.count <= 1)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(FitTheme.accentBlue)
                }
                .disabled(locked)
            }
            if !warnings.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(warnings, id: \.self) { warning in
                        AdvisoryBadge(text: warning)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func moveWithinPhase(_ phase: TrainingPhase, offsets: IndexSet, destination: Int) {
        let items = draft.exercises(in: phase)
        guard !offsets.contains(where: { isLocked(items[$0].id) }) else { return }
        var reordered = items
        reordered.move(fromOffsets: offsets, toOffset: destination)
        var rebuilt: [ExercisePrescription] = []
        for section in TrainingPhase.allCases {
            rebuilt += section == phase ? reordered : draft.exercises(in: section)
        }
        draft.exercises = rebuilt
    }

    private func move(_ id: UUID, to phase: TrainingPhase, at index: Int) {
        guard !isLocked(id), let updated = try? PlanEditingEngine.move(exerciseID: id, to: phase, at: index, in: draft) else { return }
        draft = updated
    }

    private func remove(_ id: UUID) {
        guard !isLocked(id) else { return }
        do { draft = try PlanEditingEngine.remove(exerciseID: id, from: draft) }
        catch { errorMessage = "训练至少需要保留一个动作。" }
    }

    private func applyCatalogSelection(
        _ option: ExerciseOption,
        transfer: ReplacementLoadTransfer,
        request: CatalogRequest
    ) {
        switch request {
        case let .replace(exerciseID, _):
            if let updated = try? PlanEditingEngine.replace(
                exerciseID: exerciseID,
                with: option,
                loadTransfer: transfer,
                in: draft
            ) { draft = updated }
        case let .add(phase, index):
            let prescription: ExercisePrescription
            if let profile = store.profile {
                prescription = TrainingEngine.makePrescription(for: option, profile: profile)
            } else {
                prescription = ExercisePrescription(
                    name: option.name,
                    pattern: option.pattern,
                    sets: 4,
                    repLower: 8,
                    repUpper: 12,
                    targetRIR: 0,
                    isPriority: phase == .primary,
                    equipmentKind: option.equipment,
                    workingSets: 4
                )
            }
            draft = PlanEditingEngine.add(prescription, to: phase, at: index, in: draft)
        }
    }

    private func commit(saveTemplate: Bool) {
        do {
            switch mode {
            case .plan:
                store.commitPlanEditorDraft(draft)
            case .activeWorkout:
                try store.commitActiveWorkoutEditorDraft(draft)
                if saveTemplate { try store.saveActiveWorkoutLayoutToSourcePlan() }
            }
            dismiss()
        } catch PlanEditError.lockedExercise {
            errorMessage = "已经记录训练组的动作不能被替换、删除或改动。"
        } catch {
            errorMessage = "原训练计划已发生变化，请关闭后重新打开编辑器。"
        }
    }

    private func isLocked(_ id: UUID) -> Bool {
        guard mode == .activeWorkout, let active = store.activeWorkoutDraft else { return false }
        return PlanEditingEngine.isLocked(exerciseID: id, in: active)
    }

    private func completedSetCount(_ id: UUID) -> Int {
        store.activeWorkoutDraft?.results.filter { $0.exerciseID == id }.count ?? 0
    }

    private func advisoryWarnings(for exercise: ExercisePrescription, phase: TrainingPhase) -> [String] {
        guard let option = ExerciseCatalog.resolve(idOrAlias: exercise.name)
            ?? store.customExercises.first(where: { $0.name == exercise.name }) else { return [] }
        var warnings: [String] = []
        if option.suitablePhases?.contains(phase) == false { warnings.append("阶段非常规") }
        if !availableEquipment.contains(option.equipment) { warnings.append("器械可能不可用") }
        if !(option.primaryMuscles ?? []).isDisjoint(with: injuredMuscles) { warnings.append("涉及避让部位") }
        return warnings
    }

    private var availableEquipment: Set<EquipmentKind> {
        switch store.profile?.equipment ?? .fullGym {
        case .fullGym: Set(EquipmentKind.allCases)
        case .dumbbells: [.dumbbell, .bodyweight, .resistanceBand, .bodyweightBand]
        case .bodyweightBands: [.bodyweight, .resistanceBand, .bodyweightBand]
        }
    }

    private var injuredMuscles: Set<MuscleGroup> {
        store.safetySettings.avoidedRegions.reduce(into: []) { result, region in
            switch region {
            case .chest: result.insert(.chest)
            case .back: result.insert(.back)
            case .shoulders: result.insert(.shoulders)
            case .legs: result.formUnion([.quadriceps, .posteriorChain, .calves])
            }
        }
    }

    private func phaseHelp(_ phase: TrainingPhase) -> String {
        switch phase {
        case .primary: "优先完成、需要较高专注度的主要动作。"
        case .accessory: "补充目标肌群与训练量的辅助动作。"
        case .finisher: "训练末段的孤立、泵感或低风险收尾动作。"
        }
    }
}

private enum CatalogRequest: Identifiable {
    case replace(exerciseID: UUID, phase: TrainingPhase)
    case add(phase: TrainingPhase, index: Int)

    var id: String {
        switch self {
        case let .replace(id, _): "replace-\(id)"
        case let .add(phase, index): "add-\(phase.rawValue)-\(index)"
        }
    }

    var phase: TrainingPhase {
        switch self {
        case let .replace(_, phase), let .add(phase, _): phase
        }
    }

    func currentExercise(in draft: PlanEditorDraft) -> ExercisePrescription? {
        guard case let .replace(id, _) = self else { return nil }
        return draft.exercises.first { $0.id == id }
    }
}
