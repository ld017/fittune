import Foundation

enum TrainingEngine {
    static let ruleVersion = "1.1.1-live-history-cardio-1"

    static func assessReadiness(_ input: ReadinessInput) -> ReadinessAssessment {
        let sleepDuration = min(max(input.sleepHours / 8.0, 0), 1) * 100
        let sleepQuality = Double(min(max(input.sleepQuality ?? Int((input.sleepHours / 2).rounded()), 1), 5)) * 20
        let soreness = Double(6 - min(max(input.soreness, 1), 5)) * 20
        let stress = Double(6 - min(max(input.stress, 1), 5)) * 20
        let motivation = Double(min(max(input.motivation, 1), 5)) * 20
        let raw = sleepDuration * 0.25 + sleepQuality * 0.15 + soreness * 0.20 + stress * 0.20 + motivation * 0.20
        let score = Int(raw.rounded())

        if score >= 72 {
            return ReadinessAssessment(
                score: score,
                level: .ready,
                summary: "按原计划训练，并用第一组表现确认今天的工作重量。",
                loadMultiplier: 1,
                setReduction: 0
            )
        }
        if score >= 52 {
            return ReadinessAssessment(
                score: score,
                level: .moderate,
                summary: "先完成热身；首组建议会结合睡眠、上次表现与间隔下调约 5%。",
                loadMultiplier: 0.95,
                setReduction: 0
            )
        }
        return ReadinessAssessment(
            score: score,
            level: .low,
            summary: "建议降低重量并少做一组；若有异常不适，请停止训练。",
            loadMultiplier: 0.90,
            setReduction: 1
        )
    }

    static func warmupPrescription(workingLoadKg: Double, workingReps: Int, setCount: Int) -> [WarmupSetSuggestion] {
        guard setCount > 0 else { return [] }
        let count = min(4, setCount)
        let percentageTemplates: [Int: [Double]] = [
            1: [0.60],
            2: [0.45, 0.70],
            3: [0.40, 0.60, 0.80],
            4: [0.30, 0.50, 0.70, 0.85]
        ]
        let percentages = percentageTemplates[count] ?? [0.60]
        return percentages.enumerated().map { index, percentage in
            let rawLoad = max(0, workingLoadKg * percentage)
            let roundedLoad = (rawLoad / 2.5).rounded() * 2.5
            let extraReps = max(0, (count - index - 1) * 2)
            return WarmupSetSuggestion(
                loadKg: min(workingLoadKg, roundedLoad),
                reps: max(1, workingReps + extraReps),
                rir: 5
            )
        }
    }

    static func recommendNextSet(
        prescription: ExercisePrescription,
        result: SetResult,
        readiness: ReadinessAssessment,
        increment: Double,
        exerciseHistory: [SetResult] = [],
        priorRecord: WorkoutRecord? = nil
    ) -> SetRecommendation {
        let step = max(increment, 0.5)
        var factor = 1.0
        var action = LoadAdjustment.hold
        var reasons = ["完成次数与 RIR 处于目标范围"]
        let remainingSets = max(0, prescription.resolvedWorkingSets - result.setNumber)

        if result.reps < prescription.repLower || result.rir < prescription.targetRIR - 1 {
            factor = 0.925
            action = .decrease
            reasons = ["完成次数或实际 RIR 低于目标，建议保守减重"]
        } else if result.reps >= prescription.repUpper && result.rir > prescription.targetRIR + 1 {
            factor = 1.025
            action = .increase
            reasons = ["已达到次数上限且保留额外余力"]
        }

        if readiness.level == .low && action != .decrease {
            factor = min(factor, readiness.loadMultiplier)
            action = .decrease
            reasons.append("今天恢复信号偏低，采用保守重量")
        } else if readiness.level == .moderate && action == .increase {
            factor = 1
            action = .hold
            reasons.append("恢复状态一般，暂不在组间加重")
        }

        if priorRecord != nil || !exerciseHistory.isEmpty {
            reasons.append("已结合本动作训练历史")
        }

        var rounded = result.loadKg
        if result.loadKg > 0 {
            rounded = (result.loadKg * factor / step).rounded() * step
            if action == .increase && rounded <= result.loadKg {
                rounded = result.loadKg + step
            } else if action == .decrease && rounded >= result.loadKg {
                rounded = max(step, result.loadKg - step)
            }
        }

        return SetRecommendation(
            nextLoadKg: max(0, rounded),
            adjustment: action,
            reason: reasons.joined(separator: "；") + "。",
            confidence: result.rir <= 4 && (priorRecord != nil || !exerciseHistory.isEmpty) ? "高" : "中",
            restSeconds: prescription.isPriority ? 180 : 120,
            suggestedRemainingSets: remainingSets,
            continuation: .continueTraining
        )
    }

    static func recommendRest(
        current: SetResult,
        previous: SetResult?,
        setKind: SetKind,
        pattern: MovementPattern,
        historicalE1RM: Double?,
        readiness: ReadinessAssessment
    ) -> RestRecommendation {
        let compoundPatterns: Set<MovementPattern> = [
            .squat, .hinge, .horizontalPush, .horizontalPull,
            .verticalPush, .verticalPull, .singleLeg
        ]
        let isCompound = compoundPatterns.contains(pattern)
        let relativeLoad = historicalE1RM.flatMap { $0 > 0 ? current.loadKg / $0 : nil }
        var lower = setKind == .warmup ? 60 : (isCompound ? 120 : 90)
        var upper = setKind == .warmup ? 120 : (isCompound ? 240 : 180)
        var recommended = setKind == .warmup ? 90 : (isCompound ? 180 : 120)
        var reasons = [setKind == .warmup ? "热身组采用较短基准休息" : (isCompound ? "复合正式组采用较长基准休息" : "孤立正式组采用中等基准休息")]
        var inputs = ["组类型", "动作模式", "完成次数", "RIR", "今日恢复"]

        if setKind == .working && ((relativeLoad ?? 0) >= 0.80 || current.reps <= 6) {
            lower = 180
            upper = 300
            recommended = 240
            reasons.append("低次数或估计负荷不低于历史 e1RM 的 80%")
            if relativeLoad != nil { inputs.append("历史 e1RM") }
        }
        if current.rir == 0 {
            recommended += 60
            reasons.append("RIR 0，增加 60 秒")
        } else if current.rir == 1 {
            recommended += 30
            reasons.append("RIR 1，增加 30 秒")
        }
        if let previous,
           current.loadKg <= previous.loadKg,
           Double(current.reps) < Double(previous.reps) * 0.90 {
            recommended += 30
            reasons.append("次数较前组下降超过 10%，增加 30 秒")
            inputs.append("前组表现")
        }
        if readiness.level == .low {
            recommended += 30
            reasons.append("今日恢复偏低，增加 30 秒")
        }

        recommended = min(300, max(lower, recommended))
        upper = min(300, max(upper, recommended))
        let confidence = historicalE1RM == nil ? "中" : "中高"
        return RestRecommendation(
            lowerSeconds: lower,
            recommendedSeconds: recommended,
            upperSeconds: upper,
            confidence: confidence,
            reasons: reasons,
            inputsUsed: Array(Set(inputs)).sorted()
        )
    }

