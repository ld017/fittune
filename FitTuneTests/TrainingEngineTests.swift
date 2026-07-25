import XCTest
@testable import FitTune

final class TrainingEngineTests: XCTestCase {
    func testGeneratedExercisesDefaultToFourWorkingSets() throws {
        let profile = profile(goal: .hypertrophy, experience: .new)
        let plan = TrainingEngine.generatePlan(for: profile)
        let exercise = try XCTUnwrap(plan.sessions.first?.exercises.first)

        XCTAssertEqual(exercise.resolvedWorkingSets, 4)
    }
    func testGeneratedPlanUsesRIRZeroForAllWorkingPrescriptions() {
        let plan = TrainingEngine.generatePlan(for: profile(goal: .hypertrophy, experience: .intermediate))

        XCTAssertFalse(plan.sessions.flatMap(\.exercises).isEmpty)
        XCTAssertTrue(plan.sessions.flatMap(\.exercises).allSatisfy { $0.targetRIR == 0 })
    }

    func testAutomaticWarmupRampsLoadAndReducesRepetitions() {
        let warmups = TrainingEngine.warmupPrescription(workingLoadKg: 100, workingReps: 5, setCount: 3)

        XCTAssertEqual(warmups.count, 3)
        XCTAssertEqual(warmups.map(\.rir), [5, 5, 5])
        XCTAssertTrue(zip(warmups, warmups.dropFirst()).allSatisfy { $0.loadKg < $1.loadKg })
        XCTAssertTrue(zip(warmups, warmups.dropFirst()).allSatisfy { $0.reps >= $1.reps })
        XCTAssertLessThan(warmups.last?.loadKg ?? 100, 100)
    }

    func testOnlyWorkingSetsContributeToStrengthProgressEffect() {
        let exerciseID = UUID()
        let date = Date(timeIntervalSince1970: 1_721_563_200)
        let working = SetResult(exerciseID: exerciseID, exerciseName: "卧推", setNumber: 2, loadKg: 80, reps: 8, rir: 0, completedAt: date, setKind: .working)
        let warmup = SetResult(exerciseID: exerciseID, exerciseName: "卧推", setNumber: 1, loadKg: 40, reps: 20, rir: 0, completedAt: date, setKind: .warmup)
        let base = WorkoutRecord(sessionName: "胸", startedAt: date, completedAt: date.addingTimeInterval(3600), readinessScore: 80, sets: [working], sessionRPE: 8)
        let withWarmup = WorkoutRecord(sessionName: "胸", startedAt: date, completedAt: date.addingTimeInterval(3600), readinessScore: 80, sets: [warmup, working], sessionRPE: 8)

        let baseEffect = TrainingEngine.evaluateStrengthWorkout(base)
        let warmupEffect = TrainingEngine.evaluateStrengthWorkout(withWarmup)

        XCTAssertEqual(warmupEffect.strengthScore, baseEffect.strengthScore)
        XCTAssertEqual(warmupEffect.hypertrophyScore, baseEffect.hypertrophyScore)
        XCTAssertEqual(warmupEffect.fatigueScore, baseEffect.fatigueScore)
    }
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

