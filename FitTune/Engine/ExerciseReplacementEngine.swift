import Foundation

struct ExerciseReplacementContext: Equatable {
    var current: ExerciseOption
    var phase: TrainingPhase
    var availableEquipment: Set<EquipmentKind>
    var disabledExerciseIDs: Set<String>
    var injuredMuscles: Set<MuscleGroup>
    var favoriteIDs: Set<String>
    var recentExerciseIDs: [String]
    var includeUnavailableEquipment: Bool
}

struct ExerciseReplacementCandidate: Identifiable, Equatable {
    var exercise: ExerciseOption
    var score: Int
    var reasons: [String]
    var equipmentAvailable: Bool

    var id: String { exercise.id }
}

struct ReplacementLoadTransfer: Equatable {
    var suggestedLoadKg: Double?
    var confidence: DataConfidence
    var reason: String
}

struct ExerciseBrowserFilters: Equatable {
    var search = ""
    var selectedMuscle: MuscleGroup?
    var selectedPattern: MovementPattern?
    var selectedEquipment: EquipmentKind?
    var availableEquipment: Set<EquipmentKind> = Set(EquipmentKind.allCases)
    var disabledExerciseIDs: Set<String> = []
    var injuredMuscles: Set<MuscleGroup> = []
    var includeUnavailableEquipment = false
}

struct ExerciseBrowserPatternGroup: Identifiable, Equatable {
    var pattern: MovementPattern
    var items: [ExerciseOption]
    var id: MovementPattern { pattern }
}

struct ExerciseBrowserMuscleSection: Identifiable, Equatable {
    var muscle: MuscleGroup
    var groups: [ExerciseBrowserPatternGroup]
    var id: MuscleGroup { muscle }
}

struct ExerciseBrowserSnapshot: Equatable {
    var recommended: [ExerciseReplacementCandidate]
    var sections: [ExerciseBrowserMuscleSection]
    var loadTransfers: [String: ReplacementLoadTransfer]

    static let empty = ExerciseBrowserSnapshot(recommended: [], sections: [], loadTransfers: [:])
}

enum ExerciseReplacementEngine {
    static func rank(
        catalog: [ExerciseOption],
        context: ExerciseReplacementContext
    ) -> [ExerciseReplacementCandidate] {
        let currentPrimary = context.current.primaryMuscles ?? []
        let currentSecondary = context.current.secondaryMuscles ?? []

        return catalog.compactMap { exercise -> ExerciseReplacementCandidate? in
            guard exercise.id != context.current.id,
                  !context.disabledExerciseIDs.contains(exercise.id) else { return nil }

            let primary = exercise.primaryMuscles ?? []
            guard primary.isDisjoint(with: context.injuredMuscles) else { return nil }

            let equipmentAvailable = context.availableEquipment.contains(exercise.equipment)
            guard equipmentAvailable || context.includeUnavailableEquipment else { return nil }

            var score = 0
            var reasons: [String] = []

            if exercise.pattern == context.current.pattern {
                score += 40
                reasons.append("同为\(shortPatternTitle(exercise.pattern))")
            }

            let primaryOverlap = primary.intersection(currentPrimary)
            if !primaryOverlap.isEmpty {
                score += primaryOverlap.count * 12
                reasons.append("主练\(muscleNames(primaryOverlap))")
            }

            let secondaryOverlap = (exercise.secondaryMuscles ?? []).intersection(currentSecondary)
            if !secondaryOverlap.isEmpty {
                score += secondaryOverlap.count * 4
                reasons.append("辅助肌群相近")
            }

            if exercise.suitablePhases?.contains(context.phase) == true {
                score += 10
                reasons.append("适合\(context.phase.title)")
            }

            if exercise.equipment == context.current.equipment {
                score += 8
                reasons.append("同器械")
            } else if equipmentAvailable {
                score += 4
                reasons.append("器械可用")
            }

            if exercise.difficulty == context.current.difficulty {
                score += 5
                reasons.append("难度相近")
            } else if difficultyDistance(exercise.difficulty, context.current.difficulty) == 1 {
                score += 2
            }

            if context.favoriteIDs.contains(exercise.id) {
                score += 8
                reasons.append("已收藏")
            }
            if context.recentExerciseIDs.contains(exercise.id) {
                score += 4
                reasons.append("近期训练表现可参考")
            }

            return ExerciseReplacementCandidate(
                exercise: exercise,
                score: score,
                reasons: reasons,
                equipmentAvailable: equipmentAvailable
            )
        }
        .sorted { left, right in
            if left.score != right.score { return left.score > right.score }
            let leftFavorite = context.favoriteIDs.contains(left.id)
            let rightFavorite = context.favoriteIDs.contains(right.id)
            if leftFavorite != rightFavorite { return leftFavorite }
            return left.exercise.name.localizedStandardCompare(right.exercise.name) == .orderedAscending
        }
    }