    static func recommendStartingLoad(
        prescription: ExercisePrescription,
        history: [WorkoutRecord],
        readiness: ReadinessAssessment,
        increment: Double,
        now: Date = .now
    ) -> StartingLoadRecommendation {
        if prescription.equipmentKind == .bodyweightBand {
            return StartingLoadRecommendation(
                loadKg: 0,
                adjustment: .hold,
                reason: "徒手或弹力带动作以动作难度、次数与 RIR 调节。",
                confidence: "中",
                daysSinceLast: nil
            )
        }

        let sortedHistory = history.sorted { $0.completedAt > $1.completedAt }
        let exactRecord = sortedHistory.first { record in
            record.sets.contains { $0.exerciseName == prescription.name && $0.loadKg > 0 }
        }
        let matchedByPattern = exactRecord == nil
        let record = exactRecord ?? sortedHistory.first { record in
            record.sets.contains { $0.movementPattern == prescription.pattern && $0.loadKg > 0 }
        }

        guard let record else {
            return StartingLoadRecommendation(
                loadKg: prescription.suggestedLoadKg,
                adjustment: .hold,
                reason: "尚无同动作历史。先用热身组找到能在目标 RIR 内稳定完成的重量，完成后自动建立建议。",
                confidence: "低",
                daysSinceLast: nil
            )
        }

        let relevantSets = record.sets.filter { set in
            guard set.loadKg > 0 else { return false }
            if exactRecord != nil { return set.exerciseName == prescription.name }
            return set.movementPattern == prescription.pattern
        }
        guard !relevantSets.isEmpty else {
            return StartingLoadRecommendation(loadKg: nil, adjustment: .hold, reason: "需要一次校准训练。", confidence: "低", daysSinceLast: nil)
        }

        let loads = relevantSets.map(\.loadKg).sorted()
        let baseline = loads[loads.count / 2]
        let meanReps = average(relevantSets.map { Double($0.reps) })
        let meanRIR = average(relevantSets.map { Double($0.rir) })
        let meanTechnique = average(relevantSets.map { Double($0.techniqueQuality ?? record.sessionQuality ?? 3) })
        let hoursSince = max(0, now.timeIntervalSince(record.completedAt) / 3600)
        let daysSince = Int(hoursSince / 24)
        let step = max(increment, 0.5)

        var factor = 1.0
        var reasons: [String] = []

        if meanTechnique < 3 || meanReps < Double(prescription.repLower) || meanRIR < Double(prescription.targetRIR - 1) {
            factor = 0.95
            reasons.append("上次完成质量或余力低于目标")
        } else if meanTechnique >= 4 && meanReps >= Double(prescription.repUpper) && meanRIR >= Double(prescription.targetRIR + 1) {
            factor = 1.025
            reasons.append("上次次数、RIR 与动作质量均达标")
        } else {
            reasons.append("上次表现处于目标范围")
        }

        switch hoursSince {
        case ..<24:
            factor = min(factor, 0.90)
            reasons.append("同模式训练不足 24 小时")
        case 24..<48:
            factor = min(factor, 0.95)
            reasons.append("同模式训练间隔不足 48 小时")
        case 48...168:
            reasons.append("已恢复约 \(max(daysSince, 2)) 天")
        case 168..<336:
            factor = min(factor, 0.95)
            reasons.append("距上次已超过 7 天，先保守回归")
        default:
            factor = min(factor, 0.90)
            reasons.append("距上次已超过 14 天，先重新校准")
        }

        if readiness.loadMultiplier < 1 {
            factor = min(factor, readiness.loadMultiplier)
            reasons.append("今日恢复分限制加重")
        }

        factor = min(max(factor, 0.90), 1.05)
        var rounded = (baseline * factor / step).rounded() * step
        if factor > 1, rounded <= baseline { rounded = baseline + step }
        if factor < 1, rounded >= baseline { rounded = max(step, baseline - step) }

        let adjustment: LoadAdjustment = rounded > baseline ? .increase : (rounded < baseline ? .decrease : .hold)
        return StartingLoadRecommendation(
            loadKg: rounded,
            adjustment: adjustment,
            reason: reasons.joined(separator: "；") + "。上次动作质量 \(meanTechnique.formatted(.number.precision(.fractionLength(1))))/5。",
            confidence: matchedByPattern ? "中" : (relevantSets.count >= 2 ? "中高" : "中"),
            daysSinceLast: daysSince
        )
    }

    static func estimatedOneRepMax(loadKg: Double, reps: Int, rir: Int) -> Double? {
        guard loadKg > 0, reps > 0 else { return nil }
        let estimatedMaxReps = min(reps + max(rir, 0), 12)
        return loadKg * (1 + Double(estimatedMaxReps) / 30.0)
    }

    static func weightTrend(entries: [WeightEntry]) -> Double? {
        let sorted = entries.sorted { $0.date < $1.date }
        guard sorted.count >= 4 else { return nil }
        let recent = Array(sorted.suffix(14))
        let split = max(1, recent.count / 2)
        let older = recent.prefix(split).map(\.kilograms)
        let newer = recent.suffix(recent.count - split).map(\.kilograms)
        guard !older.isEmpty, !newer.isEmpty else { return nil }
        return average(newer) - average(older)
    }

    static func generatePlan(
        for profile: UserProfile,
        favoriteExerciseIDs: Set<String> = [],
        customExercises: [ExerciseOption] = []
    ) -> TrainingPlan {
        let split = profile.splitPreference ?? .automatic
        let templates = splitTemplates(preference: split, days: profile.weeklyDays)
        let maxExercises: Int
        switch profile.sessionMinutes {
        case ..<45: maxExercises = 5
        case 45..<70: maxExercises = 6
        default: maxExercises = 8
        }

        let strengthGoal = effectiveStrengthGoal(for: profile)
        let sessions = templates.map { template in
            let exercises = template.patterns.prefix(maxExercises).enumerated().map { index, pattern in
                let option = preferredExercise(
                    for: pattern,
                    equipment: profile.equipment,
                    favoriteExerciseIDs: favoriteExerciseIDs,
                    customExercises: customExercises
                )
                return prescription(
                    option: option,
                    goal: strengthGoal,
                    experience: profile.experience,
                    priority: index < 2
                )
            }
            return TrainingSession(name: template.name, focus: template.focus, exercises: exercises)
        }

        return TrainingPlan(
            title: "\(displaySplit(split, days: profile.weeklyDays).title) · 力量 + 有氧",
            rationale: rationale(for: profile, sessionCount: sessions.count),
            sessions: sessions,
            generatedAt: .now,
            ruleVersion: ruleVersion,
            cardioSessions: cardioSessions(for: profile)
        )
    }

    static func nextSessionIndex(history: [WorkoutRecord], sessionCount: Int) -> Int? {
        guard sessionCount > 0 else { return nil }
        let fullyCompleted = history.filter { $0.resolvedCompletionStatus == .completed }.count
        return fullyCompleted % sessionCount
    }

    static func makeTodaySession(
        focus: DailyTrainingFocus,
        profile: UserProfile,
        recommendedSession: TrainingSession?,
        avoiding avoidedRegions: Set<BodyRegion>
    ) -> TrainingSession? {
        if let primaryRegion = focus.primaryRegion, avoidedRegions.contains(primaryRegion) {
            return nil
        }

        if focus == .recommended, let recommendedSession {
            var filtered = recommendedSession
            filtered.exercises = recommendedSession.exercises.filter {
                movementRegions(for: $0.pattern).isDisjoint(with: avoidedRegions)
            }
            guard !filtered.exercises.isEmpty else { return nil }
            filtered.focus = avoidanceDetail(base: recommendedSession.focus, avoidedRegions: avoidedRegions)
            return filtered
        }

        let template = dailyTemplate(for: focus)
        let allowedPatterns = template.patterns.filter {
            movementRegions(for: $0).isDisjoint(with: avoidedRegions)
        }
        guard !allowedPatterns.isEmpty else { return nil }

        let strengthGoal = effectiveStrengthGoal(for: profile)
        let exerciseLimit = maxExerciseCount(for: profile.sessionMinutes)
        let exercises = allowedPatterns.prefix(exerciseLimit).enumerated().map { index, pattern in
            prescription(
                option: preferredExercise(for: pattern, equipment: profile.equipment),
                goal: strengthGoal,
                experience: profile.experience,
                priority: index < 2
            )
        }
        guard !exercises.isEmpty else { return nil }
        return TrainingSession(
            name: template.name,
            focus: avoidanceDetail(base: template.focus, avoidedRegions: avoidedRegions),
            exercises: exercises
        )
    }

    static func movementRegions(for pattern: MovementPattern) -> Set<BodyRegion> {
        switch pattern {
        case .squat, .singleLeg, .kneeFlexion, .calves:
            [.legs]
        case .hinge:
            [.back, .legs]
        case .horizontalPush:
            [.chest, .shoulders]
        case .horizontalPull, .verticalPull:
            [.back]
        case .verticalPush, .shoulderIsolation:
            [.shoulders]
        case .chestIsolation:
            [.chest]
        case .arms, .core, .conditioning:
            []
        }
    }

    static func exerciseAlternatives(for pattern: MovementPattern) -> [ExerciseOption] {
        ExerciseCatalog.builtIns.filter { $0.pattern == pattern }
    }

    static var allExercises: [ExerciseOption] { ExerciseCatalog.builtIns }

    static var allExerciseOptions: [ExerciseOption] { ExerciseCatalog.builtIns }

    static func canonicalExercise(named name: String) -> ExerciseOption? {
        let key = name.normalizedExerciseName
        return ExerciseCatalog.builtIns.first { option in
            option.name.normalizedExerciseName == key
                || option.aliases.contains { $0.normalizedExerciseName == key }
        }
    }