    func testAllExperienceLevelsReceiveFourEditableWorkingSets() {
        var returnProfile = profile(goal: .returnToTraining, experience: .returning)
        let returnPlan = TrainingEngine.generatePlan(for: returnProfile)

        returnProfile.goal = .hypertrophy
        returnProfile.experience = .advanced
        let advancedPlan = TrainingEngine.generatePlan(for: returnProfile)

        let returnSets = returnPlan.sessions.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
        let advancedSets = advancedPlan.sessions.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
        XCTAssertEqual(returnSets, advancedSets)
        XCTAssertTrue(returnPlan.sessions.flatMap(\.exercises).allSatisfy { $0.resolvedWorkingSets == 4 })
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

    func testRepeatedRIRZeroSetsRemainAdvisoryAndExtendRest() {
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
        let rest = TrainingEngine.recommendRest(
            current: second,
            previous: first,
            setKind: .working,
            pattern: .squat,
            historicalE1RM: 120,
            readiness: readyAssessment
        )

        XCTAssertEqual(recommendation.continuation, .continueTraining)
        XCTAssertEqual(recommendation.suggestedRemainingSets, 2)
        XCTAssertGreaterThanOrEqual(rest.recommendedSeconds, 240)
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

    func testCardioHeartRateSeriesFillsLongGapWithModalityMET() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var user = profile(goal: .generalFitness, experience: .intermediate)
        user.ageYears = 30
        user.biologicalSex = .male
        let provenance = MetricProvenance(
            source: .bluetooth,
            sourceName: "FIT 3",
            confidence: .measured,
            coverage: 1
        )
        let samples = [0.0, 5.0, 1_795.0, 1_800.0].map {
            WorkoutMetricSample(
                timestamp: start.addingTimeInterval($0),
                heartRateBPM: 145,
                provenance: provenance
            )
        }

        let estimate = TrainingEngine.cardioEnergyEstimate(
            modality: .cycling,
            intensity: .zone2,
            minutes: 30,
            weightKg: 70,
            profile: user,
            metricSamples: samples,
            startedAt: start
        )
        let fallback = TrainingEngine.netActiveEnergy(
            met: TrainingEngine.cardioMET(modality: .cycling, intensity: .zone2),
            weightKg: 70,
            minutes: 30
        )

        XCTAssertEqual(estimate.kilocalories, fallback, accuracy: fallback * 0.05)
        XCTAssertTrue(estimate.method.contains("心率 + 有氧模型"))
    }

    func testCardioTimeSeriesWithoutDemographicsUsesPureMETModel() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let user = profile(goal: .generalFitness, experience: .intermediate)
        let provenance = MetricProvenance(
            source: .bluetooth,
            sourceName: "FIT 3",
            confidence: .measured,
            coverage: 1
        )
        let samples = [0.0, 5.0].map {
            WorkoutMetricSample(
                timestamp: start.addingTimeInterval($0),
                heartRateBPM: 145,
                provenance: provenance
            )
        }

        let estimate = TrainingEngine.cardioEnergyEstimate(
            modality: .cycling,
            intensity: .zone2,
            minutes: 30,
            weightKg: 70,
            profile: user,
            metricSamples: samples,
            startedAt: start
        )

        XCTAssertEqual(estimate.method, "2024 Adult Compendium MET")
        XCTAssertEqual(estimate.confidence, "低至中")
    }

    func testOnlyAppleWatchSamplesProvideMeasuredWorkoutEnergy() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let watch = MetricProvenance(
            source: .appleWatch,
            sourceName: "Apple Watch",
            confidence: .measured,
            coverage: 1
        )
        let bluetooth = MetricProvenance(
            source: .bluetooth,
            sourceName: "FIT 3",
            confidence: .measured,
            coverage: 1
        )

        XCTAssertEqual(
            TrainingEngine.appleWatchActiveEnergy(from: [
                .init(timestamp: date, activeEnergyKcal: 120, provenance: watch),
                .init(timestamp: date.addingTimeInterval(5), activeEnergyKcal: 180, provenance: watch)
            ]),
            180
        )
        XCTAssertNil(TrainingEngine.appleWatchActiveEnergy(from: [
            .init(timestamp: date, activeEnergyKcal: 180, provenance: bluetooth)
        ]))
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

    func testLowHeartRateStrengthSessionUsesModelFloorInsteadOfSingleDigitEnergy() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var user = profile(goal: .hypertrophy, experience: .intermediate)
        user.ageYears = 30
        user.biologicalSex = .female
        let provenance = MetricProvenance(
            source: .bluetooth,
            sourceName: "HUAWEI WATCH FIT 3",
            confidence: .measured,
            coverage: 1
        )
        let samples = stride(from: 0.0, through: 3_600.0, by: 5.0).map {
            WorkoutMetricSample(
                timestamp: start.addingTimeInterval($0),
                heartRateBPM: 70,
                provenance: provenance
            )
        }
        let record = WorkoutRecord(
            sessionName: "力量",
            startedAt: start,
            completedAt: start.addingTimeInterval(3_600),
            readinessScore: 80,
            sets: [],
            sessionRPE: 7,
            averageHeartRate: 70,
            metricSamples: samples
        )

        let estimate = TrainingEngine.strengthEnergyEstimate(
            record: record,
            weightKg: 70,
            profile: user
        )

