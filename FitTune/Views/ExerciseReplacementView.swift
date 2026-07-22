import SwiftUI

struct ExerciseReplacementView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let currentPrescription: ExercisePrescription?
    let targetPhase: TrainingPhase
    let onSelect: (ExerciseOption, ReplacementLoadTransfer) -> Void

    @State private var searchText = ""
    @State private var selectedMuscle: MuscleGroup?
    @State private var selectedPattern: MovementPattern?
    @State private var selectedEquipment: EquipmentKind?
    @State private var includeUnavailableEquipment = false

    var body: some View {
        NavigationStack {
            List {
                if let currentPrescription {
                    Section("当前动作") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(currentPrescription.name).font(.headline)
                            Text("保留组数、次数范围、RIR 与\(targetPhase.title)位置；不同动作或器械的重量会重新校准。")
                                .font(.caption)
                                .foregroundStyle(FitTheme.secondaryText)
                        }
                    }
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterMenu(title: selectedMuscle.map(muscleTitle) ?? "肌群", value: $selectedMuscle, values: MuscleGroup.allCases, label: muscleTitle)
                            filterMenu(title: selectedPattern?.title ?? "动作模式", value: $selectedPattern, values: MovementPattern.allCases, label: { $0.title })
                            filterMenu(title: selectedEquipment?.title ?? "器械", value: $selectedEquipment, values: EquipmentKind.allCases, label: { $0.title })
                            FilterChip(title: targetPhase.title, isSelected: true) {}
                        }
                    }
                    Toggle("显示当前不可用器械", isOn: $includeUnavailableEquipment)
                    Button("清除全部筛选") {
                        selectedMuscle = nil
                        selectedPattern = nil
                        selectedEquipment = nil
                        searchText = ""
                    }
                } header: {
                    Text("筛选")
                } footer: {
                    Text("默认排除已禁用、涉及避让部位及当前器械条件不支持的动作；展开不可用器械后会明确标记。")
                }

                if currentPrescription != nil, !recommended.isEmpty {
                    Section("优先推荐") {
                        ForEach(Array(recommended.prefix(8))) { candidate in
                            candidateRow(candidate)
                        }
                    }
                }

                ForEach(browseMuscles, id: \.self) { muscle in
                    Section(muscleTitle(muscle)) {
                        ForEach(patterns(for: muscle), id: \.self) { pattern in
                            DisclosureGroup(pattern.title) {
                                ForEach(browseItems(muscle: muscle, pattern: pattern)) { option in
                                    browseRow(option)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索动作或器械")
            .scrollContentBackground(.hidden)
            .background(FitBackground())
            .navigationTitle(currentPrescription == nil ? "添加动作" : "替换动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var catalog: [ExerciseOption] {
        ExerciseCatalog.builtIns + store.customExercises
    }

    private var currentOption: ExerciseOption? {
        guard let currentPrescription else { return nil }
        return ExerciseCatalog.resolve(idOrAlias: currentPrescription.name)
            ?? store.customExercises.first(where: { $0.name == currentPrescription.name })
            ?? ExerciseOption(
                name: currentPrescription.name,
                pattern: currentPrescription.pattern,
                equipment: currentPrescription.equipmentKind ?? .bodyweight
            )
    }

    private var ranked: [ExerciseReplacementCandidate] {
        guard let currentOption else { return [] }
        return ExerciseReplacementEngine.rank(
            catalog: catalog,
            context: ExerciseReplacementContext(
                current: currentOption,
                phase: targetPhase,
                availableEquipment: availableEquipment,
                disabledExerciseIDs: store.safetySettings.disabledExerciseIDs,
                injuredMuscles: injuredMuscles,
                favoriteIDs: store.favoriteExerciseIDs,
                recentExerciseIDs: recentExerciseIDs,
                includeUnavailableEquipment: includeUnavailableEquipment
            )
        )
    }

    private var recommended: [ExerciseReplacementCandidate] {
        ranked.filter { matchesFilters($0.exercise) }
    }

    private var visibleBrowseItems: [ExerciseOption] {
        let rankedIDs = Set(ranked.map(\.id))
        return catalog.filter { option in
            let permitted = currentPrescription == nil
                ? !store.safetySettings.disabledExerciseIDs.contains(option.id)
                    && (includeUnavailableEquipment || availableEquipment.contains(option.equipment))
                    && (option.primaryMuscles ?? []).isDisjoint(with: injuredMuscles)
                : rankedIDs.contains(option.id)
            return permitted && matchesFilters(option)
        }
    }

    private var browseMuscles: [MuscleGroup] {
        MuscleGroup.allCases.filter { muscle in
            visibleBrowseItems.contains { $0.primaryMuscles?.contains(muscle) == true }
        }
    }

    private func patterns(for muscle: MuscleGroup) -> [MovementPattern] {
        MovementPattern.allCases.filter { pattern in
            visibleBrowseItems.contains { $0.pattern == pattern && $0.primaryMuscles?.contains(muscle) == true }
        }
    }

    private func browseItems(muscle: MuscleGroup, pattern: MovementPattern) -> [ExerciseOption] {
        visibleBrowseItems
            .filter { $0.pattern == pattern && $0.primaryMuscles?.contains(muscle) == true }
            .sorted { left, right in
                if left.equipment != right.equipment { return left.equipment.title < right.equipment.title }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    private func candidateRow(_ candidate: ExerciseReplacementCandidate) -> some View {
        Button { select(candidate.exercise) } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(candidate.exercise.name).font(.headline)
                        if store.favoriteExerciseIDs.contains(candidate.id) {
                            Image(systemName: "star.fill").foregroundStyle(FitTheme.warning)
                        }
                    }
                    Text("\(candidate.exercise.equipment.title) · \(candidate.reasons.prefix(3).joined(separator: " · "))")
                        .font(.caption)
                        .foregroundStyle(FitTheme.secondaryText)
                    Text(loadTransfer(for: candidate.exercise).reason)
                        .font(.caption2)
                        .foregroundStyle(candidate.equipmentAvailable ? FitTheme.accentBlue : FitTheme.warning)
                }
                Spacer()
                Text("\(candidate.score)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(FitTheme.accent)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            favoriteButton(candidate.exercise)
        }
    }

    private func browseRow(_ option: ExerciseOption) -> some View {
        Button { select(option) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                    Text(option.equipment.title)
                        .font(.caption2)
                        .foregroundStyle(availableEquipment.contains(option.equipment) ? FitTheme.secondaryText : FitTheme.warning)
                }
                Spacer()
                if option.source == .custom { Text("自定义").font(.caption2).foregroundStyle(FitTheme.warning) }
                if store.favoriteExerciseIDs.contains(option.id) { Image(systemName: "star.fill").foregroundStyle(FitTheme.warning) }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) { favoriteButton(option) }
    }

    private func select(_ option: ExerciseOption) {
        onSelect(option, loadTransfer(for: option))
        dismiss()
    }

    private func loadTransfer(for option: ExerciseOption) -> ReplacementLoadTransfer {
        guard let currentPrescription else {
            return .init(suggestedLoadKg: nil, confidence: .unavailable, reason: "新增动作将在首组校准重量")
        }
        return ExerciseReplacementEngine.transferLoad(from: currentPrescription, to: option, history: store.workoutHistory)
    }

    private func favoriteButton(_ option: ExerciseOption) -> some View {
        Button { store.toggleFavoriteExercise(option.id) } label: {
            Label(store.favoriteExerciseIDs.contains(option.id) ? "取消收藏" : "收藏", systemImage: "star")
        }
        .tint(FitTheme.warning)
    }

    private func matchesFilters(_ option: ExerciseOption) -> Bool {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (normalizedSearch.isEmpty || option.name.localizedCaseInsensitiveContains(normalizedSearch) || option.equipment.title.localizedCaseInsensitiveContains(normalizedSearch))
            && (selectedMuscle == nil || option.primaryMuscles?.contains(selectedMuscle!) == true)
            && (selectedPattern == nil || option.pattern == selectedPattern)
            && (selectedEquipment == nil || option.equipment == selectedEquipment)
    }

    private func filterMenu<Value: Hashable>(
        title: String,
        value: Binding<Value?>,
        values: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        Menu {
            Button("全部") { value.wrappedValue = nil }
            ForEach(values, id: \.self) { item in
                Button(label(item)) { value.wrappedValue = item }
            }
        } label: {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(value.wrappedValue != nil ? FitTheme.background : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(value.wrappedValue != nil ? FitTheme.accent : FitTheme.elevated, in: Capsule())
        }
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

    private var recentExerciseIDs: [String] {
        store.workoutHistory.prefix(5).flatMap(\.sets).compactMap { set in
            ExerciseCatalog.resolve(idOrAlias: set.exerciseName)?.id
        }
    }

    private func muscleTitle(_ muscle: MuscleGroup) -> String {
        switch muscle {
        case .chest: "胸"
        case .back: "背"
        case .shoulders: "肩"
        case .quadriceps: "股四头"
        case .posteriorChain: "臀腿后侧"
        case .calves: "小腿"
        case .biceps: "肱二头"
        case .triceps: "肱三头"
        case .forearmsGrip: "前臂/握力"
        case .core: "核心"
        }
    }
}