    static func exerciseOption(named name: String, pattern: MovementPattern) -> ExerciseOption? {
        if let canonical = canonicalExercise(named: name), canonical.pattern == pattern {
            return canonical
        }
        return ExerciseCatalog.builtIns.first { $0.name == name && $0.pattern == pattern }
    }

    static func makePrescription(for option: ExerciseOption, profile: UserProfile, priority: Bool = false) -> ExercisePrescription {
        prescription(
            option: option,
            goal: effectiveStrengthGoal(for: profile),
            experience: profile.experience,
            priority: priority
        )
    }

    // Evidence hierarchy: measured RMR > Cunningham with measured/derived FFM
    // > Mifflin–St Jeor. Strength history is deliberately not used as a proxy
    // for muscle mass because it is not an independent RMR predictor.
    static func restingEnergy(profile: UserProfile, weightKg: Double? = nil) -> Double? {
        restingEnergyEstimate(profile: profile, weightKg: weightKg)?.kilocalories
    }

    static func restingEnergyEstimate(profile: UserProfile, weightKg: Double? = nil) -> EnergyEstimate? {
        if let measured = profile.measuredRMRKcal, (700...5000).contains(measured) {
            return EnergyEstimate(
                kilocalories: measured,
                lowerBound: measured * 0.95,
                upperBound: measured * 1.05,
                method: "实测静息代谢",
                confidence: "高"
            )
        }
        let weight = weightKg ?? profile.bodyWeightKg
        let leanMass: Double? = {
            if let value = profile.leanMassKg, value > 20, value <= weight { return value }
            if let bodyFat = profile.bodyFatPercent, (3...65).contains(bodyFat) {
                return weight * (1 - bodyFat / 100)
            }
            return nil
        }()
        if let leanMass {
            let value = 500 + 22 * leanMass
            return EnergyEstimate(
                kilocalories: value,
                lowerBound: value * 0.90,
                upperBound: value * 1.10,
                method: "Cunningham（去脂体重）",
                confidence: profile.leanMassKg != nil ? "中高" : "中"
            )
        }
        guard let age = profile.ageYears,
              let height = profile.heightCm,
              let sex = profile.biologicalSex,
              sex != .notSet,
              (14...100).contains(age),
              (120...230).contains(height) else { return nil }
        let base = 10 * weight + 6.25 * height - 5 * Double(age)
        let value = max(800, base + (sex == .male ? 5 : -161))
        return EnergyEstimate(
            kilocalories: value,
            lowerBound: value * 0.90,
            upperBound: value * 1.10,
            method: "Mifflin–St Jeor",
            confidence: "中"
        )
    }

    // Net activity calories subtract one resting MET so daily resting energy is
    // not counted a second time.
    static func netActiveEnergy(met: Double, weightKg: Double, minutes: Double) -> Double {
        max(0, met - 1) * 3.5 * weightKg / 200 * max(0, minutes)
    }

    static func cardioMET(modality: CardioModality, intensity: CardioIntensity) -> Double {
        switch (modality, intensity) {
        case (.inclineWalking, .recovery): 4.0
        case (.inclineWalking, .zone2): 6.5
        case (.inclineWalking, .intervals): 8.0
        case (.stairClimber, .recovery): 5.0
        case (.stairClimber, .zone2): 9.3
        case (.stairClimber, .intervals): 11.0
        case (.swimming, .recovery): 4.8
        case (.swimming, .zone2): 7.0
        case (.swimming, .intervals): 9.8
        case (.running, .recovery): 6.0
        case (.running, .zone2): 8.3
        case (.running, .intervals): 11.0
        case (.cycling, .recovery): 4.0
        case (.cycling, .zone2): 6.8
        case (.cycling, .intervals): 10.0
        case (.rowing, .recovery): 5.0
        case (.rowing, .zone2): 7.5
        case (.rowing, .intervals): 11.0
        case (.elliptical, .recovery): 4.0
        case (.elliptical, .zone2): 5.8
        case (.elliptical, .intervals): 8.0
        case (.briskWalking, .recovery): 3.5
        case (.briskWalking, .zone2): 4.8
        case (.briskWalking, .intervals): 6.0
        case (.jumpRope, .recovery): 8.8
        case (.jumpRope, .zone2): 11.0
        case (.jumpRope, .intervals): 12.3
        }
    }

    static func makeCardioWorkout(
        modality: CardioModality,
        intensity: CardioIntensity,
        minutes: Int,
        weightKg: Double,
        profile: UserProfile? = nil,
        distanceKm: Double? = nil,
        averageHeartRate: Double? = nil,
        speedKph: Double? = nil,
        inclinePercent: Double? = nil,
        powerWatts: Double? = nil,
        floorsClimbed: Double? = nil,
        sessionRPE: Double? = nil,
        measuredActiveEnergy: Double? = nil,
        source: String = "手动",
        externalID: String? = nil,
        date: Date = .now,
        metricSamples: [WorkoutMetricSample] = [],
        startedAt: Date? = nil
    ) -> CardioWorkoutRecord {
        let estimate = cardioEnergyEstimate(
            modality: modality,
            intensity: intensity,
            minutes: minutes,
            weightKg: weightKg,
            profile: profile,
            distanceKm: distanceKm,
            averageHeartRate: averageHeartRate,
            speedKph: speedKph,
            inclinePercent: inclinePercent,
            measuredActiveEnergy: measuredActiveEnergy,
            metricSamples: metricSamples,
            startedAt: startedAt
        )
        var record = CardioWorkoutRecord(
            date: date,
            modality: modality,
            intensity: intensity,
            durationMinutes: minutes,
            distanceKm: distanceKm,
            averageHeartRate: averageHeartRate,
            activeEnergyKcal: estimate.kilocalories,
            source: source,
            externalID: externalID,
            speedKph: speedKph,
            inclinePercent: inclinePercent,
            powerWatts: powerWatts,
            floorsClimbed: floorsClimbed,
            sessionRPE: sessionRPE,
            energyMethod: estimate.method,
            energyLowerBoundKcal: estimate.lowerBound,
            energyUpperBoundKcal: estimate.upperBound,
            energyAlgorithmVersion: EnergyEngine.algorithmVersion,
            metricSamples: metricSamples
        )
        record.effect = evaluateCardioWorkout(record)
        return record
    }

    static func cardioEnergyEstimate(
        modality: CardioModality,
        intensity: CardioIntensity,
        minutes: Int,
        weightKg: Double,
        profile: UserProfile? = nil,
        distanceKm: Double? = nil,
        averageHeartRate: Double? = nil,
        speedKph: Double? = nil,
        inclinePercent: Double? = nil,
        measuredActiveEnergy: Double? = nil,
        metricSamples: [WorkoutMetricSample] = [],
        startedAt: Date? = nil
    ) -> EnergyEstimate {
        let start = startedAt ?? .now.addingTimeInterval(-Double(minutes) * 60)
        let completedAt = start.addingTimeInterval(Double(minutes) * 60)
        let legacySegments = speedKph.map {
            [CardioWorkloadSegment(
                startedAt: start,
                endedAt: completedAt,
                speedKph: $0,
                inclinePercent: inclinePercent,
                source: .userEntered
            )]
        } ?? []
        let legacySamples: [WorkoutMetricSample]
        if metricSamples.isEmpty, let averageHeartRate {
            let provenance = MetricProvenance(source: .manual, sourceName: "手动平均心率", confidence: .estimated, coverage: 1)
            legacySamples = stride(from: 0.0, through: Double(minutes) * 60, by: 10).map {
                .init(timestamp: start.addingTimeInterval($0), heartRateBPM: averageHeartRate, provenance: provenance)
            }
        } else {
            legacySamples = metricSamples
        }
        return CardioEnergyEstimator.estimate(
            CardioEnergyInput(
                modality: modality,
                intensity: intensity,
                startedAt: start,
                completedAt: completedAt,
                weightKg: weightKg,
                profile: profile,
                confirmedDistanceKm: distanceKm,
                sensorDistanceKm: nil,
                workloadSegments: legacySegments,
                metricSamples: legacySamples,
                deviceEstimateKcal: measuredActiveEnergy,
                deviceEnergySource: measuredActiveEnergy == nil ? nil : .unknown,
                importedDeviceOnly: false
            )
        )
    }

    static func appleWatchActiveEnergy(from samples: [WorkoutMetricSample]) -> Double? {
        samples
            .filter { $0.provenance.source == .appleWatch }
            .compactMap(\.activeEnergyKcal)
            .filter { $0 > 0 }
            .max()
    }

