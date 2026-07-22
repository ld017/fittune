import Foundation

enum ExerciseCatalog {
    static let builtIns: [ExerciseOption] = normalize(
        TrainingEngine.legacyExerciseLibrary + additionalExercises
    )

    static func resolve(idOrAlias value: String) -> ExerciseOption? {
        let normalized = value.normalizedExerciseName
        return builtIns.first { option in
            option.id == value
                || option.replacementIDs.contains(value)
                || option.name.normalizedExerciseName == normalized
                || option.aliases.contains { $0.normalizedExerciseName == normalized }
        }
    }

    private static let additionalExercises: [ExerciseOption] = {
        let specs: [(String, MovementPattern, EquipmentKind, MuscleGroup)] = [
            // 胸
            ("片装式水平推胸", .horizontalPush, .plateLoadedMachine, .chest),
            ("片装式上斜推胸", .horizontalPush, .plateLoadedMachine, .chest),
            ("片装式下斜推胸", .horizontalPush, .plateLoadedMachine, .chest),
            ("单臂片装式推胸", .horizontalPush, .plateLoadedMachine, .chest),
            ("跪姿地雷管推胸", .horizontalPush, .landmine, .chest),
            ("单臂地雷管推胸", .horizontalPush, .landmine, .chest),
            ("壶铃地板卧推", .horizontalPush, .kettlebell, .chest),
            ("交替哑铃卧推", .horizontalPush, .dumbbell, .chest),
            ("单臂绳索推胸", .horizontalPush, .cable, .chest),
            ("上斜俯卧撑", .horizontalPush, .bodyweight, .chest),
            ("下斜俯卧撑", .horizontalPush, .bodyweight, .chest),
            ("环式俯卧撑", .horizontalPush, .bodyweight, .chest),
            ("仰卧绳索夹胸", .chestIsolation, .cable, .chest),
            ("单臂绳索夹胸", .chestIsolation, .cable, .chest),

            // 背
            ("地雷管划船", .horizontalPull, .landmine, .back),
            ("单臂地雷管划船", .horizontalPull, .landmine, .back),
            ("胸托地雷管划船", .horizontalPull, .landmine, .back),
            ("片装式高位下拉", .verticalPull, .plateLoadedMachine, .back),
            ("片装式单臂高位下拉", .verticalPull, .plateLoadedMachine, .back),
            ("片装式低位划船", .horizontalPull, .plateLoadedMachine, .back),
            ("片装式胸托划船", .horizontalPull, .plateLoadedMachine, .back),
            ("单臂片装式划船", .horizontalPull, .plateLoadedMachine, .back),
            ("宽握坐姿划船", .horizontalPull, .cable, .back),
            ("窄握坐姿划船", .horizontalPull, .cable, .back),
            ("反握坐姿划船", .horizontalPull, .cable, .back),
            ("高位绳索划船", .horizontalPull, .cable, .back),
            ("半跪姿单臂下拉", .verticalPull, .cable, .back),
            ("交替单臂高位下拉", .verticalPull, .cable, .back),
            ("V 把高位下拉", .verticalPull, .cable, .back),
            ("跪姿直臂下压", .verticalPull, .cable, .back),
            ("弹力带引体辅助", .verticalPull, .resistanceBand, .back),
            ("弹力带直臂下压", .verticalPull, .resistanceBand, .back),
            ("弹力带单臂划船", .horizontalPull, .resistanceBand, .back),
            ("毛巾引体向上", .verticalPull, .bodyweight, .back),
            ("对握引体向上", .verticalPull, .bodyweight, .back),
            ("宽握引体向上", .verticalPull, .bodyweight, .back),
            ("负重反握引体", .verticalPull, .bodyweight, .back),
            ("壶铃俯身划船", .horizontalPull, .kettlebell, .back),
            ("单臂壶铃划船", .horizontalPull, .kettlebell, .back),

            // 肩
            ("片装式推肩", .verticalPush, .plateLoadedMachine, .shoulders),
            ("单臂片装式推肩", .verticalPush, .plateLoadedMachine, .shoulders),
            ("地雷管半跪姿推举", .verticalPush, .landmine, .shoulders),
            ("双手地雷管推举", .verticalPush, .landmine, .shoulders),
            ("壶铃单臂推举", .verticalPush, .kettlebell, .shoulders),
            ("壶铃底朝上推举", .verticalPush, .kettlebell, .shoulders),
            ("哑铃古巴推举", .verticalPush, .dumbbell, .shoulders),
            ("交替哑铃推举", .verticalPush, .dumbbell, .shoulders),
            ("绳索前平举", .shoulderIsolation, .cable, .shoulders),
            ("杠铃前平举", .shoulderIsolation, .barbell, .shoulders),
            ("杠铃片前平举", .shoulderIsolation, .barbell, .shoulders),
            ("倾斜哑铃侧平举", .shoulderIsolation, .dumbbell, .shoulders),
            ("上斜凳侧卧侧平举", .shoulderIsolation, .dumbbell, .shoulders),
            ("双臂绳索侧平举", .shoulderIsolation, .cable, .shoulders),
            ("绳索 Y 举", .shoulderIsolation, .cable, .shoulders),
            ("哑铃 Y 举", .shoulderIsolation, .dumbbell, .shoulders),
            ("弹力带反向飞鸟", .shoulderIsolation, .resistanceBand, .shoulders),
            ("弹力带前平举", .shoulderIsolation, .resistanceBand, .shoulders),
            ("弹力带外展侧平举", .shoulderIsolation, .resistanceBand, .shoulders),

            // 股四头
            ("壶铃高脚杯深蹲", .squat, .kettlebell, .quadriceps),
            ("双壶铃前蹲", .squat, .kettlebell, .quadriceps),
            ("地雷管深蹲", .squat, .landmine, .quadriceps),
            ("地雷管反向箭步蹲", .singleLeg, .landmine, .quadriceps),
            ("片装式哈克深蹲", .squat, .plateLoadedMachine, .quadriceps),
            ("片装式腿举", .squat, .plateLoadedMachine, .quadriceps),
            ("窄站距腿举", .squat, .plateLoadedMachine, .quadriceps),
            ("前脚抬高分腿蹲", .singleLeg, .dumbbell, .quadriceps),
            ("行走箭步蹲", .singleLeg, .dumbbell, .quadriceps),
            ("侧向箭步蹲", .singleLeg, .dumbbell, .quadriceps),
            ("弹力带西西深蹲", .squat, .resistanceBand, .quadriceps),
            ("辅助单腿蹲", .singleLeg, .bodyweight, .quadriceps),

            // 臀腿后侧
            ("罗马椅山羊挺身", .hinge, .romanChair, .posteriorChain),
            ("负重罗马椅山羊挺身", .hinge, .romanChair, .posteriorChain),
            ("罗马椅臀部挺身", .hinge, .romanChair, .posteriorChain),
            ("壶铃罗马尼亚硬拉", .hinge, .kettlebell, .posteriorChain),
            ("壶铃摆动", .hinge, .kettlebell, .posteriorChain),
            ("地雷管罗马尼亚硬拉", .hinge, .landmine, .posteriorChain),
            ("片装式臀推", .hinge, .plateLoadedMachine, .posteriorChain),
            ("单腿臀推机", .hinge, .plateLoadedMachine, .posteriorChain),
            ("哑铃早安式", .hinge, .dumbbell, .posteriorChain),
            ("绳索拉胯", .hinge, .cable, .posteriorChain),
            ("健身球腿弯举", .kneeFlexion, .bodyweight, .posteriorChain),
            ("单腿滑垫腿弯举", .kneeFlexion, .bodyweight, .posteriorChain),
            ("弹力带站姿腿弯举", .kneeFlexion, .resistanceBand, .posteriorChain),
            ("弹力带早安式", .hinge, .resistanceBand, .posteriorChain),

            // 小腿
            ("腿举机提踵", .calves, .plateLoadedMachine, .calves),
            ("史密斯站姿提踵", .calves, .smithMachine, .calves),
            ("驴式提踵", .calves, .bodyweight, .calves),
            ("壶铃单腿提踵", .calves, .kettlebell, .calves),
            ("弹力带跖屈", .calves, .resistanceBand, .calves),
            ("坐姿哑铃提踵", .calves, .dumbbell, .calves),
            ("台阶双腿提踵", .calves, .bodyweight, .calves),

            // 肱二头
            ("交替哑铃弯举", .arms, .dumbbell, .biceps),
            ("坐姿哑铃弯举", .arms, .dumbbell, .biceps),
            ("集中弯举", .arms, .dumbbell, .biceps),
            ("蜘蛛弯举", .arms, .barbell, .biceps),
            ("EZ 杠反握牧师凳弯举", .arms, .barbell, .biceps),
            ("绳索锤式弯举", .arms, .cable, .biceps),
            ("绳索反向弯举", .arms, .cable, .biceps),
            ("单臂绳索弯举", .arms, .cable, .biceps),
            ("高位绳索弯举", .arms, .cable, .biceps),
            ("片装式牧师凳弯举", .arms, .plateLoadedMachine, .biceps),
            ("弹力带弯举", .arms, .resistanceBand, .biceps),
            ("弹力带锤式弯举", .arms, .resistanceBand, .biceps),
            ("壶铃弯举", .arms, .kettlebell, .biceps),
            ("壶铃锤式弯举", .arms, .kettlebell, .biceps),

            // 肱三头
            ("杠铃窄握卧推", .arms, .barbell, .triceps),
            ("EZ 杠仰卧臂屈伸", .arms, .barbell, .triceps),
            ("哑铃仰卧臂屈伸", .arms, .dumbbell, .triceps),
            ("单臂哑铃过顶臂屈伸", .arms, .dumbbell, .triceps),
            ("双手哑铃过顶臂屈伸", .arms, .dumbbell, .triceps),
            ("哑铃俯身臂屈伸", .arms, .dumbbell, .triceps),
            ("直杆绳索下压", .arms, .cable, .triceps),
            ("V 把绳索下压", .arms, .cable, .triceps),
            ("反握绳索下压", .arms, .cable, .triceps),
            ("单臂反握下压", .arms, .cable, .triceps),
            ("绳索仰卧臂屈伸", .arms, .cable, .triceps),
            ("固定器械臂屈伸", .arms, .selectorizedMachine, .triceps),
            ("片装式双杠臂屈伸", .arms, .plateLoadedMachine, .triceps),
            ("弹力带下压", .arms, .resistanceBand, .triceps),
            ("弹力带过顶臂屈伸", .arms, .resistanceBand, .triceps),
            ("钻石俯卧撑", .arms, .bodyweight, .triceps),

            // 前臂与握力
            ("杠铃腕弯举", .arms, .barbell, .forearmsGrip),
            ("杠铃反向腕弯举", .arms, .barbell, .forearmsGrip),
            ("哑铃腕弯举", .arms, .dumbbell, .forearmsGrip),
            ("哑铃反向腕弯举", .arms, .dumbbell, .forearmsGrip),
            ("哑铃旋前旋后", .arms, .dumbbell, .forearmsGrip),
            ("腕力滚轴", .arms, .bodyweight, .forearmsGrip),
            ("杠铃静态握持", .arms, .barbell, .forearmsGrip),
            ("哑铃行李箱行走", .core, .dumbbell, .forearmsGrip),
            ("壶铃农夫行走", .core, .kettlebell, .forearmsGrip),
            ("单臂壶铃行李箱行走", .core, .kettlebell, .forearmsGrip),
            ("毛巾悬垂", .arms, .bodyweight, .forearmsGrip),
            ("单杠悬垂", .arms, .bodyweight, .forearmsGrip),
            ("杠铃片捏握", .arms, .barbell, .forearmsGrip),
            ("弹力带手指伸展", .arms, .resistanceBand, .forearmsGrip),

            // 核心
            ("跪姿健腹轮", .core, .bodyweight, .core),
            ("站姿健腹轮", .core, .bodyweight, .core),
            ("悬垂举膝", .core, .bodyweight, .core),
            ("悬垂举腿", .core, .bodyweight, .core),
            ("仰卧反向卷腹", .core, .bodyweight, .core),
            ("卷腹触脚", .core, .bodyweight, .core),
            ("鸟狗式", .core, .bodyweight, .core),
            ("平板支撑", .core, .bodyweight, .core),
            ("长杠杆平板支撑", .core, .bodyweight, .core),
            ("哥本哈根侧桥", .core, .bodyweight, .core),
            ("绳索伐木", .core, .cable, .core),
            ("绳索反向伐木", .core, .cable, .core),
            ("半跪姿帕洛夫推", .core, .cable, .core),
            ("站姿帕洛夫推", .core, .cable, .core),
            ("地雷管转体", .core, .landmine, .core),
            ("壶铃绕体", .core, .kettlebell, .core),
            ("壶铃土耳其起立", .core, .kettlebell, .core),
            ("哑铃负重卷腹", .core, .dumbbell, .core),
            ("哑铃侧屈", .core, .dumbbell, .core),
            ("弹力带抗旋转推", .core, .resistanceBand, .core)
        ]

        return specs.map { name, pattern, equipment, primary in
            ExerciseOption(
                name: name,
                pattern: pattern,
                equipment: equipment,
                category: category(for: primary),
                primaryMuscles: [primary]
            )
        }
    }()