    static func transferLoad(
        from prescription: ExercisePrescription,
        to replacement: ExerciseOption,
        history: [WorkoutRecord]
    ) -> ReplacementLoadTransfer {
        if prescription.name.normalizedExerciseName == replacement.name.normalizedExerciseName,
           prescription.equipmentKind == replacement.equipment,
           let load = prescription.suggestedLoadKg {
            return ReplacementLoadTransfer(
                suggestedLoadKg: load,
                confidence: .derived,
                reason: "同一动作与器械，保留当前建议重量"
            )
        }

        let exactSet = history
            .sorted { $0.completedAt > $1.completedAt }
            .lazy
            .compactMap { record in
                record.sets.last { $0.exerciseName.normalizedExerciseName == replacement.name.normalizedExerciseName }
            }
            .first
        if let exactSet {
            return ReplacementLoadTransfer(
                suggestedLoadKg: exactSet.loadKg,
                confidence: .derived,
                reason: "采用该动作最近一次实际完成重量，需用首组重新校准"
            )
        }

        return ReplacementLoadTransfer(
            suggestedLoadKg: nil,
            confidence: .unavailable,
            reason: "动作或器械不同，暂不换算重量，请手动输入并用首组校准"
        )
    }

    static func browserSnapshot(
        catalog: [ExerciseOption],
        replacementContext: ExerciseReplacementContext?,
        filters: ExerciseBrowserFilters,
        history: [WorkoutRecord],
        currentPrescription: ExercisePrescription?
    ) -> ExerciseBrowserSnapshot {
        let ranked = replacementContext.map { rank(catalog: catalog, context: $0) } ?? []
        let rankedIDs = Set(ranked.map(\.id))
        let effectiveEquipment = replacementContext?.availableEquipment ?? filters.availableEquipment
        let effectiveDisabledIDs = replacementContext?.disabledExerciseIDs ?? filters.disabledExerciseIDs
        let effectiveInjuredMuscles = replacementContext?.injuredMuscles ?? filters.injuredMuscles
        let includeUnavailable = replacementContext?.includeUnavailableEquipment ?? filters.includeUnavailableEquipment

        let visibleItems = catalog.filter { option in
            let permitted: Bool
            if replacementContext != nil {
                permitted = rankedIDs.contains(option.id)
            } else {
                permitted = !effectiveDisabledIDs.contains(option.id)
                    && (includeUnavailable || effectiveEquipment.contains(option.equipment))
                    && (option.primaryMuscles ?? []).isDisjoint(with: effectiveInjuredMuscles)
            }
            return permitted && matches(option, filters: filters)
        }

        let sections = MuscleGroup.allCases.compactMap { muscle -> ExerciseBrowserMuscleSection? in
            let groups = MovementPattern.allCases.compactMap { pattern -> ExerciseBrowserPatternGroup? in
                let items = visibleItems
                    .filter { $0.pattern == pattern && $0.primaryMuscles?.contains(muscle) == true }
                    .sorted(by: browseOrder)
                return items.isEmpty ? nil : ExerciseBrowserPatternGroup(pattern: pattern, items: items)
            }
            return groups.isEmpty ? nil : ExerciseBrowserMuscleSection(muscle: muscle, groups: groups)
        }

        let recommended = ranked.filter { matches($0.exercise, filters: filters) }
        let recentLoads = recentLoadIndex(history: history)
        var transferItems: [String: ExerciseOption] = [:]
        for option in visibleItems + recommended.map(\.exercise) {
            transferItems[option.id] = option
        }
        let transfers = transferItems.mapValues { option in
            indexedTransferLoad(
                from: currentPrescription,
                to: option,
                recentLoads: recentLoads
            )
        }
        return ExerciseBrowserSnapshot(
            recommended: recommended,
            sections: sections,
            loadTransfers: transfers
        )
    }