    static func heartRateActiveEnergy(averageHeartRate: Double, minutes: Double, weightKg: Double, profile: UserProfile) -> Double? {
        guard let age = profile.ageYears,
              let sex = profile.biologicalSex, sex != .notSet,
              (60...210).contains(averageHeartRate), minutes > 0 else { return nil }
        let grossKJPerMinute: Double
        if sex == .male {
            grossKJPerMinute = -55.0969 + 0.6309 * averageHeartRate + 0.1988 * weightKg + 0.2017 * Double(age)
        } else {
            grossKJPerMinute = -20.4022 + 0.4472 * averageHeartRate - 0.1263 * weightKg + 0.074 * Double(age)
        }
        let grossKcal = max(0, grossKJPerMinute / 4.184) * minutes
        let restingDuringExercise = (restingEnergy(profile: profile, weightKg: weightKg) ?? 24 * weightKg) / 1440 * minutes
        return max(0, grossKcal - restingDuringExercise)
    }

    private struct TimeWeightedHeartRateEnergy {
        var kilocalories: Double
        var coverage: Double
    }

    static func hasUsableHeartRateSeries(
        _ samples: [WorkoutMetricSample],
        startedAt: Date,
        completedAt: Date
    ) -> Bool {
        let valid = validHeartRateSamples(
            samples,
            startedAt: startedAt,
            completedAt: completedAt
        )
        return zip(valid, valid.dropFirst()).contains { left, right in
            let interval = right.date.timeIntervalSince(left.date)
            return interval > 0 && interval <= 15
        }
    }

    private static func timeWeightedHeartRateEnergy(
        samples: [WorkoutMetricSample],
        startedAt: Date,
        completedAt: Date,
        weightKg: Double,
        profile: UserProfile,
        fallbackKcalPerMinute: Double,
        lowerRateFactor: Double,
        upperRateFactor: Double
    ) -> TimeWeightedHeartRateEnergy? {
        let totalSeconds = max(60, completedAt.timeIntervalSince(startedAt))
        let valid = validHeartRateSamples(
            samples,
            startedAt: startedAt,
            completedAt: completedAt
        )
        guard valid.count >= 2 else { return nil }
        guard heartRateActiveEnergy(
            averageHeartRate: valid[0].bpm,
            minutes: 1,
            weightKg: weightKg,
            profile: profile
        ) != nil else { return nil }

        var energy = 0.0
        var coveredSeconds = 0.0
        var cursor = startedAt
        for pair in zip(valid, valid.dropFirst()) {
            let left = pair.0
            let right = pair.1
            if left.date > cursor {
                energy += fallbackKcalPerMinute * left.date.timeIntervalSince(cursor) / 60
            }
            let interval = right.date.timeIntervalSince(left.date)
            if interval > 0, interval <= 15 {
                let bpm = (left.bpm + right.bpm) / 2
                let heartRateRate = heartRateActiveEnergy(
                    averageHeartRate: bpm,
                    minutes: 1,
                    weightKg: weightKg,
                    profile: profile
                ) ?? fallbackKcalPerMinute
                let boundedRate = min(
                    fallbackKcalPerMinute * upperRateFactor,
                    max(fallbackKcalPerMinute * lowerRateFactor, heartRateRate)
                )
                energy += boundedRate * interval / 60
                coveredSeconds += interval
            } else if interval > 0 {
                energy += fallbackKcalPerMinute * interval / 60
            }
            cursor = max(cursor, right.date)
        }
        if cursor < completedAt {
            energy += fallbackKcalPerMinute * completedAt.timeIntervalSince(cursor) / 60
        }
        guard coveredSeconds > 0 else { return nil }
        return TimeWeightedHeartRateEnergy(
            kilocalories: energy,
            coverage: min(1, coveredSeconds / totalSeconds)
        )
    }

    private static func validHeartRateSamples(
        _ samples: [WorkoutMetricSample],
        startedAt: Date,
        completedAt: Date
    ) -> [(date: Date, bpm: Double)] {
        samples
            .compactMap { sample -> (date: Date, bpm: Double)? in
                guard let bpm = sample.heartRateBPM,
                      (60...210).contains(bpm),
                      sample.timestamp >= startedAt,
                      sample.timestamp <= completedAt else { return nil }
                return (sample.timestamp, bpm)
            }
            .sorted { $0.date < $1.date }
    }

    private static func strengthFallbackEstimate(
        record: WorkoutRecord,
        weightKg: Double
    ) -> EnergyEstimate {
        let minutes = max(1, record.completedAt.timeIntervalSince(record.startedAt) / 60)
        let inferredRPE = record.sessionRPE ?? average(record.sets.compactMap { $0.feeling?.rpe })
        let met: Double
        if inferredRPE >= 9 { met = 6.0 }
        else if inferredRPE >= 7 { met = 5.0 }
        else if inferredRPE >= 5 { met = 3.5 }
        else { met = 3.0 }
        let value = netActiveEnergy(met: met, weightKg: weightKg, minutes: minutes)
        return EnergyEstimate(
            kilocalories: value,
            lowerBound: value * 0.65,
            upperBound: value * 1.35,
            method: "2024 Adult Compendium MET + session-RPE",
            confidence: "低至中"
        )
    }

    static func strengthEnergyEstimate(record: WorkoutRecord, weightKg: Double, profile: UserProfile? = nil) -> EnergyEstimate {
        if let measured = record.measuredActiveEnergyKcal, measured > 0 {
            return EnergyEstimate(kilocalories: measured, lowerBound: measured * 0.95, upperBound: measured * 1.05, method: "Apple Watch / 设备实测", confidence: "高")
        }
        let minutes = max(1, record.completedAt.timeIntervalSince(record.startedAt) / 60)
        let fallback = strengthFallbackEstimate(record: record, weightKg: weightKg)
        if let profile,
           let samples = record.metricSamples,
           let blended = timeWeightedHeartRateEnergy(
                samples: samples,
                startedAt: record.startedAt,
                completedAt: record.completedAt,
                weightKg: weightKg,
                profile: profile,
                fallbackKcalPerMinute: fallback.kilocalories / minutes,
                lowerRateFactor: 0.65,
                upperRateFactor: 1.35
           ) {
            let lowerFactor = 0.65 + 0.10 * blended.coverage
            let upperFactor = 1.35 - 0.10 * blended.coverage
            return EnergyEstimate(
                kilocalories: blended.kilocalories,
                lowerBound: blended.kilocalories * lowerFactor,
                upperBound: blended.kilocalories * upperFactor,
                method: "FitTune 心率 + 力量模型估算",
                confidence: blended.coverage >= 0.8 ? "中" : "低至中"
            )
        }
        return fallback
    }

    static func estimateStrengthActiveEnergy(record: WorkoutRecord, weightKg: Double, profile: UserProfile? = nil) -> Double {
        strengthEnergyEstimate(record: record, weightKg: weightKg, profile: profile).kilocalories
    }

