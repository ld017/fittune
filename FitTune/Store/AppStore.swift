import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    var profile: UserProfile?
    var plan: TrainingPlan?
    var readiness = ReadinessInput()
    var workoutHistory: [WorkoutRecord] = []
    var weightHistory: [WeightEntry] = []
    var cardioHistory: [CardioMetricEntry] = []
    var recoveryHistory: [RecoveryEntry] = []
    var cardioWorkouts: [CardioWorkoutRecord] = []
    var dailyActiveEnergy: [DailyActiveEnergyEntry] = []
    var dailySteps: [DailyStepEntry] = []
    var bodyCompositionHistory: [BodyCompositionEntry] = []
    var deletedWorkoutHistory: [WorkoutRecord] = []
    var deletedCardioWorkouts: [CardioWorkoutRecord] = []
    var deletedWeightHistory: [WeightEntry] = []
    var deletedCardioHistory: [CardioMetricEntry] = []
    var deletedRecoveryHistory: [RecoveryEntry] = []
    var deletedBodyCompositionHistory: [BodyCompositionEntry] = []
    var dailyTrainingChoice: DailyTrainingChoice?
    var activeWorkoutDraft: WorkoutDraft?
    var recoveryCheckIns: [RecoveryCheckIn] = []
    var safetySettings = PersonalSafetySettings()
    var favoriteExerciseIDs: Set<String> = []
    var customExercises: [ExerciseOption] = []

    private let defaults: UserDefaults
    private let storageKey = "FitTune.snapshot.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    var readinessAssessment: ReadinessAssessment {
        TrainingEngine.assessReadiness(readiness)
    }

    var latestWeight: Double? {
        bodyCompositionHistory.sorted { $0.date > $1.date }.first?.weightKg
            ?? weightHistory.sorted { $0.date > $1.date }.first?.kilograms
            ?? profile?.bodyWeightKg
    }

    var nextSession: TrainingSession? {
        guard let session = scheduledSession else { return nil }
        return adaptedSession(session)
    }

    var todayChoice: DailyTrainingChoice {
        guard let dailyTrainingChoice,
              Calendar.current.isDate(dailyTrainingChoice.date, inSameDayAs: .now) else {
            return DailyTrainingChoice()
        }
        return dailyTrainingChoice
    }

    var todaySession: TrainingSession? {
        guard let profile, todayChoice.intent == .train else { return nil }
        guard let session = TrainingEngine.makeTodaySession(
            focus: todayChoice.focus,
            profile: profile,
            recommendedSession: scheduledSession,
            avoiding: todayChoice.avoidedRegions
        ) else { return nil }
        return adaptedSession(session)
    }

    var cardioPlan: [CardioSession] { plan?.cardioSessions ?? [] }

    var totalCompletedSets: Int {
        workoutHistory.reduce(0) { $0 + $1.sets.count }
    }

    var partialWorkoutCount: Int {
        workoutHistory.filter { $0.resolvedCompletionStatus == .partial }.count
    }

    var todayEnergySummary: DailyEnergySummary {
        let calendar = Calendar.current
        let weight = latestWeight ?? profile?.bodyWeightKg ?? 70
        let strength = workoutHistory.filter { calendar.isDateInToday($0.completedAt) }
            .reduce(0.0) { $0 + ($1.activeEnergyKcal ?? TrainingEngine.estimateStrengthActiveEnergy(record: $1, weightKg: weight, profile: profile)) }
        let cardio = cardioWorkouts.filter { calendar.isDateInToday($0.date) }
            .reduce(0.0) { $0 + $1.activeEnergyKcal }
        let wearable = dailyActiveEnergy.filter { calendar.isDateInToday($0.date) }.map(\.kilocalories).max() ?? 0
        let stepEntry = dailySteps.filter { calendar.isDateInToday($0.date) }.max { $0.steps < $1.steps }
        let stepEstimate = stepEntry?.estimatedActiveEnergyKcal ?? 0
        let residualWearable = max(0, wearable - strength - cardio)
        let walking = wearable > 0 ? min(stepEstimate, residualWearable) : stepEstimate
        let other = wearable > 0 ? max(0, residualWearable - walking) : 0
        return DailyEnergySummary(
            restingKcal: profile.flatMap { TrainingEngine.restingEnergy(profile: $0, weightKg: weight) },
            strengthKcal: strength,
            cardioKcal: cardio,
            walkingStepsKcal: walking,
            steps: stepEntry?.steps ?? 0,
            otherWearableKcal: other
        )
    }

    func finishOnboarding(with newProfile: UserProfile) {
        profile = newProfile
        plan = TrainingEngine.generatePlan(for: newProfile, favoriteExerciseIDs: favoriteExerciseIDs, customExercises: customExercises)
        readiness = ReadinessInput()
        if newProfile.bodyWeightKg > 0 {
            weightHistory = [WeightEntry(date: .now, kilograms: newProfile.bodyWeightKg, source: "手动")]
        }
        persist()
    }

    func updateReadiness(_ input: ReadinessInput) {
        readiness = input
        let assessment = TrainingEngine.assessReadiness(input)
        let entry = RecoveryEntry(
            date: input.date,
            sleepHours: input.sleepHours,
            sleepQuality: input.sleepQuality ?? 3,
            soreness: input.soreness,
            stress: input.stress,
            motivation: input.motivation,
            readinessScore: assessment.score
        )
        if let index = recoveryHistory.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: input.date) }) {
            recoveryHistory[index] = entry
        } else {
            recoveryHistory.append(entry)
        }
        recoveryHistory.sort { $0.date < $1.date }
        persist()
    }

    func updateRecoveryCheckIn(_ checkIn: RecoveryCheckIn) {
        if let index = recoveryCheckIns.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: checkIn.date) }) {
            recoveryCheckIns[index] = checkIn
        } else {
            recoveryCheckIns.append(checkIn)
        }
        recoveryCheckIns.sort { $0.date < $1.date }
        persist()
    }

    func updateSafetySettings(_ settings: PersonalSafetySettings) {
        safetySettings = settings
        persist()
    }

    func appendSummaryRevision(_ revision: SummaryRevision, toWorkoutID workoutID: UUID) {
        guard let index = workoutHistory.firstIndex(where: { $0.id == workoutID }) else { return }
        var revisions = workoutHistory[index].summaryRevisions ?? []
        guard !revisions.contains(where: { $0.id == revision.id }) else { return }
        revisions.append(revision)
        workoutHistory[index].summaryRevisions = revisions
        workoutHistory[index].summary = revision.summary
        persist()
    }

    func updateProfileAndRegenerate(_ updated: UserProfile) {
        profile = updated
        plan = TrainingEngine.generatePlan(for: updated, favoriteExerciseIDs: favoriteExerciseIDs, customExercises: customExercises)
        persist()
    }

    func toggleFavoriteExercise(_ exerciseID: String) {
        if favoriteExerciseIDs.contains(exerciseID) {
            favoriteExerciseIDs.remove(exerciseID)
        } else {
            favoriteExerciseIDs.insert(exerciseID)
        }
        persist()
    }

    func saveCustomExercise(_ exercise: ExerciseOption) {
        var custom = exercise
        custom.source = .custom
        if custom.stableID == nil {
            custom.stableID = "custom.\(UUID().uuidString.lowercased())"
        }
        if let index = customExercises.firstIndex(where: { $0.id == custom.id }) {
            customExercises[index] = custom
        } else {
            customExercises.append(custom)
        }
        persist()
    }

    func deleteCustomExercise(id: String) {
        customExercises.removeAll { $0.id == id }
        favoriteExerciseIDs.remove(id)
        persist()
    }

    func setTodayIntent(_ intent: TodayTrainingIntent) {
        var choice = todayChoice
        choice.date = .now
        choice.intent = intent
        dailyTrainingChoice = choice
        persist()
    }

    func setTodayFocus(_ focus: DailyTrainingFocus) {
        var choice = todayChoice
        choice.date = .now
        choice.intent = .train
        choice.focus = focus
        dailyTrainingChoice = choice
        persist()
    }

    func toggleAvoidedRegion(_ region: BodyRegion) {
        var choice = todayChoice
        choice.date = .now
        choice.intent = .train
        if choice.avoidedRegions.contains(region) {
            choice.avoidedRegions.remove(region)
        } else {
            choice.avoidedRegions.insert(region)
            if choice.focus.primaryRegion == region {
                choice.focus = .recommended
            }
        }
        dailyTrainingChoice = choice
        persist()
    }

    func addWeight(_ kilograms: Double, source: String = "手动") {
        guard kilograms > 20, kilograms < 400 else { return }
        weightHistory.append(WeightEntry(date: .now, kilograms: kilograms, source: source))
        weightHistory.sort { $0.date < $1.date }
        if var current = profile {
            current.bodyWeightKg = kilograms
            profile = current
        }
        persist()
    }

    func addBodyComposition(weightKg: Double, bodyFatPercent: Double?, leanMassKg: Double?, waistCm: Double?, source: String = "手动") {
        guard (20...400).contains(weightKg) else { return }
        let bodyFat = bodyFatPercent.flatMap { (3...65).contains($0) ? $0 : nil }
        let lean = leanMassKg.flatMap { (15...weightKg).contains($0) ? $0 : nil }
        bodyCompositionHistory.append(BodyCompositionEntry(date: .now, weightKg: weightKg, bodyFatPercent: bodyFat, leanMassKg: lean, waistCm: waistCm, source: source))
        bodyCompositionHistory.sort { $0.date < $1.date }
        addWeight(weightKg, source: source)
        if var current = profile {
            current.bodyFatPercent = bodyFat
            current.leanMassKg = lean
            profile = current
        }
        persist()
    }

    func addCardioMetric(type: CardioMetricType, value: Double, source: String = "手动") {
        guard value > 0 else { return }
        cardioHistory.append(CardioMetricEntry(date: .now, type: type, value: value, source: source))
        cardioHistory.sort { $0.date < $1.date }
        persist()
    }

    func addCardioWorkout(_ record: CardioWorkoutRecord) {
        if let externalID = record.externalID,
           cardioWorkouts.contains(where: { $0.externalID == externalID }) { return }
        if record.source.contains("Apple"),
           let index = cardioWorkouts.firstIndex(where: { existing in
               existing.externalID == nil
                   && existing.modality == record.modality
                   && Calendar.current.isDate(existing.date, inSameDayAs: record.date)
                   && abs(existing.durationMinutes - record.durationMinutes) <= 5
                   && abs(existing.date.timeIntervalSince(record.date)) <= 4 * 3600
           }) {
            var updated = record
            updated.id = cardioWorkouts[index].id
            cardioWorkouts[index] = updated
            persist()
            return
        }
        cardioWorkouts.insert(record, at: 0)
        persist()
    }

    func mergeWearableStrengthWorkout(_ wearable: WearableStrengthWorkout) {
        if workoutHistory.contains(where: { $0.externalID == wearable.externalID }) { return }
        guard let index = workoutHistory.firstIndex(where: { record in
            let duration = Int(record.completedAt.timeIntervalSince(record.startedAt) / 60)
            return Calendar.current.isDate(record.startedAt, inSameDayAs: wearable.date)
                && abs(record.startedAt.timeIntervalSince(wearable.date)) <= 4 * 3600
                && abs(duration - wearable.durationMinutes) <= 30
        }) else { return }
        var updated = workoutHistory[index]
        updated.externalID = wearable.externalID
        if let heartRate = wearable.averageHeartRate { updated.averageHeartRate = heartRate }
        if let energy = wearable.activeEnergyKcal, energy > 0 {
            updated.measuredActiveEnergyKcal = energy
            updated.activeEnergyKcal = energy
            updated.energyMethod = "Apple Watch / 设备实测（同步更新）"
            updated.energyLowerBoundKcal = energy * 0.95
            updated.energyUpperBoundKcal = energy * 1.05
        }
        updated.effect = TrainingEngine.evaluateStrengthWorkout(updated)
        workoutHistory[index] = updated
        persist()
    }

    func importWearableActiveEnergy(_ kilocalories: Double, date: Date = .now, source: String = "Apple Watch") {
        guard kilocalories > 0 else { return }
        if let index = dailyActiveEnergy.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            dailyActiveEnergy[index] = DailyActiveEnergyEntry(date: date, kilocalories: kilocalories, source: source)
        } else {
            dailyActiveEnergy.append(DailyActiveEnergyEntry(date: date, kilocalories: kilocalories, source: source))
        }
        persist()
    }

    func importDailySteps(steps: Int, distanceKm: Double?, weightKg: Double, date: Date = .now, source: String = "Apple Health") {
        guard steps >= 0 else { return }
        let distance = distanceKm.flatMap { $0 > 0 ? $0 : nil }
        // Net walking cost at level grade is approximately 0.5 kcal/kg/km.
        let estimate = distance.map { 0.5 * weightKg * $0 } ?? Double(steps) * 0.0004 * weightKg
        let entry = DailyStepEntry(date: date, steps: steps, distanceKm: distance, estimatedActiveEnergyKcal: max(0, estimate), source: source)
        if let index = dailySteps.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            dailySteps[index] = entry
        } else {
            dailySteps.append(entry)
        }
        persist()
    }

    func lastWorkoutRecord(for exercise: ExercisePrescription) -> WorkoutRecord? {
        workoutHistory.sorted { $0.completedAt > $1.completedAt }.first { record in
            record.sets.contains { $0.exerciseName == exercise.name || $0.movementPattern == exercise.pattern }
        }
    }

    func loadRecommendation(for exercise: ExercisePrescription) -> StartingLoadRecommendation {
        TrainingEngine.recommendStartingLoad(
            prescription: exercise,
            history: workoutHistory,
            readiness: readinessAssessment,
            increment: profile?.loadIncrementKg ?? 2.5
        )
    }

    func adaptedSession(_ session: TrainingSession) -> TrainingSession {
        var adapted = session
        for index in adapted.exercises.indices {
            let recommendation = loadRecommendation(for: adapted.exercises[index])
            adapted.exercises[index].suggestedLoadKg = recommendation.loadKg
            adapted.exercises[index].suggestedLoadReason = recommendation.reason
        }
        return adapted
    }

    func replaceExercise(sessionID: UUID, exerciseID: UUID, with option: ExerciseOption) {
        guard var currentPlan = plan,
              let sessionIndex = currentPlan.sessions.firstIndex(where: { $0.id == sessionID }),
              let exerciseIndex = currentPlan.sessions[sessionIndex].exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        var exercise = currentPlan.sessions[sessionIndex].exercises[exerciseIndex]
        guard exercise.pattern == option.pattern else { return }
        exercise.name = option.name
        exercise.equipmentKind = option.equipment
        exercise.suggestedLoadKg = nil
        exercise.suggestedLoadReason = "动作已替换，需要用该器械重新校准工作重量。"
        currentPlan.sessions[sessionIndex].exercises[exerciseIndex] = exercise
        plan = currentPlan
        persist()
    }

    func completeWorkout(_ record: WorkoutRecord) {
        workoutHistory.insert(record, at: 0)
        learnWorkingLoads(from: record)
        persist()
    }

    func startWorkout(_ session: TrainingSession) {
        guard activeWorkoutDraft == nil, let first = session.exercises.first else { return }
        let starting = loadRecommendation(for: first)
        var draft = WorkoutDraft(
            sourceSessionID: session.id,
            session: session,
            exerciseIndex: 0,
            setNumber: 1,
            loadKg: starting.loadKg ?? 0,
            reps: first.repLower,
            rir: first.targetRIR,
            techniqueQuality: 4,
            hasPain: false
        )
        if let profile {
            draft.planSnapshot = PlanSnapshot(
                sourcePlanRuleVersion: plan?.ruleVersion ?? TrainingEngine.ruleVersion,
                sourceSessionID: session.id,
                planTitle: plan?.title ?? "自由训练",
                sessionName: session.name,
                goal: profile.goal,
                split: profile.splitPreference ?? .automatic,
                equipment: profile.equipment,
                exercises: session.exercises
            )
        }
        activeWorkoutDraft = draft
        persist()
    }

    func updateWorkoutDraft(_ mutation: (inout WorkoutDraft) -> Void) {
        guard var draft = activeWorkoutDraft else { return }
        mutation(&draft)
        draft.updatedAt = .now
        activeWorkoutDraft = draft
        persist()
    }

    func completeCurrentDraftSet() {
        guard var draft = activeWorkoutDraft,
              draft.phase == .training,
              draft.exerciseIndex >= 0,
              draft.exerciseIndex < draft.session.exercises.count else { return }
        let exercise = draft.session.exercises[draft.exerciseIndex]
        guard draft.setNumber >= 1,
              draft.setNumber <= exercise.sets,
              !draft.results.contains(where: { $0.exerciseID == exercise.id && $0.setNumber == draft.setNumber }) else { return }

        let previous = draft.results.last { $0.exerciseID == exercise.id }
        let result = SetResult(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            setNumber: draft.setNumber,
            loadKg: draft.loadKg,
            reps: draft.reps,
            rir: draft.rir,
            movementPattern: exercise.pattern,
            techniqueQuality: draft.techniqueQuality,
            feeling: nil,
            setKind: draft.currentSetKind
        )
        draft.results.append(result)
        let exerciseHistory = draft.results.filter { $0.exerciseID == exercise.id }
        draft.recommendation = TrainingEngine.recommendNextSet(
            prescription: exercise,
            result: result,
            readiness: readinessAssessment,
            increment: profile?.loadIncrementKg ?? 2.5,
            exerciseHistory: exerciseHistory,
            priorRecord: lastWorkoutRecord(for: exercise)
        )
        let historicalE1RM = workoutHistory
            .flatMap(\.sets)
            .filter { set in
                if let canonical = TrainingEngine.canonicalExercise(named: set.exerciseName),
                   let current = TrainingEngine.canonicalExercise(named: exercise.name) {
                    return canonical.id == current.id
                }
                return set.exerciseName == exercise.name || set.movementPattern == exercise.pattern
            }
            .compactMap { TrainingEngine.estimatedOneRepMax(loadKg: $0.loadKg, reps: $0.reps, rir: $0.rir) }
            .max()
        draft.restRecommendation = TrainingEngine.recommendRest(
            current: result,
            previous: previous,
            setKind: result.resolvedSetKind,
            pattern: exercise.pattern,
            historicalE1RM: historicalE1RM,
            readiness: readinessAssessment
        )
        draft.restStartedAt = .now
        draft.phase = draft.setNumber >= exercise.sets ? .exerciseComplete : .resting
        draft.userOverrodeSuggestedLoad = false
        draft.updatedAt = .now
        activeWorkoutDraft = draft
        persist()
    }

    func advanceDraftToNextSet() {
        guard var draft = activeWorkoutDraft,
              draft.phase == .resting,
              draft.exerciseIndex >= 0,
              draft.exerciseIndex < draft.session.exercises.count else { return }
        let exercise = draft.session.exercises[draft.exerciseIndex]
        guard draft.setNumber < exercise.sets else { return }

        draft.setNumber += 1
        if let suggested = draft.recommendation?.nextLoadKg {
            draft.loadKg = suggested
        }
        draft.reps = exercise.repLower
        draft.rir = draft.currentSetKind.defaultRIR
        draft.techniqueQuality = 4
        draft.hasPain = false
        draft.phase = .training
        draft.restRecommendation = nil
        draft.restStartedAt = nil
        draft.userOverrodeSuggestedLoad = false
        draft.updatedAt = .now
        activeWorkoutDraft = draft
        persist()
    }

    func setDraftPlannedSets(_ requestedSets: Int) {
        guard var draft = activeWorkoutDraft,
              draft.exerciseIndex >= 0,
              draft.exerciseIndex < draft.session.exercises.count else { return }
        let exerciseID = draft.session.exercises[draft.exerciseIndex].id
        let completed = draft.results.filter { $0.exerciseID == exerciseID }.count
        let minimum = max(1, completed + (draft.phase == .training ? 1 : 0))
        let sets = min(12, max(minimum, requestedSets))
        draft.session.exercises[draft.exerciseIndex].sets = sets
        draft.warmupSetsByExercise[exerciseID] = min(sets, draft.warmupSetsByExercise[exerciseID] ?? 0)
        if draft.phase == .exerciseComplete, sets > completed {
            draft.setNumber = completed + 1
            draft.phase = .training
            draft.restRecommendation = nil
            draft.restStartedAt = nil
        }
        draft.updatedAt = .now
        activeWorkoutDraft = draft
        persist()
    }

    func setDraftWarmupSets(_ requestedSets: Int) {
        guard var draft = activeWorkoutDraft,
              draft.exerciseIndex >= 0,
              draft.exerciseIndex < draft.session.exercises.count else { return }
        let exercise = draft.session.exercises[draft.exerciseIndex]
        draft.warmupSetsByExercise[exercise.id] = min(exercise.sets, max(0, requestedSets))
        draft.rir = draft.currentSetKind.defaultRIR
        draft.updatedAt = .now
        activeWorkoutDraft = draft
        persist()
    }

    func setDraftCurrentSetKind(_ kind: SetKind) {
        guard var draft = activeWorkoutDraft,
              draft.exerciseIndex >= 0,
              draft.exerciseIndex < draft.session.exercises.count else { return }
        let exerciseID = draft.session.exercises[draft.exerciseIndex].id
        var kinds = draft.setKindsByExercise[exerciseID] ?? [:]
        kinds[draft.setNumber] = kind
        draft.setKindsByExercise[exerciseID] = kinds
        draft.rir = kind.defaultRIR
        draft.updatedAt = .now
        activeWorkoutDraft = draft
        persist()
    }

    func replaceDraftCurrentExercise(with option: ExerciseOption) {
        guard var draft = activeWorkoutDraft,
              draft.exerciseIndex >= 0,
              draft.exerciseIndex < draft.session.exercises.count else { return }
        let current = draft.session.exercises[draft.exerciseIndex]
        guard option.pattern == current.pattern,
              !draft.results.contains(where: { $0.exerciseID == current.id }) else { return }
        draft.session.exercises[draft.exerciseIndex].name = option.name
        draft.session.exercises[draft.exerciseIndex].equipmentKind = option.equipment
        draft.session.exercises[draft.exerciseIndex].suggestedLoadKg = nil
        draft.session.exercises[draft.exerciseIndex].suggestedLoadReason = "训练中替换动作，请按当前器械校准重量。"
        var changes = draft.changeEvents ?? []
        changes.append(WorkoutChangeEvent(
            kind: .exerciseReplaced,
            exerciseName: option.name,
            detail: "由\(current.name)替换为\(option.name)"
        ))
        draft.changeEvents = changes
        let starting = loadRecommendation(for: draft.session.exercises[draft.exerciseIndex])
        draft.loadKg = starting.loadKg ?? 0
        draft.reps = draft.session.exercises[draft.exerciseIndex].repLower
        draft.rir = draft.session.exercises[draft.exerciseIndex].targetRIR
        draft.updatedAt = .now
        activeWorkoutDraft = draft
        persist()
    }

    func addDraftExercise(_ option: ExerciseOption) {
        guard var draft = activeWorkoutDraft, let profile else { return }
        draft.session.exercises.append(TrainingEngine.makePrescription(for: option, profile: profile))
        var changes = draft.changeEvents ?? []
        changes.append(WorkoutChangeEvent(kind: .exerciseAdded, exerciseName: option.name, detail: "用户在训练中添加"))
        draft.changeEvents = changes
        draft.updatedAt = .now
        activeWorkoutDraft = draft
        persist()
    }

    func removeDraftCurrentExercise() {
        guard var draft = activeWorkoutDraft,
              draft.session.exercises.count > 1,
              draft.exerciseIndex >= 0,
              draft.exerciseIndex < draft.session.exercises.count else { return }
        let current = draft.session.exercises[draft.exerciseIndex]
        guard !draft.results.contains(where: { $0.exerciseID == current.id }) else { return }
        draft.session.exercises.remove(at: draft.exerciseIndex)
        var changes = draft.changeEvents ?? []
        changes.append(WorkoutChangeEvent(kind: .exerciseRemoved, exerciseName: current.name, detail: "用户在训练中移除"))
        draft.changeEvents = changes
        draft.exerciseIndex = min(draft.exerciseIndex, draft.session.exercises.count - 1)
        prepareDraftForCurrentExercise(&draft)
        activeWorkoutDraft = draft
        persist()
    }

    @discardableResult
    func advanceDraftToNextExercise() -> Bool {
        guard var draft = activeWorkoutDraft,
              draft.exerciseIndex + 1 < draft.session.exercises.count else { return false }
        draft.exerciseIndex += 1
        prepareDraftForCurrentExercise(&draft)
        activeWorkoutDraft = draft
        persist()
        return true
    }

    @discardableResult
    func returnDraftToPreviousExercise() -> Bool {
        guard var draft = activeWorkoutDraft, draft.exerciseIndex > 0 else { return false }
        draft.exerciseIndex -= 1
        prepareDraftForCurrentExercise(&draft)
        activeWorkoutDraft = draft
        persist()
        return true
    }

    @discardableResult
    func saveActiveWorkout(status: WorkoutCompletionStatus) -> WorkoutRecord? {
        guard let draft = activeWorkoutDraft else { return nil }
        guard !draft.results.isEmpty else {
            discardWorkoutDraft()
            return nil
        }
        let qualities = draft.results.compactMap(\.techniqueQuality)
        let quality = qualities.isEmpty
            ? nil
            : Int((Double(qualities.reduce(0, +)) / Double(qualities.count)).rounded())
        let setRPE = draft.results.map { min(10.0, max(5.0, 10.0 - Double($0.rir))) }
        let sessionRPE = setRPE.reduce(0, +) / Double(setRPE.count)
        var record = WorkoutRecord(
            sessionName: draft.session.name,
            startedAt: draft.startedAt,
            completedAt: .now,
            readinessScore: readinessAssessment.score,
            sets: draft.results,
            sessionQuality: quality,
            completionStatus: status,
            sessionRPE: sessionRPE,
            averageHeartRate: draft.averageHeartRate > 0 ? draft.averageHeartRate : nil,
            measuredActiveEnergyKcal: draft.measuredActiveEnergyKcal > 0 ? draft.measuredActiveEnergyKcal : nil
        )
        let weight = latestWeight ?? profile?.bodyWeightKg ?? 70
        let energy = TrainingEngine.strengthEnergyEstimate(record: record, weightKg: weight, profile: profile)
        record.activeEnergyKcal = energy.kilocalories
        record.energyMethod = energy.method
        record.energyLowerBoundKcal = energy.lowerBound
        record.energyUpperBoundKcal = energy.upperBound
        record.effect = TrainingEngine.evaluateStrengthWorkout(record)
        record.planSnapshot = draft.planSnapshot
        record.changeEvents = draft.changeEvents
        record.metricSamples = draft.metricSamples
        finishWorkoutDraft(with: record)
        return record
    }

    private func prepareDraftForCurrentExercise(_ draft: inout WorkoutDraft) {
        let exercise = draft.session.exercises[draft.exerciseIndex]
        let completed = draft.results.filter { $0.exerciseID == exercise.id }.count
        draft.setNumber = min(exercise.sets, completed + 1)
        draft.phase = completed >= exercise.sets ? .exerciseComplete : .training
        let starting = loadRecommendation(for: exercise)
        draft.loadKg = draft.results.last(where: { $0.exerciseID == exercise.id })?.loadKg
            ?? starting.loadKg
            ?? 0
        draft.reps = exercise.repLower
        draft.rir = exercise.targetRIR
        draft.techniqueQuality = 4
        draft.hasPain = false
        draft.recommendation = nil
        draft.restRecommendation = nil
        draft.restStartedAt = nil
        draft.userOverrodeSuggestedLoad = false
        draft.updatedAt = .now
    }

    func checkpointActiveWorkout() {
        guard activeWorkoutDraft != nil else { return }
        persist()
    }

    func discardWorkoutDraft() {
        activeWorkoutDraft = nil
        persist()
    }

    func finishWorkoutDraft(with record: WorkoutRecord) {
        workoutHistory.insert(record, at: 0)
        learnWorkingLoads(from: record)
        activeWorkoutDraft = nil
        persist()
    }

    func deleteWorkout(id: UUID) {
        guard let index = workoutHistory.firstIndex(where: { $0.id == id }) else { return }
        deletedWorkoutHistory.insert(workoutHistory.remove(at: index), at: 0)
        rebuildLearnedLoads()
        persist()
    }

    func restoreWorkout(id: UUID) {
        guard let index = deletedWorkoutHistory.firstIndex(where: { $0.id == id }) else { return }
        workoutHistory.insert(deletedWorkoutHistory.remove(at: index), at: 0)
        rebuildLearnedLoads()
        persist()
    }

    func permanentlyDeleteWorkout(id: UUID) {
        guard deletedWorkoutHistory.contains(where: { $0.id == id }) else { return }
        deletedWorkoutHistory.removeAll { $0.id == id }
        rebuildLearnedLoads()
        persist()
    }

    func deleteCardioWorkout(id: UUID) {
        guard let index = cardioWorkouts.firstIndex(where: { $0.id == id }) else { return }
        deletedCardioWorkouts.insert(cardioWorkouts.remove(at: index), at: 0)
        persist()
    }

    func restoreCardioWorkout(id: UUID) {
        guard let index = deletedCardioWorkouts.firstIndex(where: { $0.id == id }) else { return }
        cardioWorkouts.insert(deletedCardioWorkouts.remove(at: index), at: 0)
        persist()
    }

    func permanentlyDeleteCardioWorkout(id: UUID) {
        guard deletedCardioWorkouts.contains(where: { $0.id == id }) else { return }
        deletedCardioWorkouts.removeAll { $0.id == id }
        persist()
    }

    func deleteWeight(id: UUID) {
        guard let index = weightHistory.firstIndex(where: { $0.id == id }) else { return }
        deletedWeightHistory.insert(weightHistory.remove(at: index), at: 0)
        persist()
    }

    func restoreWeight(id: UUID) {
        guard let index = deletedWeightHistory.firstIndex(where: { $0.id == id }) else { return }
        weightHistory.append(deletedWeightHistory.remove(at: index))
        weightHistory.sort { $0.date < $1.date }
        persist()
    }

    func permanentlyDeleteWeight(id: UUID) {
        guard deletedWeightHistory.contains(where: { $0.id == id }) else { return }
        deletedWeightHistory.removeAll { $0.id == id }
        persist()
    }

    func emptyTrash() {
        deletedWorkoutHistory.removeAll()
        deletedCardioWorkouts.removeAll()
        deletedWeightHistory.removeAll()
        deletedCardioHistory.removeAll()
        deletedRecoveryHistory.removeAll()
        deletedBodyCompositionHistory.removeAll()
        rebuildLearnedLoads()
        persist()
    }

    func clearRecordObjectsToTrash() {
        deletedWorkoutHistory.insert(contentsOf: workoutHistory, at: 0)
        deletedCardioWorkouts.insert(contentsOf: cardioWorkouts, at: 0)
        deletedWeightHistory.insert(contentsOf: weightHistory, at: 0)
        deletedCardioHistory.insert(contentsOf: cardioHistory, at: 0)
        deletedRecoveryHistory.insert(contentsOf: recoveryHistory, at: 0)
        deletedBodyCompositionHistory.insert(contentsOf: bodyCompositionHistory, at: 0)
        workoutHistory.removeAll()
        cardioWorkouts.removeAll()
        weightHistory.removeAll()
        cardioHistory.removeAll()
        recoveryHistory.removeAll()
        bodyCompositionHistory.removeAll()
        rebuildLearnedLoads()
        persist()
    }

    func restoreAllDeletedRecords() {
        workoutHistory.append(contentsOf: deletedWorkoutHistory)
        cardioWorkouts.append(contentsOf: deletedCardioWorkouts)
        weightHistory.append(contentsOf: deletedWeightHistory)
        cardioHistory.append(contentsOf: deletedCardioHistory)
        recoveryHistory.append(contentsOf: deletedRecoveryHistory)
        bodyCompositionHistory.append(contentsOf: deletedBodyCompositionHistory)
        deletedWorkoutHistory.removeAll()
        deletedCardioWorkouts.removeAll()
        deletedWeightHistory.removeAll()
        deletedCardioHistory.removeAll()
        deletedRecoveryHistory.removeAll()
        deletedBodyCompositionHistory.removeAll()
        workoutHistory.sort { $0.completedAt > $1.completedAt }
        cardioWorkouts.sort { $0.date > $1.date }
        weightHistory.sort { $0.date < $1.date }
        rebuildLearnedLoads()
        persist()
    }

    var deletedRecordCount: Int {
        deletedWorkoutHistory.count + deletedCardioWorkouts.count + deletedWeightHistory.count + deletedCardioHistory.count + deletedRecoveryHistory.count + deletedBodyCompositionHistory.count
    }

    func resetAllData() {
        profile = nil
        plan = nil
        readiness = ReadinessInput()
        workoutHistory = []
        weightHistory = []
        cardioHistory = []
        recoveryHistory = []
        cardioWorkouts = []
        dailyActiveEnergy = []
        dailySteps = []
        bodyCompositionHistory = []
        deletedWorkoutHistory = []
        deletedCardioWorkouts = []
        deletedWeightHistory = []
        deletedCardioHistory = []
        deletedRecoveryHistory = []
        deletedBodyCompositionHistory = []
        dailyTrainingChoice = nil
        activeWorkoutDraft = nil
        recoveryCheckIns = []
        safetySettings = PersonalSafetySettings()
        favoriteExerciseIDs = []
        customExercises = []
        defaults.removeObject(forKey: storageKey)
    }

    private var scheduledSession: TrainingSession? {
        guard let sessions = plan?.sessions,
              let index = TrainingEngine.nextSessionIndex(history: workoutHistory, sessionCount: sessions.count) else { return nil }
        return sessions[index]
    }

    private func learnWorkingLoads(from record: WorkoutRecord) {
        guard var currentPlan = plan else { return }
        for set in record.sets.reversed() where set.resolvedSetKind == .working && set.loadKg > 0 {
            for sessionIndex in currentPlan.sessions.indices {
                if let exerciseIndex = currentPlan.sessions[sessionIndex].exercises.firstIndex(where: { $0.name == set.exerciseName }) {
                    currentPlan.sessions[sessionIndex].exercises[exerciseIndex].suggestedLoadKg = set.loadKg
                    currentPlan.sessions[sessionIndex].exercises[exerciseIndex].suggestedLoadReason = "来自最近一次已完成训练。"
                }
            }
        }
        plan = currentPlan
    }

    private func rebuildLearnedLoads() {
        guard var currentPlan = plan else { return }
        for sessionIndex in currentPlan.sessions.indices {
            for exerciseIndex in currentPlan.sessions[sessionIndex].exercises.indices {
                currentPlan.sessions[sessionIndex].exercises[exerciseIndex].suggestedLoadKg = nil
                currentPlan.sessions[sessionIndex].exercises[exerciseIndex].suggestedLoadReason = "等待有效训练记录重新校准。"
            }
        }
        plan = currentPlan
        for record in workoutHistory.sorted(by: { $0.completedAt < $1.completedAt }) {
            learnWorkingLoads(from: record)
        }
    }

    private func persist() {
        let snapshot = AppSnapshot(
            profile: profile,
            plan: plan,
            readiness: readiness,
            workoutHistory: workoutHistory,
            weightHistory: weightHistory,
            cardioHistory: cardioHistory,
            recoveryHistory: recoveryHistory,
            dailyTrainingChoice: dailyTrainingChoice,
            cardioWorkouts: cardioWorkouts,
            dailyActiveEnergy: dailyActiveEnergy,
            dailySteps: dailySteps,
            bodyCompositionHistory: bodyCompositionHistory,
            deletedWorkoutHistory: deletedWorkoutHistory,
            deletedCardioWorkouts: deletedCardioWorkouts,
            deletedWeightHistory: deletedWeightHistory,
            deletedCardioHistory: deletedCardioHistory,
            deletedRecoveryHistory: deletedRecoveryHistory,
            deletedBodyCompositionHistory: deletedBodyCompositionHistory,
            activeWorkoutDraft: activeWorkoutDraft,
            recoveryCheckIns: recoveryCheckIns,
            safetySettings: safetySettings,
            favoriteExerciseIDs: favoriteExerciseIDs,
            customExercises: customExercises
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func restore() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(AppSnapshot.self, from: data) else { return }
        let needsSchemaMigration = snapshot.resolvedSchemaVersion < AppSnapshot.currentSchemaVersion
        profile = snapshot.profile
        plan = snapshot.plan
        // Preserve the user's customized plan while marking it as running on the
        // current deterministic rule set after a migration.
        if plan?.ruleVersion != TrainingEngine.ruleVersion {
            plan?.ruleVersion = TrainingEngine.ruleVersion
        }
        readiness = snapshot.readiness
        workoutHistory = snapshot.workoutHistory
        weightHistory = snapshot.weightHistory
        cardioHistory = snapshot.cardioHistory ?? []
        recoveryHistory = snapshot.recoveryHistory ?? []
        dailyTrainingChoice = snapshot.dailyTrainingChoice
        cardioWorkouts = snapshot.cardioWorkouts ?? []
        dailyActiveEnergy = snapshot.dailyActiveEnergy ?? []
        dailySteps = snapshot.dailySteps ?? []
        bodyCompositionHistory = snapshot.bodyCompositionHistory ?? []
        deletedWorkoutHistory = snapshot.deletedWorkoutHistory ?? []
        deletedCardioWorkouts = snapshot.deletedCardioWorkouts ?? []
        deletedWeightHistory = snapshot.deletedWeightHistory ?? []
        deletedCardioHistory = snapshot.deletedCardioHistory ?? []
        deletedRecoveryHistory = snapshot.deletedRecoveryHistory ?? []
        deletedBodyCompositionHistory = snapshot.deletedBodyCompositionHistory ?? []
        activeWorkoutDraft = snapshot.activeWorkoutDraft
        recoveryCheckIns = snapshot.recoveryCheckIns ?? []
        safetySettings = snapshot.safetySettings ?? PersonalSafetySettings()
        customExercises = (snapshot.customExercises ?? []).filter { $0.source == .custom }
        let validExerciseIDs = Set(TrainingEngine.allExercises.map(\.id) + customExercises.map(\.id))
        favoriteExerciseIDs = (snapshot.favoriteExerciseIDs ?? []).intersection(validExerciseIDs)
        if needsSchemaMigration {
            persist()
        }
    }
}