        XCTAssertGreaterThan(estimate.kilocalories, 100)
        XCTAssertTrue(estimate.method.contains("心率 + 力量模型"))
        XCTAssertLessThan(estimate.lowerBound, estimate.kilocalories)
        XCTAssertGreaterThan(estimate.upperBound, estimate.kilocalories)
    }

    func testStrengthHeartRateGapsAreFilledWithoutDoubleCounting() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var user = profile(goal: .hypertrophy, experience: .intermediate)
        user.ageYears = 30
        user.biologicalSex = .male
        let provenance = MetricProvenance(
            source: .bluetooth,
            sourceName: "H10",
            confidence: .measured,
            coverage: 1
        )
        let samples = [0.0, 5.0, 1_800.0, 1_805.0].map {
            WorkoutMetricSample(
                timestamp: start.addingTimeInterval($0),
                heartRateBPM: 140,
                provenance: provenance
            )
        }
        let record = WorkoutRecord(
            sessionName: "力量",
            startedAt: start,
            completedAt: start.addingTimeInterval(3_600),
            readinessScore: 80,
            sets: [],
            sessionRPE: 7,
            averageHeartRate: 140,
            metricSamples: samples
        )

        let estimate = TrainingEngine.strengthEnergyEstimate(
            record: record,
            weightKg: 70,
            profile: user
        )
        let fallback = TrainingEngine.netActiveEnergy(
            met: 5,
            weightKg: 70,
            minutes: 60
        )

        XCTAssertEqual(estimate.kilocalories, fallback, accuracy: fallback * 0.05)
        XCTAssertEqual(estimate.confidence, "低至中")
    }

    func testStrengthTimeSeriesWithoutDemographicsUsesPureSessionRPEModel() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let user = profile(goal: .hypertrophy, experience: .intermediate)
        let provenance = MetricProvenance(
            source: .bluetooth,
            sourceName: "FIT 3",
            confidence: .measured,
            coverage: 1
        )
        let samples = [0.0, 5.0].map {
            WorkoutMetricSample(
                timestamp: start.addingTimeInterval($0),
                heartRateBPM: 140,
                provenance: provenance
            )
        }
        let record = WorkoutRecord(
            sessionName: "力量",
            startedAt: start,
            completedAt: start.addingTimeInterval(3_600),
            readinessScore: 80,
            sets: [],
            sessionRPE: 7,
            metricSamples: samples
        )

        let estimate = TrainingEngine.strengthEnergyEstimate(
            record: record,
            weightKg: 70,
            profile: user
        )

        XCTAssertEqual(estimate.method, "2024 Adult Compendium MET + session-RPE")
        XCTAssertEqual(estimate.confidence, "低至中")
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

    func testRIRZeroDoesNotReduceUserPlannedSetsOrForceStop() {
        let exercise = ExercisePrescription(
            name: "卧推",
            pattern: .horizontalPush,
            sets: 5,
            repLower: 6,
            repUpper: 10,
            targetRIR: 2,
            isPriority: true
        )
        let prior = [
            SetResult(exerciseID: exercise.id, exerciseName: exercise.name, setNumber: 2, loadKg: 80, reps: 8, rir: 0, techniqueQuality: 2, feeling: .maximal),
            SetResult(exerciseID: exercise.id, exerciseName: exercise.name, setNumber: 3, loadKg: 80, reps: 7, rir: 0, techniqueQuality: 2, feeling: .maximal)
        ]
        let result = SetResult(exerciseID: exercise.id, exerciseName: exercise.name, setNumber: 4, loadKg: 80, reps: 6, rir: 0, techniqueQuality: 2, feeling: .maximal)
        let readiness = ReadinessAssessment(score: 70, level: .moderate, summary: "测试", loadMultiplier: 0.95, setReduction: 1)

        let advice = TrainingEngine.recommendNextSet(
            prescription: exercise,
            result: result,
            readiness: readiness,
            increment: 2.5,
            exerciseHistory: prior + [result]
        )

        XCTAssertEqual(advice.suggestedRemainingSets, 1)
        XCTAssertEqual(advice.continuation, .continueTraining)
    }

    func testTechniqueAndFeelingDoNotChangeNextLoad() {
        let exercise = ExercisePrescription(name: "卧推", pattern: .horizontalPush, sets: 5, repLower: 6, repUpper: 10, targetRIR: 2, isPriority: true)
        let readiness = ReadinessAssessment(score: 80, level: .ready, summary: "测试", loadMultiplier: 1, setReduction: 0)
        let first = SetResult(exerciseID: exercise.id, exerciseName: exercise.name, setNumber: 2, loadKg: 80, reps: 8, rir: 1, techniqueQuality: 5, feeling: .easy)
        let second = SetResult(exerciseID: exercise.id, exerciseName: exercise.name, setNumber: 2, loadKg: 80, reps: 8, rir: 1, techniqueQuality: 1, feeling: .pain)

        let firstAdvice = TrainingEngine.recommendNextSet(prescription: exercise, result: first, readiness: readiness, increment: 2.5)
        let secondAdvice = TrainingEngine.recommendNextSet(prescription: exercise, result: second, readiness: readiness, increment: 2.5)

        XCTAssertEqual(firstAdvice.nextLoadKg, secondAdvice.nextLoadKg)
        XCTAssertEqual(firstAdvice.adjustment, secondAdvice.adjustment)
    }

    func testRestRecommendationExtendsForRIRZeroRepDropAndLowReadiness() {
        let exerciseID = UUID()
        let previous = SetResult(exerciseID: exerciseID, exerciseName: "卧推", setNumber: 3, loadKg: 80, reps: 10, rir: 2)
        let current = SetResult(exerciseID: exerciseID, exerciseName: "卧推", setNumber: 4, loadKg: 80, reps: 8, rir: 0)
        let readiness = ReadinessAssessment(score: 40, level: .low, summary: "测试", loadMultiplier: 0.9, setReduction: 1)

        let rest = TrainingEngine.recommendRest(
            current: current,
            previous: previous,
            setKind: .working,
            pattern: .horizontalPush,
            historicalE1RM: 100,
            readiness: readiness
        )

        XCTAssertEqual(rest.recommendedSeconds, 300)
        XCTAssertTrue(rest.reasons.contains("RIR 0，增加 60 秒"))
        XCTAssertTrue(rest.reasons.contains("次数较前组下降超过 10%，增加 30 秒"))
        XCTAssertTrue(rest.reasons.contains("今日恢复偏低，增加 30 秒"))
        XCTAssertTrue((rest.lowerSeconds...rest.upperSeconds).contains(rest.recommendedSeconds))
    }

    func testWarmupRestNeverUsesWorkingSetHeavyLoadRange() {
        let result = SetResult(exerciseID: UUID(), exerciseName: "深蹲", setNumber: 2, loadKg: 100, reps: 5, rir: 1)
        let readiness = ReadinessAssessment(score: 85, level: .ready, summary: "测试", loadMultiplier: 1, setReduction: 0)

        let rest = TrainingEngine.recommendRest(
            current: result,
            previous: nil,
            setKind: .warmup,
            pattern: .squat,
            historicalE1RM: 110,
            readiness: readiness
        )

        XCTAssertEqual(rest.lowerSeconds, 60)
        XCTAssertLessThanOrEqual(rest.upperSeconds, 180)
    }

    func testExerciseCatalogHasUniqueIDsAndNames() {
        let items = TrainingEngine.allExerciseOptions

        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        XCTAssertEqual(Set(items.map { $0.name.normalizedExerciseName }).count, items.count)
    }

    func testCatalogHasNoCombinedExercises() {
        XCTAssertFalse(TrainingEngine.allExerciseOptions.contains { $0.name.contains(" + ") })
    }

    func testLegacyAliasesResolveToSpecificCanonicalEquipment() {
        XCTAssertEqual(TrainingEngine.canonicalExercise(named: "蝴蝶机夹胸（肘垫）")?.name, "蝴蝶机夹胸")
        XCTAssertEqual(TrainingEngine.canonicalExercise(named: "器械推肩")?.equipment, .selectorizedMachine)
        XCTAssertEqual(TrainingEngine.canonicalExercise(named: "绳索夹胸")?.equipment, .cable)
    }

    func testWorkoutDraftRoundTripsProgress() throws {
        let exercise = ExercisePrescription(
            name: "杠铃卧推",
            pattern: .horizontalPush,
            sets: 5,
            repLower: 6,
            repUpper: 10,
            targetRIR: 2,
            isPriority: true,
            equipmentKind: .barbell
        )
        let session = TrainingSession(name: "胸部训练", focus: "胸", exercises: [exercise])
        let draft = WorkoutDraft(
            sourceSessionID: session.id,
            session: session,
            exerciseIndex: 0,
            setNumber: 4,
            warmupSetsByExercise: [exercise.id: 2],
            loadKg: 80,
            reps: 8,
            rir: 1,
            techniqueQuality: 4,
            hasPain: false
        )

        let restored = try JSONDecoder().decode(WorkoutDraft.self, from: JSONEncoder().encode(draft))

        XCTAssertEqual(restored, draft)
        XCTAssertEqual(restored.currentSetKind, .working)
        XCTAssertEqual(restored.workingSetOrdinal, 2)
        XCTAssertEqual(restored.totalWorkingSets, 3)
    }

    func testLegacySetWithoutKindResolvesAsWorking() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","exerciseID":"00000000-0000-0000-0000-000000000002","exerciseName":"卧推","setNumber":1,"loadKg":60,"reps":8,"rir":2,"completedAt":"2026-07-21T10:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let result = try decoder.decode(SetResult.self, from: Data(json.utf8))

        XCTAssertEqual(result.resolvedSetKind, .working)
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