    static func evaluateStrengthWorkout(_ record: WorkoutRecord) -> TrainingEffect {
        let sets = record.sets.filter { $0.resolvedSetKind == .working }
        let averageTechnique = average(sets.map { Double($0.techniqueQuality ?? record.sessionQuality ?? 3) })
        let nearFailure = sets.filter { $0.rir <= 1 || ($0.feeling?.rpe ?? 0) >= 9 }.count
        let durationMinutes = max(1, record.completedAt.timeIntervalSince(record.startedAt) / 60)
        let sessionRPE = record.sessionRPE ?? average(sets.compactMap { $0.feeling?.rpe })
        let trainingLoad = max(0, sessionRPE) * durationMinutes
        let effectiveSetLoad = sets.reduce(0.0) { partial, set in
            let proximity = max(0.25, min(1, (5 - Double(set.rir)) / 4))
            let technique = Double(set.techniqueQuality ?? 3) / 5
            return partial + proximity * technique
        }
        let meanRelativeIntensity = average(sets.compactMap { set -> Double? in
            guard let e1RM = estimatedOneRepMax(loadKg: set.loadKg, reps: set.reps, rir: set.rir), e1RM > 0 else { return nil }
            return set.loadKg / e1RM
        })
        let strength = min(100, Int((effectiveSetLoad * 7 + meanRelativeIntensity * 45).rounded()))
        let hypertrophy = min(100, Int((effectiveSetLoad * 10 + Double(nearFailure) * 3).rounded()))
        let fatigue = min(100, Int((trainingLoad / 8 + Double(nearFailure) * 8 + max(0, 4 - averageTechnique) * 6).rounded()))
        let lower: Int
        let upper: Int
        if fatigue >= 75 || nearFailure >= 5 { lower = 48; upper = 96 }
        else if fatigue >= 55 || nearFailure >= 3 { lower = 36; upper = 72 }
        else if fatigue >= 30 { lower = 24; upper = 48 }
        else { lower = 12; upper = 36 }
        let recovery = (lower + upper) / 2
        let regions = Set(sets.compactMap(\.movementPattern).flatMap { movementRegions(for: $0) })
        let regionText = BodyRegion.allCases.filter(regions.contains).map(\.title).joined(separator: "、")
        return TrainingEffect(
            strengthScore: strength,
            hypertrophyScore: hypertrophy,
            aerobicScore: 0,
            fatigueScore: fatigue,
            estimatedRecoveryHours: recovery,
            summary: "本次完成 \(sets.count) 个有效组，主要刺激\(regionText.isEmpty ? "目标肌群" : regionText)。",
            advice: upper >= 72
                ? "同部位高强度训练先预留 \(lower)–\(upper) 小时；用热身表现、酸痛和睡眠再次确认。"
                : "恢复窗口约 \(lower)–\(upper) 小时；这是训练负荷估计，不替代实际热身表现。",
            recoveryLowerHours: lower,
            recoveryUpperHours: upper,
            confidence: sets.count >= 4 && sets.allSatisfy({ $0.feeling != nil && $0.techniqueQuality != nil }) ? "中" : "低",
            trainingLoadAU: trainingLoad,
            method: "session-RPE × 时长 + RIR + 相对强度 + 动作质量"
        )
    }

    static func evaluateCardioWorkout(_ record: CardioWorkoutRecord) -> TrainingEffect {
        let defaultRPE: Double = record.intensity == .intervals ? 8.5 : (record.intensity == .zone2 ? 5.5 : 3.5)
        let rpe = record.sessionRPE ?? defaultRPE
        let trainingLoad = rpe * Double(record.durationMinutes)
        let aerobic = min(100, Int((trainingLoad / 4).rounded()))
        let fatigue = min(100, Int((trainingLoad / 6).rounded()))
        let lower = fatigue >= 75 ? 36 : (fatigue >= 45 ? 18 : 8)
        let upper = fatigue >= 75 ? 72 : (fatigue >= 45 ? 36 : 24)
        let recovery = (lower + upper) / 2
        return TrainingEffect(
            strengthScore: 0,
            hypertrophyScore: 0,
            aerobicScore: aerobic,
            fatigueScore: fatigue,
            estimatedRecoveryHours: recovery,
            summary: "\(record.modality.title) \(record.durationMinutes) 分钟，预计主动消耗 \(Int(record.activeEnergyKcal.rounded())) 千卡。",
            advice: record.intensity == .intervals
                ? "恢复窗口约 \(lower)–\(upper) 小时；结合腿部酸痛、静息心率和热身表现确认。"
                : "恢复窗口约 \(lower)–\(upper) 小时；可用轻松活动、补液与睡眠促进恢复。",
            recoveryLowerHours: lower,
            recoveryUpperHours: upper,
            confidence: record.sessionRPE != nil ? "中" : "低至中",
            trainingLoadAU: trainingLoad,
            method: "session-RPE × 时长"
        )
    }

    private static func rationale(for profile: UserProfile, sessionCount: Int) -> String {
        let split = displaySplit(profile.splitPreference ?? .automatic, days: profile.weeklyDays)
        let strengthGoal = effectiveStrengthGoal(for: profile)
        let cardioGoal = profile.cardioTrainingGoal ?? defaultCardioGoal(for: profile.goal)
        var text = "力量模块采用\(split.title)，以\(strengthGoal.title)为目标，共 \(sessionCount) 次；有氧模块以\(cardioGoal.title)独立安排。"
        if profile.secondaryGoal != .none {
            text += " 次目标为\(profile.secondaryGoal.title)，但不覆盖主目标。"
        }
        if profile.experience == .new || profile.experience == .returning || profile.experience == .autoAssess {
            text += " 前 2–3 次训练优先校准动作、工作重量、动作质量与 RIR。"
        }
        return text
    }

    private struct SessionTemplate {
        var name: String
        var focus: String
        var patterns: [MovementPattern]
    }

    private static func maxExerciseCount(for sessionMinutes: Int) -> Int {
        switch sessionMinutes {
        case ..<45: 5
        case 45..<70: 6
        default: 8
        }
    }

    private static func dailyTemplate(for focus: DailyTrainingFocus) -> SessionTemplate {
        switch focus {
        case .recommended:
            SessionTemplate(
                name: "自主全身",
                focus: "今天自行安排的全身训练",
                patterns: [.squat, .horizontalPush, .horizontalPull, .hinge, .verticalPull, .core]
            )
        case .chest:
            SessionTemplate(name: "胸部训练", focus: "胸部推举与孤立", patterns: [.horizontalPush, .chestIsolation, .arms, .core])
        case .back:
            SessionTemplate(name: "背部训练", focus: "垂直拉与水平拉", patterns: [.verticalPull, .horizontalPull, .hinge, .arms, .core])
        case .shoulders:
            SessionTemplate(name: "肩部训练", focus: "肩上推举与三角肌", patterns: [.verticalPush, .shoulderIsolation, .arms, .core])
        case .legs:
            SessionTemplate(name: "腿部训练", focus: "股四头、臀腿与小腿", patterns: [.squat, .hinge, .singleLeg, .kneeFlexion, .calves, .core])
        case .push:
            SessionTemplate(name: "推部训练", focus: "胸、肩与肱三头", patterns: [.horizontalPush, .verticalPush, .chestIsolation, .shoulderIsolation, .arms, .core])
        case .pull:
            SessionTemplate(name: "拉部训练", focus: "背部与肱二头", patterns: [.verticalPull, .horizontalPull, .hinge, .arms, .core])
        case .fullBody:
            SessionTemplate(name: "自主全身", focus: "覆盖主要动作模式", patterns: [.squat, .horizontalPush, .horizontalPull, .hinge, .verticalPush, .verticalPull, .core])
        }
    }

    private static func avoidanceDetail(base: String, avoidedRegions: Set<BodyRegion>) -> String {
        guard !avoidedRegions.isEmpty else { return base }
        let titles = BodyRegion.allCases.filter(avoidedRegions.contains).map(\.title).joined(separator: "、")
        return "\(base) · 今天避开\(titles)"
    }

    private static func displaySplit(_ preference: TrainingSplit, days: Int) -> TrainingSplit {
        guard preference == .automatic else { return preference }
        switch days {
        case ...3: return .fullBody
        case 4: return .upperLower
        default: return .pushPullLegs
        }
    }

    private static func splitTemplates(preference: TrainingSplit, days: Int) -> [SessionTemplate] {
        let chosen = displaySplit(preference, days: days)
        let fullBody = [
            SessionTemplate(name: "全身 A", focus: "蹲与水平推", patterns: [.squat, .horizontalPush, .horizontalPull, .hinge, .verticalPull, .core]),
            SessionTemplate(name: "全身 B", focus: "髋与垂直推", patterns: [.hinge, .verticalPush, .verticalPull, .singleLeg, .horizontalPush, .core]),
            SessionTemplate(name: "全身 C", focus: "单侧稳定与容量", patterns: [.singleLeg, .horizontalPull, .horizontalPush, .squat, .arms, .core])
        ]
        let upperLower = [
            SessionTemplate(name: "上肢 A", focus: "水平推拉", patterns: [.horizontalPush, .horizontalPull, .verticalPush, .verticalPull, .arms, .core]),
            SessionTemplate(name: "下肢 A", focus: "深蹲主导", patterns: [.squat, .hinge, .singleLeg, .kneeFlexion, .calves, .core]),
            SessionTemplate(name: "上肢 B", focus: "垂直推拉", patterns: [.verticalPush, .verticalPull, .horizontalPush, .horizontalPull, .shoulderIsolation, .arms]),
            SessionTemplate(name: "下肢 B", focus: "髋主导", patterns: [.hinge, .singleLeg, .squat, .kneeFlexion, .calves, .core])
        ]
        let pushPullLegs = [
            SessionTemplate(name: "推", focus: "胸、肩与肱三头", patterns: [.horizontalPush, .verticalPush, .chestIsolation, .shoulderIsolation, .arms, .core]),
            SessionTemplate(name: "拉", focus: "背部与肱二头", patterns: [.verticalPull, .horizontalPull, .hinge, .arms, .core]),
            SessionTemplate(name: "腿", focus: "股四头、臀腿与小腿", patterns: [.squat, .hinge, .singleLeg, .kneeFlexion, .calves, .core])
        ]
        let bodyPart = [
            SessionTemplate(name: "胸", focus: "水平推与胸部孤立", patterns: [.horizontalPush, .chestIsolation, .verticalPush, .arms, .core]),
            SessionTemplate(name: "背", focus: "垂直拉与水平拉", patterns: [.verticalPull, .horizontalPull, .hinge, .arms, .core]),
            SessionTemplate(name: "肩", focus: "垂直推与三角肌", patterns: [.verticalPush, .shoulderIsolation, .horizontalPush, .arms, .core]),
            SessionTemplate(name: "腿", focus: "蹲、髋与单腿", patterns: [.squat, .hinge, .singleLeg, .kneeFlexion, .calves, .core])
        ]

        let base: [SessionTemplate]
        let count: Int
        switch chosen {
        case .automatic, .fullBody:
            base = fullBody
            count = max(2, min(days, 6))
        case .upperLower:
            base = upperLower
            count = max(3, min(days, 6))
        case .pushPullLegs:
            base = pushPullLegs
            count = max(3, min(days, 6))
        case .chestBackShouldersLegs:
            base = bodyPart
            count = max(4, min(days, 6))
        }
        return (0..<count).map { base[$0 % base.count] }
    }