    private static func normalize(_ rawExercises: [ExerciseOption]) -> [ExerciseOption] {
        var catalog: [ExerciseOption] = []
        var indexByName: [String: Int] = [:]

        for raw in rawExercises where !raw.name.contains(" + ") {
            var option = raw
            let originalEquipment = option.equipment
            option.equipment = canonicalEquipment(for: option)
            let key = option.name.normalizedExerciseName
            guard !key.isEmpty else { continue }

            let oldID = "\(option.resolvedCategory.rawValue).\(originalEquipment.rawValue).\(option.pattern.rawValue).\(key)"
            let v10Equipment: EquipmentKind = originalEquipment == .machineCable
                ? (option.name.contains("绳索") ? .cable : .selectorizedMachine)
                : originalEquipment
            let v10ID = "\(option.resolvedCategory.rawValue).\(v10Equipment.rawValue).\(option.pattern.rawValue).\(key)"
            option.stableID = "\(option.resolvedCategory.rawValue).\(option.equipment.rawValue).\(option.pattern.rawValue).\(key)"
            for legacyID in [oldID, v10ID] where legacyID != option.stableID && !option.replacementIDs.contains(legacyID) {
                option.replacementIDs.append(legacyID)
            }
            enrich(&option)

            if let index = indexByName[key] {
                var existing = catalog[index]
                existing.aliases = Array(Set(existing.aliases + option.aliases)).sorted()
                existing.replacementIDs = Array(Set(existing.replacementIDs + option.replacementIDs)).sorted()
                catalog[index] = existing
            } else {
                indexByName[key] = catalog.count
                catalog.append(option)
            }
        }

        return catalog.sorted {
            let left = $0.primaryMuscles?.first?.rawValue ?? ""
            let right = $1.primaryMuscles?.first?.rawValue ?? ""
            if left != right { return left < right }
            if $0.pattern.rawValue != $1.pattern.rawValue { return $0.pattern.rawValue < $1.pattern.rawValue }
            if $0.equipment.rawValue != $1.equipment.rawValue { return $0.equipment.rawValue < $1.equipment.rawValue }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func canonicalEquipment(for option: ExerciseOption) -> EquipmentKind {
        if option.name.contains("蝴蝶机") { return .butterflyMachine }
        if option.equipment == .machineCable {
            return option.name.contains("绳索") ? .cable : .selectorizedMachine
        }
        if option.equipment == .bodyweightBand {
            return option.name.contains("弹力带") ? .resistanceBand : .bodyweight
        }
        return option.equipment
    }

    private static func enrich(_ option: inout ExerciseOption) {
        let primary = option.primaryMuscles ?? [derivedPrimaryMuscle(for: option)]
        option.primaryMuscles = primary
        option.secondaryMuscles = option.secondaryMuscles ?? derivedSecondaryMuscles(for: option).subtracting(primary)
        option.isCompound = option.isCompound ?? option.resolvedIsCompound
        option.difficulty = option.difficulty ?? derivedDifficulty(for: option)
        option.laterality = option.laterality ?? derivedLaterality(for: option.name)
        option.suitablePhases = option.suitablePhases ?? (option.resolvedIsCompound ? [.primary, .accessory] : [.accessory, .finisher])
    }

    private static func derivedPrimaryMuscle(for option: ExerciseOption) -> MuscleGroup {
        switch option.resolvedCategory {
        case .chest: return .chest
        case .back: return .back
        case .shoulders: return .shoulders
        case .quadriceps: return .quadriceps
        case .posteriorChain: return .posteriorChain
        case .calves: return .calves
        case .core, .conditioning: return .core
        case .arms:
            if option.name.contains("腕") || option.name.contains("握") || option.name.contains("悬垂") || option.name.contains("农夫") {
                return .forearmsGrip
            }
            if option.name.contains("臂屈伸") || option.name.contains("下压") || option.name.contains("窄距") || option.name.contains("三头") {
                return .triceps
            }
            return .biceps
        }
    }

    private static func derivedSecondaryMuscles(for option: ExerciseOption) -> Set<MuscleGroup> {
        switch option.pattern {
        case .horizontalPush: [.shoulders, .triceps]
        case .horizontalPull, .verticalPull: [.biceps, .forearmsGrip]
        case .verticalPush: [.triceps]
        case .squat, .singleLeg: [.posteriorChain, .core]
        case .hinge: [.back, .core]
        case .chestIsolation, .shoulderIsolation, .kneeFlexion, .calves, .arms, .core, .conditioning: []
        }
    }

    private static func derivedDifficulty(for option: ExerciseOption) -> ExerciseDifficulty {
        if option.name.contains("倒立") || option.name.contains("北欧") || option.name.contains("土耳其") || option.name.contains("单腿深蹲") {
            return .advanced
        }
        if [.selectorizedMachine, .plateLoadedMachine, .butterflyMachine, .resistanceBand].contains(option.equipment) {
            return .beginner
        }
        if option.resolvedIsCompound && option.equipment == .barbell { return .advanced }
        return .intermediate
    }

    private static func derivedLaterality(for name: String) -> Laterality {
        if name.contains("交替") { return .alternating }
        if name.contains("单臂") || name.contains("单腿") || name.contains("单侧") || name.contains("行李箱") { return .unilateral }
        return .bilateral
    }

    private static func category(for muscle: MuscleGroup) -> ExerciseCategory {
        switch muscle {
        case .chest: .chest
        case .back: .back
        case .shoulders: .shoulders
        case .quadriceps: .quadriceps
        case .posteriorChain: .posteriorChain
        case .calves: .calves
        case .biceps, .triceps, .forearmsGrip: .arms
        case .core: .core
        }
    }
}
