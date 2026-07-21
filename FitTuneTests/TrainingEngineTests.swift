import XCTest
@testable import FitTune

final class TrainingEngineTests: XCTestCase {
    func testLowReadinessProducesConservativeAdjustment() {
        let input = ReadinessInput(sleepHours: 4.5, soreness: 5, stress: 5, motivation: 1)
        let assessment = TrainingEngine.assessReadiness(input)

        XCTAssertEqual(assessment.level, .low)
        XCTAssertLessThan(assessment.loadMultiplier, 1)
        XCTAssertEqual(assessment.setReduction, 1)
    }

    func testGoodReadinessKeepsOriginalPlan() {
        let input = ReadinessInput(sleepHours: 8, soreness: 1, stress: 1, motivation: 5)
        let assessment = TrainingEngine.assessReadiness(input)

        XCTAssertEqual(assessment.level, .ready)
        XCTAssertEqual(assessment.loadMultiplier, 1)
        XCTAssertEqual(assessment.setReduction, 0)
    }

    func testNextSetIncreasesAfterTopRepsWithExtraRIR() {
        let exercise = ExercisePrescription(
            name: "卧推",
            pattern: .horizontalPush,
            sets: 3,
            repLower: 6,
            repUpper: 10,
            targetRIR: 2,
            isPriority: true,
            suggestedLoadKg: nil
        )
        let result = SetResult(exerciseID: exercise.id, exerciseName: exercise.name, setNumber: 1, loadKg: 60, reps: 10, rir: 4)
        let recommendation = TrainingEngine.recommendNextSet(
            prescription: exercise,
            result: result,
            readiness: readyAssessment,
            increment: 2.5
        )

        XCTAssertEqual(recommendation.adjustment, .increase)
        XCTAssertEqual(recommendation.nextLoadKg, 62.5)
    }

    func testNextSetDecreasesAfterMissedTarget() {
        let exercise = ExercisePrescription(
            name: "深蹲",
            pattern: .squat,
            sets: 3,
            repLower: 5,
            repUpper: 8,
            targetRIR: 3,
            isPriority: true,
            suggestedLoadKg: nil
        )
        let result = SetResult(exerciseID: exercise.id, exerciseName: exercise.name, setNumber: 1, loadKg: 100, reps: 4, rir: 1)
        let recommendation = TrainingEngine.recommendNextSet(
            prescription: exercise,
            result: result,
            readiness: readyAssessment,
            increment: 2.5
        )

        XCTAssertEqual(recommendation.adjustment, .decrease)
        XCTAssertLessThan(recommendation.nextLoadKg, 100)
    }

    func testReturnToTrainingStartsWithLessVolumeThanAdvancedHypertrophy() {
        var returnProfile = profile(goal: .returnToTraining, experience: .returning)
        let returnPlan = TrainingEngine.generatePlan(for: returnProfile)

        returnProfile.goal = .hypertrophy
        returnProfile.experience = .advanced
        let advancedPlan = TrainingEngine.generatePlan(for: returnProfile)

        let returnSets = returnPlan.sessions.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
        let advancedSets = advancedPlan.sessions.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
        XCTAssertLessThan(returnSets, advancedSets)
    }

    func testPlanRespectsSelectedTrainingDaysAndEquipment() {
        let user = profile(goal: .recomposition, experience: .intermediate, days: 4, equipment: .dumbbells)
        let plan = TrainingEngine.generatePlan(for: user)

        XCTAssertEqual(plan.sessions.count, 4)
        XCTAssertTrue(plan.sessions.flatMap(\.exercises).contains { $0.name.contains("哑铃") })
    }

    func testE1RMIncludesReportedRIRButCapsMaxReps() {
        let estimate = TrainingEngine.estimatedOneRepMax(loadKg: 100, reps: 5, rir: 2)
        XCTAssertEqual(estimate ?? 0, 123.333, accuracy: 0.01)
    }

    func testStartingLoadIncreasesAfterQualitySessionAndRecovery() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let exercise = ExercisePrescription(
            name: "杠铃卧推",
            pattern: .horizontalPush,
            sets: 3,
            repLower: 6,
            repUpper: 10,
            targetRIR: 2,
            isPriority: true,
            suggestedLoadKg: nil,
            equipmentKind: .barbell
        )
        let set = SetResult(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            setNumber: 1,
            loadKg: 60,
            reps: 10,
            rir: 4,
            movementPattern: exercise.pattern,
            techniqueQuality: 5
        )
        let record = WorkoutRecord(
            sessionName: "胸",
            startedAt: now.addingTimeInterval(-72 * 3600 - 1800),
            completedAt: now.addingTimeInterval(-72 * 3600),
            readinessScore: 85,
            sets: [set],
            sessionQuality: 5
        )