    private static func prescription(
        option: ExerciseOption,
        goal: StrengthTrainingGoal,
        experience: ExperienceLevel,
        priority: Bool
    ) -> ExercisePrescription {
        let sets = 4
        var lower = 6
        var upper = 10

        switch goal {
        case .maxStrength:
            if priority {
                lower = 3
                upper = 6
            } else {
                lower = 6
                upper = 10
            }
        case .hypertrophy:
            lower = priority ? 6 : 8
            upper = priority ? 10 : 15
        case .balanced:
            lower = 6
            upper = 12
        }

        return ExercisePrescription(
            name: option.name,
            pattern: option.pattern,
            sets: sets,
            repLower: lower,
            repUpper: upper,
            targetRIR: 0,
            isPriority: priority,
            suggestedLoadKg: nil,
            equipmentKind: option.equipment,
            workingSets: sets
        )
    }

    private static func effectiveStrengthGoal(for profile: UserProfile) -> StrengthTrainingGoal {
        if let selected = profile.strengthTrainingGoal { return selected }
        switch profile.goal {
        case .strength: return .maxStrength
        case .hypertrophy: return .hypertrophy
        default: return .balanced
        }
    }

    private static func defaultCardioGoal(for goal: TrainingGoal) -> CardioTrainingGoal {
        switch goal {
        case .fatLoss, .recomposition: return .fatLoss
        case .generalFitness: return .aerobicBase
        default: return .none
        }
    }

    private static func cardioSessions(for profile: UserProfile) -> [CardioSession] {
        let goal = profile.cardioTrainingGoal ?? defaultCardioGoal(for: profile.goal)
        let cautious = profile.experience == .new || profile.experience == .returning || profile.experience == .autoAssess
        switch goal {
        case .none:
            return []
        case .fatLoss:
            var sessions = [
                CardioSession(name: "稳态有氧 A", modality: "快走 / 单车 / 椭圆机", minutes: cautious ? 25 : 35, intensity: .zone2, guidance: "保持能说短句的强度；若与力量同日，先完成力量训练。"),
                CardioSession(name: "稳态有氧 B", modality: "任选低冲击器械", minutes: cautious ? 20 : 30, intensity: .zone2, guidance: "以可持续和周总量为主，不用每次都做高强度。")
            ]
            if !cautious && profile.weeklyDays >= 4 {
                sessions.append(CardioSession(name: "短间歇", modality: "单车 / 划船机", minutes: 18, intensity: .intervals, guidance: "热身后完成 6 轮 1 分钟偏难 + 2 分钟轻松；腿部疲劳明显时改为稳态。"))
            }
            return sessions
        case .aerobicBase:
            return [
                CardioSession(name: "基础耐力 A", modality: "快走 / 慢跑 / 单车", minutes: cautious ? 25 : 40, intensity: .zone2, guidance: "保持呼吸加快但仍能交流的强度。"),
                CardioSession(name: "基础耐力 B", modality: "任选舒适模式", minutes: cautious ? 25 : 45, intensity: .zone2, guidance: "逐周优先增加 5 分钟，而不是突然提高强度。")
            ]
        case .performance:
            return [
                CardioSession(name: "有氧基础", modality: "跑步 / 单车 / 划船", minutes: 40, intensity: .zone2, guidance: "轻中等强度累积基础，不追求力竭。"),
                CardioSession(name: "心肺间歇", modality: "单车 / 划船机优先", minutes: 24, intensity: .intervals, guidance: "热身后 4 轮 3 分钟偏难 + 3 分钟轻松；爆发力优先时尽量与力量训练分开。")
            ]
        }
    }

    private static func preferredExercise(
        for pattern: MovementPattern,
        equipment: EquipmentProfile,
        favoriteExerciseIDs: Set<String> = [],
        customExercises: [ExerciseOption] = []
    ) -> ExerciseOption {
        let allowedEquipment: Set<EquipmentKind>
        switch equipment {
        case .fullGym:
            allowedEquipment = Set(EquipmentKind.allCases)
        case .dumbbells:
            allowedEquipment = [.dumbbell, .bodyweight, .resistanceBand, .bodyweightBand]
        case .bodyweightBands:
            allowedEquipment = [.bodyweight, .resistanceBand, .bodyweightBand]
        }
        let options = (exerciseAlternatives(for: pattern) + customExercises.filter { $0.pattern == pattern })
            .filter { allowedEquipment.contains($0.equipment) }
        if let favorite = options.first(where: { favoriteExerciseIDs.contains($0.id) }) {
            return favorite
        }
        let order: [EquipmentKind]
        switch equipment {
        case .fullGym: order = [.barbell, .smithMachine, .plateLoadedMachine, .selectorizedMachine, .butterflyMachine, .cable, .landmine, .dumbbell, .kettlebell, .romanChair, .bodyweight, .resistanceBand, .machineCable, .bodyweightBand]
        case .dumbbells: order = [.dumbbell, .kettlebell, .bodyweight, .resistanceBand, .bodyweightBand, .cable, .selectorizedMachine, .machineCable, .smithMachine, .barbell, .landmine, .plateLoadedMachine, .butterflyMachine, .romanChair]
        case .bodyweightBands: order = [.bodyweight, .resistanceBand, .bodyweightBand, .dumbbell, .kettlebell, .cable, .selectorizedMachine, .machineCable, .smithMachine, .barbell, .landmine, .plateLoadedMachine, .butterflyMachine, .romanChair]
        }
        for kind in order {
            if let option = options.first(where: { $0.equipment == kind }) { return option }
        }
        return options.first ?? ExerciseOption(name: "自选动作", pattern: pattern, equipment: .bodyweight)
    }