    private static func matches(_ option: ExerciseOption, filters: ExerciseBrowserFilters) -> Bool {
        let search = filters.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchesSearch = search.isEmpty
            || option.name.localizedCaseInsensitiveContains(search)
            || option.equipment.title.localizedCaseInsensitiveContains(search)
            || option.aliases.contains { $0.localizedCaseInsensitiveContains(search) }
        return matchesSearch
            && (filters.selectedMuscle == nil || option.primaryMuscles?.contains(filters.selectedMuscle!) == true)
            && (filters.selectedPattern == nil || option.pattern == filters.selectedPattern)
            && (filters.selectedEquipment == nil || option.equipment == filters.selectedEquipment)
    }

    private static func browseOrder(_ left: ExerciseOption, _ right: ExerciseOption) -> Bool {
        if left.equipment != right.equipment {
            return left.equipment.title < right.equipment.title
        }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
    }

    private static func recentLoadIndex(history: [WorkoutRecord]) -> [String: Double] {
        var result: [String: Double] = [:]
        for record in history.sorted(by: { $0.completedAt > $1.completedAt }) {
            for set in record.sets.reversed() {
                let key = set.exerciseName.normalizedExerciseName
                if result[key] == nil {
                    result[key] = set.loadKg
                }
            }
        }
        return result
    }

    private static func indexedTransferLoad(
        from prescription: ExercisePrescription?,
        to replacement: ExerciseOption,
        recentLoads: [String: Double]
    ) -> ReplacementLoadTransfer {
        guard let prescription else {
            return ReplacementLoadTransfer(
                suggestedLoadKg: nil,
                confidence: .unavailable,
                reason: "新增动作将在首组校准重量"
            )
        }
        if prescription.name.normalizedExerciseName == replacement.name.normalizedExerciseName,
           prescription.equipmentKind == replacement.equipment,
           let load = prescription.suggestedLoadKg {
            return ReplacementLoadTransfer(
                suggestedLoadKg: load,
                confidence: .derived,
                reason: "同一动作与器械，保留当前建议重量"
            )
        }
        if let load = recentLoads[replacement.name.normalizedExerciseName] {
            return ReplacementLoadTransfer(
                suggestedLoadKg: load,
                confidence: .derived,
                reason: "采用该动作最近一次实际完成重量，需用首组重新校准"
            )
        }
        return ReplacementLoadTransfer(
            suggestedLoadKg: nil,
            confidence: .unavailable,
            reason: "动作或器械不同，暂不换算重量，请手动输入并用首组校准"
        )
    }

    private static func difficultyDistance(
        _ left: ExerciseDifficulty?,
        _ right: ExerciseDifficulty?
    ) -> Int? {
        let order: [ExerciseDifficulty] = [.beginner, .intermediate, .advanced]
        guard let left, let right,
              let leftIndex = order.firstIndex(of: left),
              let rightIndex = order.firstIndex(of: right) else { return nil }
        return abs(leftIndex - rightIndex)
    }

    private static func shortPatternTitle(_ pattern: MovementPattern) -> String {
        switch pattern {
        case .squat: "深蹲"
        case .hinge: "髋铰链"
        case .horizontalPush: "水平推"
        case .horizontalPull: "水平拉"
        case .verticalPush: "垂直推"
        case .verticalPull: "垂直拉"
        case .singleLeg: "单腿训练"
        case .arms: "手臂训练"
        case .core: "核心训练"
        case .chestIsolation: "胸部孤立"
        case .shoulderIsolation: "肩部孤立"
        case .kneeFlexion: "屈膝训练"
        case .calves: "小腿训练"
        case .conditioning: "体能训练"
        }
    }

    private static func muscleNames(_ muscles: Set<MuscleGroup>) -> String {
        let names = muscles.sorted { $0.rawValue < $1.rawValue }.map { muscle in
            switch muscle {
            case .chest: "胸部"
            case .back: "背部"
            case .shoulders: "肩部"
            case .quadriceps: "股四头肌"
            case .posteriorChain: "臀腿后侧"
            case .calves: "小腿"
            case .biceps: "肱二头肌"
            case .triceps: "肱三头肌"
            case .forearmsGrip: "前臂与握力"
            case .core: "核心"
            }
        }
        return names.joined(separator: "、")
    }
}