        let recommendation = TrainingEngine.recommendStartingLoad(
            prescription: exercise,
            history: [record],
            readiness: readyAssessment,
            increment: 2.5,
            now: now
        )

        XCTAssertEqual(recommendation.adjustment, .increase)
        XCTAssertEqual(recommendation.loadKg ?? 0, 62.5)
        XCTAssertEqual(recommendation.daysSinceLast, 3)
    }

    func testStartingLoadDropsWhenSamePatternWasTrainedUnder24HoursAgo() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let exercise = ExercisePrescription(
            name: "腿举机",
            pattern: .squat,
            sets: 3,
            repLower: 6,
            repUpper: 10,
            targetRIR: 3,
            isPriority: true,
            suggestedLoadKg: nil,
            equipmentKind: .machineCable
        )
        let set = SetResult(
            exerciseID: UUID(),
            exerciseName: "杠铃深蹲",
            setNumber: 1,
            loadKg: 100,
            reps: 8,
            rir: 3,
            movementPattern: .squat,
            techniqueQuality: 4
        )
        let record = WorkoutRecord(
            sessionName: "腿",
            startedAt: now.addingTimeInterval(-13 * 3600),
            completedAt: now.addingTimeInterval(-12 * 3600),
            readinessScore: 80,
            sets: [set]
        )

        let recommendation = TrainingEngine.recommendStartingLoad(
            prescription: exercise,
            history: [record],
            readiness: readyAssessment,
            increment: 2.5,
            now: now
        )

        XCTAssertEqual(recommendation.adjustment, .decrease)
        XCTAssertEqual(recommendation.loadKg ?? 0, 90)
    }

    func testSelectedSplitAndCardioAreGeneratedAsSeparateModules() {
        var user = profile(goal: .recomposition, experience: .intermediate, days: 3)
        user.splitPreference = .pushPullLegs
        user.strengthTrainingGoal = .hypertrophy
        user.cardioTrainingGoal = .aerobicBase

        let plan = TrainingEngine.generatePlan(for: user)

        XCTAssertEqual(plan.sessions.map(\.name), ["推", "拉", "腿"])
        XCTAssertEqual(plan.cardioSessions?.count, 2)
        XCTAssertFalse(plan.sessions.flatMap(\.exercises).contains { $0.pattern == .conditioning })
    }

    func testExerciseAlternativesKeepMovementPatternAcrossEquipment() {
        let options = TrainingEngine.exerciseAlternatives(for: .horizontalPush)

        XCTAssertGreaterThanOrEqual(Set(options.map(\.equipment)).count, 3)
        XCTAssertTrue(options.allSatisfy { $0.pattern == .horizontalPush })
    }

    func testTodaySessionCanBeFreelyChangedToChest() {
        let user = profile(goal: .hypertrophy, experience: .intermediate, days: 4)
        let session = TrainingEngine.makeTodaySession(
            focus: .chest,
            profile: user,
            recommendedSession: nil,
            avoiding: []
        )

        XCTAssertEqual(session?.name, "胸部训练")
        XCTAssertTrue(session?.exercises.contains { $0.pattern == .horizontalPush } == true)
        XCTAssertTrue(session?.exercises.contains { $0.pattern == .chestIsolation } == true)
        XCTAssertFalse(session?.exercises.contains { $0.pattern == .squat } == true)
    }

    func testTodaySessionRemovesEveryMovementThatAffectsAvoidedRegion() {
        let user = profile(goal: .recomposition, experience: .intermediate, days: 4)
        let session = TrainingEngine.makeTodaySession(
            focus: .fullBody,
            profile: user,
            recommendedSession: nil,
            avoiding: [.shoulders]
        )

        XCTAssertNotNil(session)
        XCTAssertTrue(session?.exercises.allSatisfy {
            TrainingEngine.movementRegions(for: $0.pattern).isDisjoint(with: [.shoulders])
        } == true)
    }

    func testSelectingAnAvoidedPrimaryBodyPartReturnsNoSession() {
        let user = profile(goal: .hypertrophy, experience: .intermediate, days: 4)
        let session = TrainingEngine.makeTodaySession(
            focus: .legs,
            profile: user,
            recommendedSession: nil,
            avoiding: [.legs]
        )

        XCTAssertNil(session)
    }

    func testPartialWorkoutDoesNotAdvancePlanRotation() {
        let partial = WorkoutRecord(
            sessionName: "胸部训练",
            startedAt: .now,
            completedAt: .now,
            readinessScore: 80,
            sets: [],
            completionStatus: .partial
        )
        let completed = WorkoutRecord(
            sessionName: "背部训练",
            startedAt: .now,
            completedAt: .now,
            readinessScore: 80,
            sets: [],
            completionStatus: .completed
        )

        XCTAssertEqual(TrainingEngine.nextSessionIndex(history: [partial], sessionCount: 4), 0)
        XCTAssertEqual(TrainingEngine.nextSessionIndex(history: [partial, completed], sessionCount: 4), 1)
    }

    func testRestingEnergyUsesMifflinStJeorWhenProfileIsComplete() {
        var user = profile(goal: .recomposition, experience: .intermediate)
        user.ageYears = 30
        user.heightCm = 175
        user.biologicalSex = .male

        XCTAssertEqual(TrainingEngine.restingEnergy(profile: user) ?? 0, 1648.75, accuracy: 0.01)
    }

    func testCardioEnergyUsesNetMETAndMeasuredValueCanOverride() {
        let estimated = TrainingEngine.makeCardioWorkout(
            modality: .running,
            intensity: .zone2,
            minutes: 30,
            weightKg: 70
        )
        let expected = (8.3 - 1) * 3.5 * 70 / 200 * 30
        XCTAssertEqual(estimated.activeEnergyKcal, expected, accuracy: 0.01)

        let measured = TrainingEngine.makeCardioWorkout(
            modality: .running,
            intensity: .zone2,
            minutes: 30,
            weightKg: 70,
            measuredActiveEnergy: 321
        )
        XCTAssertEqual(measured.activeEnergyKcal, 321)
    }

    func testRepeatedExhaustedSetsStopCurrentExerciseAndExtendRest() {
        let exercise = ExercisePrescription(
            name: "杠铃深蹲",
            pattern: .squat,
            sets: 4,
            repLower: 5,
            repUpper: 8,
            targetRIR: 2,
            isPriority: true,
            suggestedLoadKg: nil
        )
        let first = SetResult(exerciseID: exercise.id, exerciseName: exercise.name, setNumber: 1, loadKg: 100, reps: 5, rir: 0, movementPattern: .squat, techniqueQuality: 2, feeling: .exhausted)
        let second = SetResult(exerciseID: exercise.id, exerciseName: exercise.name, setNumber: 2, loadKg: 90, reps: 5, rir: 0, movementPattern: .squat, techniqueQuality: 2, feeling: .exhausted)
        let recommendation = TrainingEngine.recommendNextSet(
            prescription: exercise,
            result: second,
            readiness: readyAssessment,
            increment: 2.5,
            exerciseHistory: [first, second]
        )

        XCTAssertEqual(recommendation.continuation, .stopExercise)
        XCTAssertEqual(recommendation.suggestedRemainingSets, 0)
        XCTAssertGreaterThanOrEqual(recommendation.restSeconds, 240)
        XCTAssertLessThan(recommendation.nextLoadKg, second.loadKg)
    }

    func testExpandedExerciseLibraryProvidesBroadSamePatternChoice() {
        XCTAssertGreaterThanOrEqual(TrainingEngine.exerciseAlternatives(for: .horizontalPush).count, 8)
        XCTAssertGreaterThanOrEqual(TrainingEngine.exerciseAlternatives(for: .horizontalPull).count, 8)
        XCTAssertGreaterThanOrEqual(TrainingEngine.exerciseAlternatives(for: .hinge).count, 8)
    }

    func testCunninghamUsesFatFreeMassWhenBodyCompositionExists() {
        var user = profile(goal: .recomposition, experience: .intermediate)
        user.bodyFatPercent = 20
        let estimate = TrainingEngine.restingEnergyEstimate(profile: user)
        XCTAssertEqual(estimate?.kilocalories ?? 0, 1732, accuracy: 0.01)
        XCTAssertEqual(estimate?.method, "Cunningham（去脂体重）")
    }

    func testMeasuredRMRHasHighestPriority() {
        var user = profile(goal: .recomposition, experience: .intermediate)
        user.bodyFatPercent = 20
        user.measuredRMRKcal = 1900
        let estimate = TrainingEngine.restingEnergyEstimate(profile: user)
        XCTAssertEqual(estimate?.kilocalories, 1900)
        XCTAssertEqual(estimate?.confidence, "高")
    }

    func testInclineWalkingUsesSpeedGradeEquationBeforeMET() {
        let estimate = TrainingEngine.cardioEnergyEstimate(
            modality: .inclineWalking,
            intensity: .zone2,
            minutes: 30,
            weightKg: 70,
            speedKph: 6,
            inclinePercent: 10
        )
        XCTAssertEqual(estimate.kilocalories, 294, accuracy: 0.01)
        XCTAssertTrue(estimate.method.contains("ACSM"))
        XCTAssertGreaterThan(estimate.upperBound, estimate.kilocalories)
    }

    func testHeartRateEnergyIsUsedWhenProfileAndHeartRateExist() {
        var user = profile(goal: .generalFitness, experience: .intermediate)
        user.ageYears = 30
        user.heightCm = 175
        user.biologicalSex = .male
        let estimate = TrainingEngine.cardioEnergyEstimate(
            modality: .cycling,
            intensity: .zone2,
            minutes: 40,
            weightKg: 70,
            profile: user,
            averageHeartRate: 140
        )
        XCTAssertTrue(estimate.method.contains("Keytel"))
        XCTAssertGreaterThan(estimate.kilocalories, 0)
    }

    func testStrengthMeasuredEnergyOverridesEstimate() {
        let record = WorkoutRecord(
            sessionName: "力量",
            startedAt: .now.addingTimeInterval(-3600),
            completedAt: .now,
            readinessScore: 80,
            sets: [],
            measuredActiveEnergyKcal: 234
        )
        let estimate = TrainingEngine.strengthEnergyEstimate(record: record, weightKg: 70)
        XCTAssertEqual(estimate.kilocalories, 234)
        XCTAssertEqual(estimate.confidence, "高")
    }

    func testEffectReportsRecoveryRangeAndSessionLoad() {
        let exerciseID = UUID()
        let record = WorkoutRecord(
            sessionName: "胸",
            startedAt: .now.addingTimeInterval(-3600),
            completedAt: .now,
            readinessScore: 75,
            sets: [
                SetResult(exerciseID: exerciseID, exerciseName: "卧推", setNumber: 1, loadKg: 80, reps: 8, rir: 2, movementPattern: .horizontalPush, techniqueQuality: 4, feeling: .moderate),
                SetResult(exerciseID: exerciseID, exerciseName: "卧推", setNumber: 2, loadKg: 80, reps: 8, rir: 1, movementPattern: .horizontalPush, techniqueQuality: 4, feeling: .hard)
            ],
            sessionRPE: 8
        )
        let effect = TrainingEngine.evaluateStrengthWorkout(record)
        XCTAssertNotNil(effect.trainingLoadAU)
        XCTAssertLessThan(effect.recoveryLowerHours ?? 999, effect.recoveryUpperHours ?? 0)
        XCTAssertTrue(effect.method?.contains("session-RPE") == true)
    }

    func testLibraryIncludesSpecificSmithMachineAndCableCategories() {
        XCTAssertGreaterThanOrEqual(TrainingEngine.allExerciseOptions.filter { $0.equipment == .smithMachine }.count, 8)
        XCTAssertGreaterThanOrEqual(TrainingEngine.allExerciseOptions.filter { $0.equipment == .cable }.count, 8)
        XCTAssertGreaterThanOrEqual(TrainingEngine.allExerciseOptions.filter { $0.resolvedCategory == .chest }.count, 15)
    }

    private var readyAssessment: ReadinessAssessment {
        TrainingEngine.assessReadiness(ReadinessInput(sleepHours: 8, soreness: 1, stress: 1, motivation: 5))
    }

    private func profile(
        goal: TrainingGoal,
        experience: ExperienceLevel,
        days: Int = 3,
        equipment: EquipmentProfile = .fullGym
    ) -> UserProfile {
        UserProfile(
            nickname: "测试",
            goal: goal,
            secondaryGoal: .none,
            experience: experience,
            weeklyDays: days,
            sessionMinutes: 60,
            equipment: equipment,
            bodyWeightKg: 70,
            loadIncrementKg: 2.5
        )
    }
}