    static let legacyExerciseLibrary: [ExerciseOption] = [
        ExerciseOption(name: "杠铃深蹲", pattern: .squat, equipment: .barbell),
        ExerciseOption(name: "高脚杯深蹲", pattern: .squat, equipment: .dumbbell),
        ExerciseOption(name: "腿举机", pattern: .squat, equipment: .machineCable),
        ExerciseOption(name: "自重深蹲", pattern: .squat, equipment: .bodyweightBand),
        ExerciseOption(name: "罗马尼亚硬拉", pattern: .hinge, equipment: .barbell),
        ExerciseOption(name: "哑铃罗马尼亚硬拉", pattern: .hinge, equipment: .dumbbell),
        ExerciseOption(name: "绳索髋拉", pattern: .hinge, equipment: .machineCable),
        ExerciseOption(name: "单腿臀桥", pattern: .hinge, equipment: .bodyweightBand),
        ExerciseOption(name: "杠铃卧推", pattern: .horizontalPush, equipment: .barbell),
        ExerciseOption(name: "哑铃卧推", pattern: .horizontalPush, equipment: .dumbbell),
        ExerciseOption(name: "坐姿推胸机", pattern: .horizontalPush, equipment: .machineCable),
        ExerciseOption(name: "俯卧撑", pattern: .horizontalPush, equipment: .bodyweightBand),
        ExerciseOption(name: "杠铃划船", pattern: .horizontalPull, equipment: .barbell),
        ExerciseOption(name: "单臂哑铃划船", pattern: .horizontalPull, equipment: .dumbbell),
        ExerciseOption(name: "坐姿绳索划船", pattern: .horizontalPull, equipment: .machineCable),
        ExerciseOption(name: "弹力带划船", pattern: .horizontalPull, equipment: .bodyweightBand),
        ExerciseOption(name: "杠铃推举", pattern: .verticalPush, equipment: .barbell),
        ExerciseOption(name: "坐姿哑铃推举", pattern: .verticalPush, equipment: .dumbbell),
        ExerciseOption(name: "器械推肩", pattern: .verticalPush, equipment: .machineCable),
        ExerciseOption(name: "派克俯卧撑", pattern: .verticalPush, equipment: .bodyweightBand),
        ExerciseOption(name: "引体向上", pattern: .verticalPull, equipment: .barbell),
        ExerciseOption(name: "哑铃上拉", pattern: .verticalPull, equipment: .dumbbell),
        ExerciseOption(name: "高位下拉", pattern: .verticalPull, equipment: .machineCable),
        ExerciseOption(name: "弹力带下拉", pattern: .verticalPull, equipment: .bodyweightBand),
        ExerciseOption(name: "杠铃保加利亚分腿蹲", pattern: .singleLeg, equipment: .barbell),
        ExerciseOption(name: "哑铃反向箭步蹲", pattern: .singleLeg, equipment: .dumbbell),
        ExerciseOption(name: "史密斯分腿蹲", pattern: .singleLeg, equipment: .smithMachine),
        ExerciseOption(name: "反向箭步蹲", pattern: .singleLeg, equipment: .bodyweightBand),
        ExerciseOption(name: "杠铃弯举 + 窄距卧推", pattern: .arms, equipment: .barbell),
        ExerciseOption(name: "哑铃弯举 + 臂屈伸", pattern: .arms, equipment: .dumbbell),
        ExerciseOption(name: "绳索弯举 + 下压", pattern: .arms, equipment: .machineCable),
        ExerciseOption(name: "弹力带手臂组合", pattern: .arms, equipment: .bodyweightBand),
        ExerciseOption(name: "杠铃健腹轮", pattern: .core, equipment: .barbell),
        ExerciseOption(name: "负重死虫", pattern: .core, equipment: .dumbbell),
        ExerciseOption(name: "绳索卷腹", pattern: .core, equipment: .machineCable),
        ExerciseOption(name: "死虫", pattern: .core, equipment: .bodyweightBand),
        ExerciseOption(name: "哑铃飞鸟", pattern: .chestIsolation, equipment: .dumbbell),
        ExerciseOption(name: "蝴蝶机夹胸", pattern: .chestIsolation, equipment: .machineCable),
        ExerciseOption(name: "弹力带夹胸", pattern: .chestIsolation, equipment: .bodyweightBand),
        ExerciseOption(name: "哑铃侧平举", pattern: .shoulderIsolation, equipment: .dumbbell),
        ExerciseOption(name: "绳索侧平举", pattern: .shoulderIsolation, equipment: .machineCable),
        ExerciseOption(name: "弹力带侧平举", pattern: .shoulderIsolation, equipment: .bodyweightBand),
        ExerciseOption(name: "哑铃滑垫腿弯举", pattern: .kneeFlexion, equipment: .dumbbell),
        ExerciseOption(name: "坐姿腿弯举", pattern: .kneeFlexion, equipment: .machineCable),
        ExerciseOption(name: "北欧腿弯举", pattern: .kneeFlexion, equipment: .bodyweightBand),
        ExerciseOption(name: "杠铃提踵", pattern: .calves, equipment: .barbell),
        ExerciseOption(name: "哑铃提踵", pattern: .calves, equipment: .dumbbell),
        ExerciseOption(name: "坐姿提踵机", pattern: .calves, equipment: .machineCable),
        ExerciseOption(name: "单腿提踵", pattern: .calves, equipment: .bodyweightBand),

        // 扩展库：同一动作模式内替换，兼顾自由重量、器械和居家条件。
        ExerciseOption(name: "颈前深蹲", pattern: .squat, equipment: .barbell, category: .quadriceps, subcategory: .squat, aliases: ["前蹲"]),
        ExerciseOption(name: "哑铃前蹲", pattern: .squat, equipment: .dumbbell),
        ExerciseOption(name: "哈克深蹲", pattern: .squat, equipment: .machineCable),
        ExerciseOption(name: "西西深蹲", pattern: .squat, equipment: .bodyweightBand),
        ExerciseOption(name: "传统硬拉", pattern: .hinge, equipment: .barbell),
        ExerciseOption(name: "杠铃臀推", pattern: .hinge, equipment: .barbell),
        ExerciseOption(name: "哑铃臀推", pattern: .hinge, equipment: .dumbbell),
        ExerciseOption(name: "臀推机", pattern: .hinge, equipment: .machineCable),
        ExerciseOption(name: "弹力带臀推", pattern: .hinge, equipment: .bodyweightBand),
        ExerciseOption(name: "上斜杠铃卧推", pattern: .horizontalPush, equipment: .barbell),
        ExerciseOption(name: "上斜哑铃卧推", pattern: .horizontalPush, equipment: .dumbbell),
        ExerciseOption(name: "史密斯卧推", pattern: .horizontalPush, equipment: .smithMachine),
        ExerciseOption(name: "双杠臂屈伸", pattern: .horizontalPush, equipment: .bodyweightBand),
        ExerciseOption(name: "胸托杠铃划船", pattern: .horizontalPull, equipment: .barbell),
        ExerciseOption(name: "胸托哑铃划船", pattern: .horizontalPull, equipment: .dumbbell),
        ExerciseOption(name: "T 杠划船机", pattern: .horizontalPull, equipment: .machineCable),
        ExerciseOption(name: "反向划船", pattern: .horizontalPull, equipment: .bodyweightBand),
        ExerciseOption(name: "地雷管推举", pattern: .verticalPush, equipment: .barbell),
        ExerciseOption(name: "阿诺德推举", pattern: .verticalPush, equipment: .dumbbell),
        ExerciseOption(name: "单臂绳索推举", pattern: .verticalPush, equipment: .machineCable),
        ExerciseOption(name: "靠墙倒立撑进阶", pattern: .verticalPush, equipment: .bodyweightBand),
        ExerciseOption(name: "反握引体向上", pattern: .verticalPull, equipment: .barbell),
        ExerciseOption(name: "双哑铃上拉", pattern: .verticalPull, equipment: .dumbbell),
        ExerciseOption(name: "单臂高位下拉", pattern: .verticalPull, equipment: .machineCable),
        ExerciseOption(name: "辅助引体向上", pattern: .verticalPull, equipment: .bodyweightBand),
        ExerciseOption(name: "杠铃箭步蹲", pattern: .singleLeg, equipment: .barbell),
        ExerciseOption(name: "哑铃台阶蹲", pattern: .singleLeg, equipment: .dumbbell),
        ExerciseOption(name: "单腿腿举", pattern: .singleLeg, equipment: .machineCable),
        ExerciseOption(name: "保加利亚分腿蹲", pattern: .singleLeg, equipment: .bodyweightBand),
        ExerciseOption(name: "杠铃弯举", pattern: .arms, equipment: .barbell),
        ExerciseOption(name: "锤式弯举 + 过顶臂屈伸", pattern: .arms, equipment: .dumbbell),
        ExerciseOption(name: "牧师凳弯举 + 绳索下压", pattern: .arms, equipment: .machineCable),
        ExerciseOption(name: "窄距俯卧撑", pattern: .arms, equipment: .bodyweightBand),
        ExerciseOption(name: "杠铃片农夫走", pattern: .core, equipment: .barbell),
        ExerciseOption(name: "哑铃农夫走", pattern: .core, equipment: .dumbbell),
        ExerciseOption(name: "绳索抗旋转推", pattern: .core, equipment: .machineCable),
        ExerciseOption(name: "侧桥", pattern: .core, equipment: .bodyweightBand),
        ExerciseOption(name: "上斜哑铃飞鸟", pattern: .chestIsolation, equipment: .dumbbell),
        ExerciseOption(name: "绳索夹胸", pattern: .chestIsolation, equipment: .machineCable),
        ExerciseOption(name: "滑盘夹胸俯卧撑", pattern: .chestIsolation, equipment: .bodyweightBand),
        ExerciseOption(name: "哑铃反向飞鸟", pattern: .shoulderIsolation, equipment: .dumbbell),
        ExerciseOption(name: "反向蝴蝶机", pattern: .shoulderIsolation, equipment: .machineCable),
        ExerciseOption(name: "弹力带面拉", pattern: .shoulderIsolation, equipment: .bodyweightBand),
        ExerciseOption(name: "哑铃单腿罗马尼亚硬拉", pattern: .kneeFlexion, equipment: .dumbbell),
        ExerciseOption(name: "俯卧腿弯举", pattern: .kneeFlexion, equipment: .machineCable),
        ExerciseOption(name: "滑垫腿弯举", pattern: .kneeFlexion, equipment: .bodyweightBand),
        ExerciseOption(name: "站姿提踵机", pattern: .calves, equipment: .machineCable),
        ExerciseOption(name: "台阶单腿提踵", pattern: .calves, equipment: .bodyweightBand),

        // v0.5：按肌群与具体器械细分，避免把史密斯、固定器械和绳索混在一起。
        ExerciseOption(name: "下斜杠铃卧推", pattern: .horizontalPush, equipment: .barbell, category: .chest),
        ExerciseOption(name: "窄握杠铃卧推", pattern: .horizontalPush, equipment: .barbell, category: .chest),
        ExerciseOption(name: "哑铃挤压卧推", pattern: .horizontalPush, equipment: .dumbbell, category: .chest),
        ExerciseOption(name: "哑铃地板卧推", pattern: .horizontalPush, equipment: .dumbbell, category: .chest),
        ExerciseOption(name: "上斜史密斯卧推", pattern: .horizontalPush, equipment: .smithMachine, category: .chest),
        ExerciseOption(name: "下斜史密斯卧推", pattern: .horizontalPush, equipment: .smithMachine, category: .chest),
        ExerciseOption(name: "水平推胸机", pattern: .horizontalPush, equipment: .selectorizedMachine, category: .chest),
        ExerciseOption(name: "上斜推胸机", pattern: .horizontalPush, equipment: .selectorizedMachine, category: .chest),
        ExerciseOption(name: "蝴蝶机夹胸（肘垫）", pattern: .chestIsolation, equipment: .selectorizedMachine, category: .chest),
        ExerciseOption(name: "站姿绳索夹胸", pattern: .chestIsolation, equipment: .cable, category: .chest),
        ExerciseOption(name: "低位至高位绳索夹胸", pattern: .chestIsolation, equipment: .cable, category: .chest),
        ExerciseOption(name: "高位至低位绳索夹胸", pattern: .chestIsolation, equipment: .cable, category: .chest),

        ExerciseOption(name: "站姿杠铃推举", pattern: .verticalPush, equipment: .barbell, category: .shoulders),
        ExerciseOption(name: "坐姿杠铃推举", pattern: .verticalPush, equipment: .barbell, category: .shoulders),
        ExerciseOption(name: "单臂哑铃推举", pattern: .verticalPush, equipment: .dumbbell, category: .shoulders),
        ExerciseOption(name: "哑铃俯身反向飞鸟", pattern: .shoulderIsolation, equipment: .dumbbell, category: .shoulders),
        ExerciseOption(name: "史密斯坐姿推肩", pattern: .verticalPush, equipment: .smithMachine, category: .shoulders),
        ExerciseOption(name: "固定器械推肩", pattern: .verticalPush, equipment: .selectorizedMachine, category: .shoulders),
        ExerciseOption(name: "固定器械侧平举", pattern: .shoulderIsolation, equipment: .selectorizedMachine, category: .shoulders),
        ExerciseOption(name: "反向蝴蝶机（后束）", pattern: .shoulderIsolation, equipment: .selectorizedMachine, category: .shoulders),
        ExerciseOption(name: "单臂绳索侧平举", pattern: .shoulderIsolation, equipment: .cable, category: .shoulders),
        ExerciseOption(name: "绳索面拉", pattern: .shoulderIsolation, equipment: .cable, category: .shoulders),
        ExerciseOption(name: "绳索反向飞鸟", pattern: .shoulderIsolation, equipment: .cable, category: .shoulders),

        ExerciseOption(name: "彭德雷划船", pattern: .horizontalPull, equipment: .barbell, category: .back),
        ExerciseOption(name: "海豹划船", pattern: .horizontalPull, equipment: .barbell, category: .back),
        ExerciseOption(name: "双臂哑铃划船", pattern: .horizontalPull, equipment: .dumbbell, category: .back),
        ExerciseOption(name: "史密斯俯身划船", pattern: .horizontalPull, equipment: .smithMachine, category: .back),
        ExerciseOption(name: "胸托划船机", pattern: .horizontalPull, equipment: .selectorizedMachine, category: .back),
        ExerciseOption(name: "对握高位下拉", pattern: .verticalPull, equipment: .cable, category: .back, subcategory: .verticalPull, aliases: ["中立握高位下拉"]),
        ExerciseOption(name: "宽握高位下拉", pattern: .verticalPull, equipment: .cable, category: .back),
        ExerciseOption(name: "直臂下压", pattern: .verticalPull, equipment: .cable, category: .back),
        ExerciseOption(name: "单臂绳索划船", pattern: .horizontalPull, equipment: .cable, category: .back),

        ExerciseOption(name: "暂停深蹲", pattern: .squat, equipment: .barbell, category: .quadriceps),
        ExerciseOption(name: "史密斯深蹲", pattern: .squat, equipment: .smithMachine, category: .quadriceps),
        ExerciseOption(name: "史密斯哈克深蹲", pattern: .squat, equipment: .smithMachine, category: .quadriceps),
        ExerciseOption(name: "腿屈伸机", pattern: .squat, equipment: .selectorizedMachine, category: .quadriceps),
        ExerciseOption(name: "钟摆深蹲机", pattern: .squat, equipment: .selectorizedMachine, category: .quadriceps),
        ExerciseOption(name: "相扑硬拉", pattern: .hinge, equipment: .barbell, category: .posteriorChain),
        ExerciseOption(name: "早安式", pattern: .hinge, equipment: .barbell, category: .posteriorChain),
        ExerciseOption(name: "史密斯罗马尼亚硬拉", pattern: .hinge, equipment: .smithMachine, category: .posteriorChain),
        ExerciseOption(name: "史密斯臀推", pattern: .hinge, equipment: .smithMachine, category: .posteriorChain),
        ExerciseOption(name: "卧式腿弯举机", pattern: .kneeFlexion, equipment: .selectorizedMachine, category: .posteriorChain),
        ExerciseOption(name: "站姿单腿弯举机", pattern: .kneeFlexion, equipment: .selectorizedMachine, category: .posteriorChain),
        ExerciseOption(name: "绳索直腿硬拉", pattern: .hinge, equipment: .cable, category: .posteriorChain),

        ExerciseOption(name: "EZ 杠弯举", pattern: .arms, equipment: .barbell, category: .arms),
        ExerciseOption(name: "上斜哑铃弯举", pattern: .arms, equipment: .dumbbell, category: .arms),
        ExerciseOption(name: "绳索过顶臂屈伸", pattern: .arms, equipment: .cable, category: .arms),
        ExerciseOption(name: "单臂绳索下压", pattern: .arms, equipment: .cable, category: .arms),
        ExerciseOption(name: "牧师凳弯举机", pattern: .arms, equipment: .selectorizedMachine, category: .arms),
        // v1.0：按动作模式、器械与子分类补齐用户指定动作。
        ExerciseOption(name: "哑铃前平举", pattern: .shoulderIsolation, equipment: .dumbbell, category: .shoulders, subcategory: .shoulderFront),
        ExerciseOption(name: "哑铃弯举", pattern: .arms, equipment: .dumbbell, category: .arms, subcategory: .biceps),
        ExerciseOption(name: "哑铃锤式弯举", pattern: .arms, equipment: .dumbbell, category: .arms, subcategory: .brachialis, aliases: ["锤式弯举"]),
        ExerciseOption(name: "负重引体向上", pattern: .verticalPull, equipment: .bodyweightBand, category: .back, subcategory: .verticalPull),
        ExerciseOption(name: "窄握高位下拉", pattern: .verticalPull, equipment: .cable, category: .back, subcategory: .verticalPull),
        ExerciseOption(name: "反手高位下拉", pattern: .verticalPull, equipment: .cable, category: .back, subcategory: .verticalPull),
        ExerciseOption(name: "泽奇深蹲", pattern: .squat, equipment: .barbell, category: .quadriceps, subcategory: .squat)
    ]

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
