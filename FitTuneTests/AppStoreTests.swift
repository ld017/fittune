import XCTest
@testable import FitTune

@MainActor
final class AppStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "FitTuneTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testPauseTimeIsExcludedAndRealSessionRPEIsSaved() throws {
        let store = makeStrengthStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.startCurrentDraftSet(at: start)
        store.completeCurrentDraftSet(at: start.addingTimeInterval(30))
        store.pauseWorkout(at: start.addingTimeInterval(60))
        store.resumeWorkout(at: start.addingTimeInterval(660))
        store.setWorkoutSessionRPE(8)

        let record = try XCTUnwrap(store.saveActiveWorkout(
            status: .partial,
            at: start.addingTimeInterval(1_200)
        ))

        XCTAssertEqual(record.sessionRPE, 8)
        XCTAssertEqual(record.pauseIntervals?.first?.durationSeconds, 600)
    }

    private func makeStrengthStore() -> AppStore {
        let suite = "FitTuneTests.StrengthTimeline.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AppStore(defaults: defaults)
        let exercise = ExercisePrescription(
            name: "杠铃深蹲",
            pattern: .squat,
            sets: 3,
            repLower: 5,
            repUpper: 8,
            targetRIR: 1,
            isPriority: true,
            workingSets: 3
        )
        store.startWorkout(TrainingSession(name: "腿", focus: "股四头", exercises: [exercise]))
        return store
    }

    func testDraftPersistsAcrossStoreRecreation() {
        let defaults = makeDefaults()
        let store = AppStore(defaults: defaults)
        let exercise = ExercisePrescription(
            name: "卧推",
            pattern: .horizontalPush,
            sets: 5,
            repLower: 6,
            repUpper: 10,
            targetRIR: 2,
            isPriority: true
        )
        store.startWorkout(TrainingSession(name: "胸", focus: "胸", exercises: [exercise]))
        store.updateWorkoutDraft {
            $0.setNumber = 4
            $0.loadKg = 82.5
            $0.rir = 1
        }

        let restored = AppStore(defaults: defaults)

        XCTAssertEqual(restored.activeWorkoutDraft?.setNumber, 4)
        XCTAssertEqual(restored.activeWorkoutDraft?.loadKg, 82.5)
        XCTAssertEqual(restored.activeWorkoutDraft?.rir, 1)
    }

    func testWarmupSetsDefaultToRIRFiveThenWorkingSetDefaultsToZero() {
        let store = AppStore(defaults: makeDefaults())
        let exercise = ExercisePrescription(name: "深蹲", pattern: .squat, sets: 4, repLower: 5, repUpper: 8, targetRIR: 0, isPriority: true)
        store.startWorkout(TrainingSession(name: "腿", focus: "腿", exercises: [exercise]))
        store.updateWorkoutDraft { $0.loadKg = 100 }

        store.setDraftWarmupSets(2)
        XCTAssertEqual(store.activeWorkoutDraft?.currentSetKind, .warmup)
        XCTAssertEqual(store.activeWorkoutDraft?.rir, 5)
        let firstWarmupLoad = store.activeWorkoutDraft?.loadKg ?? 0
        XCTAssertLessThan(firstWarmupLoad, 100)

        store.completeCurrentDraftSet()
        store.advanceDraftToNextSet()
        XCTAssertEqual(store.activeWorkoutDraft?.currentSetKind, .warmup)
        XCTAssertEqual(store.activeWorkoutDraft?.rir, 5)
        let secondWarmupLoad = store.activeWorkoutDraft?.loadKg ?? 0
        XCTAssertGreaterThan(secondWarmupLoad, firstWarmupLoad)
        XCTAssertLessThan(secondWarmupLoad, 100)

        store.completeCurrentDraftSet()
        store.advanceDraftToNextSet()
        XCTAssertEqual(store.activeWorkoutDraft?.currentSetKind, .working)
        XCTAssertEqual(store.activeWorkoutDraft?.rir, 0)
        XCTAssertEqual(store.activeWorkoutDraft?.loadKg, 100)
    }

    func testNewWorkoutKeepsFourWorkingSetsSeparateFromWarmups() {
        let store = AppStore(defaults: makeDefaults())
        let exercise = ExercisePrescription(
            name: "深蹲",
            pattern: .squat,
            sets: 4,
            repLower: 5,
            repUpper: 8,
            targetRIR: 0,
            isPriority: true,
            workingSets: 4
        )
        store.startWorkout(TrainingSession(name: "腿", focus: "腿", exercises: [exercise]))
        store.setDraftWarmupSets(2)

        XCTAssertEqual(store.activeWorkoutDraft?.currentWarmupSets, 2)
        XCTAssertEqual(store.activeWorkoutDraft?.totalWorkingSets, 4)
        XCTAssertEqual(store.activeWorkoutDraft?.totalPlannedSets, 6)
    }

    func testEditingWorkingSetsDoesNotConsumeWarmupSets() {
        let store = AppStore(defaults: makeDefaults())
        let exercise = ExercisePrescription(
            name: "卧推",
            pattern: .horizontalPush,
            sets: 4,
            repLower: 6,
            repUpper: 10,
            targetRIR: 0,
            isPriority: true,
            workingSets: 4
        )
        store.startWorkout(TrainingSession(name: "胸", focus: "胸", exercises: [exercise]))
        store.setDraftWarmupSets(2)
        store.setDraftPlannedSets(5)

        XCTAssertEqual(store.activeWorkoutDraft?.totalWorkingSets, 5)
        XCTAssertEqual(store.activeWorkoutDraft?.totalPlannedSets, 7)
    }

    func testLegacyDraftWithoutSeparateWarmupFlagKeepsLegacyTotalSetMeaning() throws {
        let exercise = ExercisePrescription(name: "卧推", pattern: .horizontalPush, sets: 4, repLower: 6, repUpper: 10, targetRIR: 0, isPriority: true)
        var draft = WorkoutDraft(
            sourceSessionID: UUID(),
            session: TrainingSession(name: "胸", focus: "胸", exercises: [exercise]),
            exerciseIndex: 0,
            setNumber: 1,
            loadKg: 60,
            reps: 8,
            rir: 0,
            techniqueQuality: 4,
            hasPain: false
        )
        draft.warmupSetsByExercise[exercise.id] = 2
        let encoded = try JSONEncoder().encode(draft)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "usesSeparateWarmups")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(WorkoutDraft.self, from: legacyData)

        XCTAssertEqual(restored.totalPlannedSets, 4)
        XCTAssertEqual(restored.totalWorkingSets, 2)
    }

    func testSetKindCanRepresentBackoffDropAndAMRAPWithoutChangingPlannedSets() {
        let store = AppStore(defaults: makeDefaults())
        let exercise = ExercisePrescription(name: "卧推", pattern: .horizontalPush, sets: 3, repLower: 6, repUpper: 10, targetRIR: 0, isPriority: true)
        store.startWorkout(TrainingSession(name: "胸", focus: "胸", exercises: [exercise]))

        store.setDraftCurrentSetKind(.backoff)
        XCTAssertEqual(store.activeWorkoutDraft?.currentSetKind, .backoff)
        XCTAssertEqual(store.activeWorkoutDraft?.session.exercises[0].sets, 3)
        store.setDraftCurrentSetKind(.drop)
        XCTAssertEqual(store.activeWorkoutDraft?.currentSetKind, .drop)
        store.setDraftCurrentSetKind(.amrap)
        XCTAssertEqual(store.activeWorkoutDraft?.currentSetKind, .amrap)
    }

    func testPermanentWorkoutDeletionCannotBeRestored() {
        let store = AppStore(defaults: makeDefaults())
        let record = WorkoutRecord(
            sessionName: "胸",
            startedAt: .now,
            completedAt: .now,
            readinessScore: 80,
            sets: []
        )
        store.workoutHistory = [record]
        store.deleteWorkout(id: record.id)

        store.permanentlyDeleteWorkout(id: record.id)
        store.restoreWorkout(id: record.id)

        XCTAssertFalse(store.deletedWorkoutHistory.contains { $0.id == record.id })
        XCTAssertFalse(store.workoutHistory.contains { $0.id == record.id })
    }

    func testEmptyTrashRemovesAllDeletedObjectKinds() {
        let store = AppStore(defaults: makeDefaults())
        let workout = WorkoutRecord(sessionName: "腿", startedAt: .now, completedAt: .now, readinessScore: 70, sets: [])
        let cardio = CardioWorkoutRecord(date: .now, modality: .running, intensity: .zone2, durationMinutes: 20, activeEnergyKcal: 150, source: "手动")
        let weight = WeightEntry(date: .now, kilograms: 70, source: "手动")
        store.deletedWorkoutHistory = [workout]
        store.deletedCardioWorkouts = [cardio]
        store.deletedWeightHistory = [weight]

        store.emptyTrash()

        XCTAssertEqual(store.deletedRecordCount, 0)
    }

    func testFourthOfFiveAtRIRZeroKeepsFifthAvailable() {
        let store = AppStore(defaults: makeDefaults())
        let exercise = ExercisePrescription(
            name: "卧推",
            pattern: .horizontalPush,
            sets: 5,
            repLower: 6,
            repUpper: 10,
            targetRIR: 2,
            isPriority: true
        )
        store.startWorkout(TrainingSession(name: "胸", focus: "胸", exercises: [exercise]))
        store.updateWorkoutDraft {
            $0.setNumber = 4
            $0.warmupSetsByExercise[exercise.id] = 2
            $0.loadKg = 80
            $0.reps = 8
            $0.rir = 0
        }

        store.completeCurrentDraftSet()

        XCTAssertEqual(store.activeWorkoutDraft?.setNumber, 4)
        XCTAssertEqual(store.activeWorkoutDraft?.phase, .resting)
        XCTAssertEqual(store.activeWorkoutDraft?.session.exercises[0].sets, 5)
        XCTAssertEqual(store.activeWorkoutDraft?.results.last?.resolvedSetKind, .working)

        store.advanceDraftToNextSet()

        XCTAssertEqual(store.activeWorkoutDraft?.setNumber, 5)
        XCTAssertEqual(store.activeWorkoutDraft?.phase, .training)
    }

    func testSuggestedNextLoadCanBeOverriddenAndPersists() {
        let defaults = makeDefaults()
        let store = AppStore(defaults: defaults)
        let exercise = ExercisePrescription(name: "深蹲", pattern: .squat, sets: 3, repLower: 5, repUpper: 8, targetRIR: 2, isPriority: true)
        store.startWorkout(TrainingSession(name: "腿", focus: "腿", exercises: [exercise]))
        store.updateWorkoutDraft { $0.loadKg = 100; $0.reps = 8; $0.rir = 4 }
        store.completeCurrentDraftSet()
        store.advanceDraftToNextSet()
        store.updateWorkoutDraft { $0.loadKg = 107.5; $0.userOverrodeSuggestedLoad = true }

        let restored = AppStore(defaults: defaults)

        XCTAssertEqual(restored.activeWorkoutDraft?.loadKg, 107.5)
        XCTAssertEqual(restored.activeWorkoutDraft?.userOverrodeSuggestedLoad, true)
    }

    func testIncreasingPlannedSetsAfterCompletionReopensUserSet() {
        let store = AppStore(defaults: makeDefaults())
        let exercise = ExercisePrescription(name: "弯举", pattern: .arms, sets: 1, repLower: 8, repUpper: 12, targetRIR: 2, isPriority: false)
        store.startWorkout(TrainingSession(name: "手臂", focus: "手臂", exercises: [exercise]))
        store.completeCurrentDraftSet()
        XCTAssertEqual(store.activeWorkoutDraft?.phase, .exerciseComplete)

        store.setDraftPlannedSets(2)

        XCTAssertEqual(store.activeWorkoutDraft?.session.exercises[0].sets, 2)
        XCTAssertEqual(store.activeWorkoutDraft?.setNumber, 2)
        XCTAssertEqual(store.activeWorkoutDraft?.phase, .training)
    }

    func testSavingPartialDraftCreatesHistoryAndClearsDraft() {
        let store = AppStore(defaults: makeDefaults())
        let exercise = ExercisePrescription(name: "划船", pattern: .horizontalPull, sets: 3, repLower: 8, repUpper: 12, targetRIR: 2, isPriority: true)
        store.startWorkout(TrainingSession(name: "背", focus: "背", exercises: [exercise]))
        store.completeCurrentDraftSet()

        let record = store.saveActiveWorkout(status: .partial)

        XCTAssertEqual(record?.resolvedCompletionStatus, .partial)
        XCTAssertEqual(record?.sets.count, 1)
        XCTAssertNil(store.activeWorkoutDraft)
        XCTAssertEqual(store.workoutHistory.first?.id, record?.id)
    }

    func testV06SnapshotRestoresAllRecordKindsAndPersistsCurrentSchema() throws {
        let defaults = makeDefaults()
        defaults.set(try V06SnapshotFixture.data(), forKey: "FitTune.snapshot.v1")

        let store = AppStore(defaults: defaults)

        XCTAssertEqual(store.workoutHistory.first?.id, V06SnapshotFixture.completedWorkoutID)
        XCTAssertEqual(store.cardioWorkouts.first?.durationMinutes, 30)
        XCTAssertEqual(store.weightHistory.first?.kilograms, 75)
        XCTAssertEqual(store.deletedWorkoutHistory.first?.id, V06SnapshotFixture.deletedWorkoutID)
        XCTAssertEqual(store.activeWorkoutDraft?.id, V06SnapshotFixture.draftID)
        XCTAssertEqual(store.activeWorkoutDraft?.setNumber, 2)
        XCTAssertEqual(store.activeWorkoutDraft?.results.count, 1)

        let migratedData = try XCTUnwrap(defaults.data(forKey: "FitTune.snapshot.v1"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let migrated = try decoder.decode(AppSnapshot.self, from: migratedData)
        XCTAssertEqual(migrated.resolvedSchemaVersion, AppSnapshot.currentSchemaVersion)
    }

    func testSchemaTwelveMigrationUpdatesEditablePlanButPreservesHistoricalRuleVersion() throws {
        let defaults = makeDefaults()
        let exercise = ExercisePrescription(
            name: "卧推",
            pattern: .horizontalPush,
            sets: 2,
            repLower: 6,
            repUpper: 10,
            targetRIR: 0,
            isPriority: true
        )
        let session = TrainingSession(name: "胸", focus: "胸", exercises: [exercise])
        let plan = TrainingPlan(
            title: "旧计划",
            rationale: "迁移测试",
            sessions: [session],
            generatedAt: .now,
            ruleVersion: "0.6-resumable-user-controlled-rest"
        )
        let historicalRuleVersion = "0.6-history-snapshot"
        let historicalSnapshot = PlanSnapshot(
            sourcePlanRuleVersion: historicalRuleVersion,
            sourceSessionID: session.id,
            planTitle: plan.title,
            sessionName: session.name,
            goal: .hypertrophy,
            split: .chestBackShouldersLegs,
            equipment: .fullGym,
            exercises: [exercise]
        )
        var record = WorkoutRecord(
            sessionName: session.name,
            startedAt: .now,
            completedAt: .now,
            readinessScore: 80,
            sets: []
        )
        record.planSnapshot = historicalSnapshot
        let snapshot = AppSnapshot(
            profile: nil,
            plan: plan,
            readiness: ReadinessInput(),
            workoutHistory: [record],
            weightHistory: [],
            schemaVersion: 12
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode(snapshot), forKey: "FitTune.snapshot.v1")

        let restored = AppStore(defaults: defaults)

        XCTAssertEqual(restored.plan?.ruleVersion, TrainingEngine.ruleVersion)
        XCTAssertEqual(restored.plan?.sessions[0].exercises[0].phase, .primary)
        XCTAssertEqual(restored.plan?.sessions[0].exercises[0].resolvedWorkingSets, 4)
        XCTAssertEqual(restored.workoutHistory[0].planSnapshot?.exercises[0].sets, 2)
        XCTAssertEqual(restored.workoutHistory[0].planSnapshot?.sourcePlanRuleVersion, historicalRuleVersion)
        XCTAssertNil(restored.workoutHistory[0].planSnapshot?.exercises[0].phase)
    }

    func testLegacyFavoriteIdentifierMigratesToCanonicalCatalogIdentifier() throws {
        let defaults = makeDefaults()
        let legacyID = "chest.selectorizedMachine.chestIsolation.蝴蝶机夹胸"
        let snapshot = AppSnapshot(
            profile: nil,
            plan: nil,
            readiness: ReadinessInput(),
            workoutHistory: [],
            weightHistory: [],
            favoriteExerciseIDs: [legacyID],
            schemaVersion: 12
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode(snapshot), forKey: "FitTune.snapshot.v1")

        let restored = AppStore(defaults: defaults)
        let canonical = try XCTUnwrap(ExerciseCatalog.resolve(idOrAlias: legacyID))

        XCTAssertEqual(restored.favoriteExerciseIDs, [canonical.id])
    }

    func testRecoveryCheckInAndSafetySettingsPersistAcrossStoreRecreation() {
        let defaults = makeDefaults()
        let store = AppStore(defaults: defaults)
        let checkIn = RecoveryCheckIn(
            date: Date(timeIntervalSince1970: 1_721_563_200),
            sleep: RecoveryDimensionValue(manualValue: 80, resolvedValue: 80, provenance: .manual),
            soreness: RecoveryDimensionValue(manualValue: 20, resolvedValue: 20, provenance: .manual),
            stress: RecoveryDimensionValue(manualValue: 35, resolvedValue: 35, provenance: .manual),
            motivation: RecoveryDimensionValue(manualValue: 90, resolvedValue: 90, provenance: .manual)
        )
        let safety = PersonalSafetySettings(
            avoidedRegions: [.shoulders],
            disabledExerciseIDs: ["dumbbell-front-raise"],
            painAlertThreshold: 2,
            maximumHeartRateAlert: 185
        )

        store.updateRecoveryCheckIn(checkIn)
        store.updateSafetySettings(safety)
        let restored = AppStore(defaults: defaults)

        XCTAssertEqual(restored.recoveryCheckIns, [checkIn])
        XCTAssertEqual(restored.safetySettings, safety)
    }

    func testRestingHeartRateSamplesPersistAndUpdateRecoveryAssessment() {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 2_000_000)
        let store = AppStore(defaults: defaults)
        store.updateRecoveryCheckIn(RecoveryCheckIn(
            date: now,
            sleep: .init(manualValue: 3, provenance: .manual),
            soreness: .init(manualValue: 3, provenance: .manual),
            stress: .init(manualValue: 3, provenance: .manual),
            motivation: .init(manualValue: 3, provenance: .manual)
        ))
        for day in 1...7 {
            store.importRestingHeartRate(.init(
                date: now.addingTimeInterval(Double(-day * 86_400)),
                bpm: 60,
                source: .appleHealth,
                sourceName: "健康",
                externalID: "baseline-\(day)"
            ))
        }
        store.importRestingHeartRate(.init(date: now, bpm: 70, source: .appleHealth, sourceName: "健康", externalID: "today"))
        store.importRestingHeartRate(.init(date: now, bpm: 70, source: .appleHealth, sourceName: "健康", externalID: "today"))

        let restored = AppStore(defaults: defaults)

        XCTAssertEqual(restored.restingHeartRateSamples.count, 8)
        XCTAssertEqual(restored.currentRecoveryAssessment?.restingHeartRateAdjustment, -10)
        XCTAssertEqual(restored.readinessAssessment.score, restored.currentRecoveryAssessment?.score)
    }

    func testClearingImportedHealthDataKeepsManualRecoveryAndWorkoutRecords() {
        let defaults = makeDefaults()
        let store = AppStore(defaults: defaults)
        let manual = RecoveryCheckIn(
            date: .now,
            sleep: .init(manualValue: 4, provenance: .manual),
            soreness: .init(manualValue: 3, provenance: .manual),
            stress: .init(manualValue: 3, provenance: .manual),
            motivation: .init(manualValue: 4, provenance: .manual)
        )
        store.updateRecoveryCheckIn(manual)
        store.importRestingHeartRate(.init(date: .now, bpm: 61, source: .appleHealth, sourceName: "健康", externalID: "rhr-1"))
        store.workoutHistory = [WorkoutRecord(sessionName: "胸", startedAt: .now, completedAt: .now, readinessScore: 80, sets: [])]

        store.clearImportedHealthData()
        let restored = AppStore(defaults: defaults)

        XCTAssertTrue(restored.restingHeartRateSamples.isEmpty)
        XCTAssertEqual(restored.recoveryCheckIns.map(\.id), [manual.id])
        XCTAssertEqual(restored.recoveryCheckIns.first?.sleep.manualValue, 4)
        XCTAssertEqual(restored.recoveryCheckIns.first?.sleep.provenance, .manual)
        XCTAssertEqual(restored.workoutHistory.count, 1)
    }

    func testLiveHeartRateWithoutPersonalHistoryLeavesRestUnchanged() {
        let store = AppStore(defaults: makeDefaults())
        store.finishOnboarding(with: testProfile(goal: .hypertrophy, split: .fullBody))
        let session = store.plan!.sessions[0]
        store.startWorkout(session)
        let start = Date(timeIntervalSince1970: 5_000_000)
        store.updateWorkoutDraft {
            $0.loadKg = 100
            $0.reps = 8
            $0.rir = 1
        }
        store.startCurrentDraftSet(at: start)
        store.completeCurrentDraftSet(at: start.addingTimeInterval(30))
        let baselineRest = store.activeWorkoutDraft!.restRecommendation!.recommendedSeconds
        let provenance = MetricProvenance(source: .bluetooth, sourceName: "H10", confidence: .measured, coverage: 1)
        store.appendLiveMetricSample(.init(timestamp: start.addingTimeInterval(30), heartRateBPM: 170, provenance: provenance), validity: .valid, now: start.addingTimeInterval(30))
        store.appendLiveMetricSample(.init(timestamp: start.addingTimeInterval(90), heartRateBPM: 162, provenance: provenance), validity: .valid, now: start.addingTimeInterval(90))
        let firstUpdate = store.activeWorkoutDraft!.restRecommendation!.recommendedSeconds

        XCTAssertEqual(firstUpdate, baselineRest)
        XCTAssertEqual(store.activeWorkoutDraft!.restRecommendation!.recommendedSeconds, firstUpdate)
        XCTAssertEqual(store.activeWorkoutDraft!.metricSamples?.count, 2)
        XCTAssertEqual(store.activeWorkoutDraft!.results.last?.heartRateResponse?.hrr60, 8)
    }

    func testSummaryRevisionAppendPreservesOriginalSets() {
        let store = AppStore(defaults: makeDefaults())
        let exerciseID = UUID()
        let originalSet = SetResult(exerciseID: exerciseID, exerciseName: "卧推", setNumber: 1, loadKg: 80, reps: 8, rir: 0)
        let record = WorkoutRecord(sessionName: "胸", startedAt: .now, completedAt: .now, readinessScore: 80, sets: [originalSet])
        store.workoutHistory = [record]
        let provenance = MetricProvenance(source: .huaweiHealth, sourceName: "华为健康", confidence: .measured, coverage: 0.85)
        let revision = SummaryRevision(
            reason: "华为健康事后同步",
            summary: WorkoutSummary(
                generatedAt: .now,
                algorithmVersion: "1.0.0",
                activeEnergyKcal: MetricRange(value: 280, lowerBound: 260, upperBound: 300, provenance: provenance)
            )
        )

        store.appendSummaryRevision(revision, toWorkoutID: record.id)

        XCTAssertEqual(store.workoutHistory[0].sets, [originalSet])
        XCTAssertEqual(store.workoutHistory[0].summaryRevisions?.last?.reason, "华为健康事后同步")
    }

    func testDraftV1ContextPersistsAcrossStoreRecreation() {
        let defaults = makeDefaults()
        let store = AppStore(defaults: defaults)
        let exercise = ExercisePrescription(name: "卧推", pattern: .horizontalPush, sets: 3, repLower: 6, repUpper: 10, targetRIR: 0, isPriority: true)
        let session = TrainingSession(name: "胸", focus: "胸", exercises: [exercise])
        store.startWorkout(session)
        let provenance = MetricProvenance(source: .phoneEstimate, sourceName: "iPhone 估算", confidence: .estimated, coverage: 0.5)
        store.updateWorkoutDraft {
            $0.planSnapshot = PlanSnapshot(
                sourcePlanRuleVersion: "1.0",
                sourceSessionID: session.id,
                planTitle: "四分化",
                sessionName: session.name,
                goal: .hypertrophy,
                split: .chestBackShouldersLegs,
                equipment: .fullGym,
                exercises: session.exercises
            )
            $0.changeEvents = [WorkoutChangeEvent(kind: .exerciseAdded, exerciseName: "卧推", detail: "测试")]
            $0.metricSamples = [WorkoutMetricSample(timestamp: .now, heartRateBPM: 130, provenance: provenance)]
        }

        let restored = AppStore(defaults: defaults)

        XCTAssertEqual(restored.activeWorkoutDraft?.planSnapshot?.sessionName, "胸")
        XCTAssertEqual(restored.activeWorkoutDraft?.changeEvents?.count, 1)
        XCTAssertEqual(restored.activeWorkoutDraft?.metricSamples?.first?.heartRateBPM, 130)
    }

    func testFavoritesAndCustomExercisesPersistAndDeletingCustomKeepsHistory() {
        let defaults = makeDefaults()
        let store = AppStore(defaults: defaults)
        let custom = ExerciseOption(
            name: "我的绳索弯举",
            pattern: .arms,
            equipment: .cable,
            category: .arms,
            subcategory: .biceps,
            stableID: "custom.cable.curl",
            replacementIDs: ["arms.cable.arms.绳索弯举"],
            source: .custom
        )
        store.saveCustomExercise(custom)
        store.toggleFavoriteExercise(custom.id)
        let historicalSet = SetResult(exerciseID: UUID(), exerciseName: custom.name, setNumber: 1, loadKg: 20, reps: 10, rir: 0)
        store.workoutHistory = [WorkoutRecord(sessionName: "手臂", startedAt: .now, completedAt: .now, readinessScore: 80, sets: [historicalSet])]
        store.deleteCustomExercise(id: custom.id)

        let restored = AppStore(defaults: defaults)

        XCTAssertTrue(restored.customExercises.isEmpty)
        XCTAssertFalse(restored.favoriteExerciseIDs.contains(custom.id))
        XCTAssertEqual(restored.workoutHistory.first?.sets.first?.exerciseName, "我的绳索弯举")
    }

    func testStartedWorkoutKeepsImmutablePlanSnapshotAfterRegeneration() throws {
        let store = AppStore(defaults: makeDefaults())
        let originalProfile = testProfile(goal: .hypertrophy, split: .chestBackShouldersLegs)
        store.finishOnboarding(with: originalProfile)
        let session = try XCTUnwrap(store.plan?.sessions.first)

        store.startWorkout(session)
        let snapshot = try XCTUnwrap(store.activeWorkoutDraft?.planSnapshot)
        var changedProfile = originalProfile
        changedProfile.goal = .strength
        changedProfile.splitPreference = .pushPullLegs
        store.updateProfileAndRegenerate(changedProfile)

        XCTAssertEqual(store.activeWorkoutDraft?.planSnapshot, snapshot)
        XCTAssertEqual(snapshot.goal, .hypertrophy)
        XCTAssertEqual(snapshot.split, .chestBackShouldersLegs)
    }

    func testWorkoutEditsAndMetricsAreCopiedIntoSavedHistory() throws {
        let store = AppStore(defaults: makeDefaults())
        store.finishOnboarding(with: testProfile(goal: .hypertrophy, split: .fullBody))
        let session = try XCTUnwrap(store.plan?.sessions.first)
        store.startWorkout(session)
        let added = try XCTUnwrap(TrainingEngine.canonicalExercise(named: "哑铃弯举"))
        store.addDraftExercise(added)
        let provenance = MetricProvenance(source: .phoneEstimate, sourceName: "iPhone 估算", confidence: .estimated, coverage: 0.5)
        store.updateWorkoutDraft {
            $0.metricSamples = [WorkoutMetricSample(timestamp: .now, heartRateBPM: 135, provenance: provenance)]
        }
        store.completeCurrentDraftSet()

        let record = try XCTUnwrap(store.saveActiveWorkout(status: .partial))

        XCTAssertNotNil(record.planSnapshot)
        XCTAssertEqual(record.changeEvents?.last?.kind, .exerciseAdded)
        XCTAssertEqual(record.metricSamples?.first?.heartRateBPM, 135)
    }

    func testStrengthSaveKeepsLatestAppleWatchCumulativeEnergyAsComparison() throws {
        let store = AppStore(defaults: makeDefaults())
        let exercise = ExercisePrescription(
            name: "卧推",
            pattern: .horizontalPush,
            sets: 1,
            repLower: 8,
            repUpper: 10,
            targetRIR: 1,
            isPriority: true
        )
        store.startWorkout(TrainingSession(name: "胸", focus: "胸", exercises: [exercise]))
        store.updateWorkoutDraft { $0.measuredActiveEnergyKcal = 999 }
        store.completeCurrentDraftSet()
        let source = MetricProvenance(
            source: .appleWatch,
            sourceName: "Apple Watch",
            confidence: .measured,
            coverage: 1
        )
        store.appendLiveMetricSample(
            .init(timestamp: .now, heartRateBPM: 130, activeEnergyKcal: 120, provenance: source),
            validity: .valid
        )
        store.appendLiveMetricSample(
            .init(timestamp: .now, heartRateBPM: 132, activeEnergyKcal: 210, provenance: source),
            validity: .valid
        )

        let record = try XCTUnwrap(store.saveActiveWorkout(status: .completed))

        XCTAssertEqual(record.deviceActiveEnergyEstimateKcal, 210)
        XCTAssertNil(record.measuredActiveEnergyKcal)
        XCTAssertNotEqual(record.activeEnergyKcal, 210)
        XCTAssertEqual(record.energyMethod, "2024 Adult Compendium 力量训练结构模型")
        XCTAssertEqual(record.energyDiagnostics?.comparisonEstimateKcal, 210)
        XCTAssertEqual(record.energyAlgorithmVersion, EnergyEngine.algorithmVersion)
    }

    func testCardioSaveKeepsAppleWatchCumulativeEnergyAsComparison() throws {
        let store = AppStore(defaults: makeDefaults())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.startCardioSession(modality: .cycling, intensity: .zone2)
        store.activeCardioDraft?.startedAt = start
        let source = MetricProvenance(
            source: .appleWatch,
            sourceName: "Apple Watch",
            confidence: .measured,
            coverage: 1
        )
        store.appendCardioMetricSample(
            .init(timestamp: start, heartRateBPM: 130, activeEnergyKcal: 80, provenance: source)
        )
        store.appendCardioMetricSample(
            .init(timestamp: start.addingTimeInterval(1_800), heartRateBPM: 140, activeEnergyKcal: 190, provenance: source)
        )

        let record = try XCTUnwrap(
            store.finishCardioSession(
                status: .completed,
                at: start.addingTimeInterval(1_800)
            )
        )

        XCTAssertEqual(record.activeEnergyKcal, 213.15, accuracy: 0.01)
        XCTAssertTrue(record.energyMethod?.contains("MET") == true)
        XCTAssertTrue(record.source.contains("Apple Watch"))
        XCTAssertEqual(record.energyAlgorithmVersion, EnergyEngine.algorithmVersion)
    }

    func testFinishedCardioUsesProfileRestingHeartRateForHRRSummary() throws {
        let store = AppStore(defaults: makeDefaults())
        var profile = testProfile(goal: .generalFitness, split: .fullBody)
        profile.restingHeartRate = 60
        profile.measuredMaxHeartRate = 180
        store.finishOnboarding(with: profile)

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "H10",
            confidence: .measured,
            coverage: 1
        )
        store.startCardioSession(modality: .cycling, intensity: .zone2, at: start)
        for seconds in stride(from: 0.0, through: 60.0, by: 10) {
            store.appendCardioMetricSample(
                .init(
                    timestamp: start.addingTimeInterval(seconds),
                    heartRateBPM: 125,
                    provenance: source
                )
            )
        }

        let record = try XCTUnwrap(store.finishCardioSession(
            status: .completed,
            at: start.addingTimeInterval(60)
        ))

        XCTAssertEqual(record.summary?.cardio?.usedHeartRateReserve, true)
        XCTAssertEqual(record.summary?.cardio?.intensityConfidence, .derived)
        XCTAssertGreaterThan(record.summary?.cardio?.aerobicBaseMinutes ?? 0, 0)
        XCTAssertEqual(record.summary?.cardio?.vigorousMinutes, 0)
    }

    func testFinishedCardioUsesConfirmedDistanceAndKeepsDeviceEnergyAsComparison() throws {
        let store = configuredStore(weightKg: 70)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.startCardioSession(
            modality: .inclineWalking,
            intensity: .zone2,
            speedKph: 5,
            inclinePercent: 8,
            at: start
        )
        store.appendCardioMetricSample(watchEnergySample(kcal: 166, at: start))
        store.appendCardioMetricSample(
            .init(
                timestamp: start.addingTimeInterval(1_800),
                distanceMeters: 4_000,
                provenance: .init(source: .phoneSensor, sourceName: "iPhone", confidence: .measured, coverage: 1)
            )
        )
        store.setConfirmedCardioDistance(meters: 5_000)

        let record = try XCTUnwrap(store.finishCardioSession(
            status: .completed,
            at: start.addingTimeInterval(3_600)
        ))

        XCTAssertEqual(record.activeEnergyKcal, 427, accuracy: 1)
        XCTAssertEqual(record.energyDiagnostics?.comparisonEstimateKcal, 166)
        XCTAssertEqual(record.distanceKm, 5)
        XCTAssertEqual(record.confirmedDistanceMeters, 5_000)
        XCTAssertEqual(record.sensorDistanceMeters, 4_000)
        XCTAssertEqual(record.workloadSegments?.first?.endedAt, start.addingTimeInterval(3_600))
    }

    func testStrengthSaveCalculatesEnergyAfterAttachingHeartRateSeries() throws {
        let store = AppStore(defaults: makeDefaults())
        var user = testProfile(goal: .hypertrophy, split: .fullBody)
        user.ageYears = 30
        user.biologicalSex = .female
        store.finishOnboarding(with: user)
        let exercise = ExercisePrescription(
            name: "卧推",
            pattern: .horizontalPush,
            sets: 1,
            repLower: 8,
            repUpper: 10,
            targetRIR: 1,
            isPriority: true
        )
        store.startWorkout(TrainingSession(name: "胸", focus: "胸", exercises: [exercise]))
        let start = Date.now.addingTimeInterval(-3_600)
        store.updateWorkoutDraft { $0.startedAt = start }
        store.completeCurrentDraftSet()
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "FIT 3",
            confidence: .measured,
            coverage: 1
        )
        store.appendLiveMetricSample(
            .init(timestamp: start, heartRateBPM: 70, provenance: source),
            validity: .valid
        )
        store.appendLiveMetricSample(
            .init(timestamp: start.addingTimeInterval(5), heartRateBPM: 70, provenance: source),
            validity: .valid
        )

        let record = try XCTUnwrap(store.saveActiveWorkout(status: .completed))

        XCTAssertEqual(record.energyMethod, "2024 Adult Compendium 力量训练结构模型")
        XCTAssertEqual(record.energyAlgorithmVersion, EnergyEngine.algorithmVersion)
    }

    func testCurrentStrengthEnergyRecordRecalculatesWithoutMutatingInput() {
        let store = AppStore(defaults: makeDefaults())
        var user = testProfile(goal: .hypertrophy, split: .fullBody)
        user.ageYears = 30
        user.biologicalSex = .female
        store.finishOnboarding(with: user)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "FIT 3",
            confidence: .measured,
            coverage: 1
        )
        let samples = stride(from: 0.0, through: 3_600.0, by: 5.0).map {
            WorkoutMetricSample(
                timestamp: start.addingTimeInterval($0),
                heartRateBPM: 70,
                provenance: source
            )
        }
        let oldRecord = WorkoutRecord(
            sessionName: "力量",
            startedAt: start,
            completedAt: start.addingTimeInterval(3_600),
            readinessScore: 80,
            sets: [],
            activeEnergyKcal: 5,
            sessionRPE: 7,
            averageHeartRate: 70,
            energyMethod: "Keytel 心率模型（力量训练修正区间）",
            metricSamples: samples
        )

        let updated = store.currentEnergyRecord(oldRecord)

        XCTAssertGreaterThan(updated.activeEnergyKcal ?? 0, 100)
        XCTAssertEqual(oldRecord.activeEnergyKcal, 5)
        XCTAssertEqual(updated.energyMethod, "2024 Adult Compendium 力量训练结构模型")
    }

    func testCurrentStrengthEnergyRecordKeepsFinalizedMeasuredEnergyOverLiveCumulativeSample() {
        let store = AppStore(defaults: makeDefaults())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let watch = MetricProvenance(
            source: .appleWatch,
            sourceName: "Apple Watch",
            confidence: .measured,
            coverage: 1
        )
        let record = WorkoutRecord(
            sessionName: "力量",
            startedAt: start,
            completedAt: start.addingTimeInterval(3_600),
            readinessScore: 80,
            sets: [],
            activeEnergyKcal: 5,
            measuredActiveEnergyKcal: 192,
            energyMethod: "旧记录",
            metricSamples: [
                .init(
                    timestamp: start.addingTimeInterval(1_800),
                    activeEnergyKcal: 180,
                    provenance: watch
                )
            ]
        )

        let updated = store.currentEnergyRecord(record)

        XCTAssertEqual(updated.measuredActiveEnergyKcal, 192)
        XCTAssertNotEqual(updated.activeEnergyKcal, 192)
        XCTAssertEqual(updated.energyMethod, "2024 Adult Compendium 力量训练结构模型")
        XCTAssertEqual(updated.energyDiagnostics?.comparisonEstimateKcal, 192)
    }

    func testCurrentCardioEnergyRecordRecalculatesWithoutMutatingInput() {
        let store = AppStore(defaults: makeDefaults())
        var user = testProfile(goal: .generalFitness, split: .fullBody)
        user.ageYears = 30
        user.biologicalSex = .male
        store.finishOnboarding(with: user)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "FIT 3",
            confidence: .measured,
            coverage: 1
        )
        let samples = stride(from: 0.0, through: 1_800.0, by: 5.0).map {
            WorkoutMetricSample(
                timestamp: start.addingTimeInterval($0),
                heartRateBPM: 135,
                provenance: source
            )
        }
        let oldRecord = CardioWorkoutRecord(
            date: start,
            modality: .cycling,
            intensity: .zone2,
            durationMinutes: 30,
            averageHeartRate: 135,
            activeEnergyKcal: 5,
            source: "旧心率估算",
            energyMethod: "Keytel 平均心率模型",
            metricSamples: samples
        )

        let updated = store.currentEnergyRecord(oldRecord)

        XCTAssertNotEqual(updated.activeEnergyKcal, 5)
        XCTAssertEqual(oldRecord.activeEnergyKcal, 5)
        XCTAssertTrue(updated.energyMethod?.contains("Keytel") == true)
    }

    func testCurrentCardioEnergyRecordRecalculatesLegacyMechanicalEvidenceWithoutSamples() {
        let store = configuredStore(weightKg: 70)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let record = CardioWorkoutRecord(
            date: start,
            modality: .inclineWalking,
            intensity: .zone2,
            durationMinutes: 60,
            activeEnergyKcal: 100,
            source: "旧记录",
            speedKph: 5,
            inclinePercent: 8
        )

        let current = store.currentEnergyRecord(record)

        XCTAssertEqual(current.activeEnergyKcal, 427, accuracy: 1)
        XCTAssertEqual(current.energyAlgorithmVersion, EnergyEngine.algorithmVersion)
    }

    func testCurrentCardioEnergyRecordWithoutEvidenceRetainsSavedEnergyAndAddsLegacyWarning() {
        let store = AppStore(defaults: makeDefaults())
        let record = CardioWorkoutRecord(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            modality: .inclineWalking,
            intensity: .zone2,
            durationMinutes: 60,
            activeEnergyKcal: 100,
            source: "旧记录"
        )

        let current = store.currentEnergyRecord(record)

        XCTAssertEqual(current.activeEnergyKcal, 100)
        XCTAssertTrue(current.energyDiagnostics?.warnings.contains { $0.contains("历史") } == true)
    }

    func testCurrentCardioEnergyRecordWithOnlyDeviceEnergyRetainsSavedEnergyAndWarning() {
        let store = AppStore(defaults: makeDefaults())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let record = CardioWorkoutRecord(
            date: start,
            modality: .cycling,
            intensity: .zone2,
            durationMinutes: 30,
            activeEnergyKcal: 100,
            source: "旧记录",
            metricSamples: [watchEnergySample(kcal: 166, at: start)]
        )

        let current = store.currentEnergyRecord(record)

        XCTAssertEqual(current.activeEnergyKcal, 100)
        XCTAssertEqual(current.energyDiagnostics?.comparisonEstimateKcal, 166)
        XCTAssertTrue(current.energyDiagnostics?.warnings.contains { $0.contains("历史") } == true)
    }

    func testCurrentStrengthEnergyRecordKeepsSavedValueWithoutUsableHeartRate() {
        let store = AppStore(defaults: makeDefaults())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = MetricProvenance(
            source: .phoneSensor,
            sourceName: "iPhone",
            confidence: .measured,
            coverage: 1
        )
        let record = WorkoutRecord(
            sessionName: "力量",
            startedAt: start,
            completedAt: start.addingTimeInterval(3_600),
            readinessScore: 80,
            sets: [],
            activeEnergyKcal: 77,
            energyMethod: "旧记录",
            metricSamples: [
                .init(timestamp: start, cadence: 100, provenance: source)
            ]
        )

        let current = store.currentEnergyRecord(record)

        XCTAssertEqual(current.activeEnergyKcal, 77)
        XCTAssertEqual(current.energyMethod, "旧记录")
    }

    func testCurrentCardioEnergyRecordKeepsSavedValueForSparseHeartRate() {
        let store = AppStore(defaults: makeDefaults())
        var user = testProfile(goal: .generalFitness, split: .fullBody)
        user.ageYears = 30
        user.biologicalSex = .male
        store.finishOnboarding(with: user)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "FIT 3",
            confidence: .measured,
            coverage: 1
        )
        let record = CardioWorkoutRecord(
            date: start,
            modality: .cycling,
            intensity: .zone2,
            durationMinutes: 30,
            activeEnergyKcal: 77,
            source: "旧记录",
            energyMethod: "旧记录",
            metricSamples: [
                .init(timestamp: start, heartRateBPM: 130, provenance: source),
                .init(timestamp: start.addingTimeInterval(30), heartRateBPM: 132, provenance: source)
            ]
        )

        let current = store.currentEnergyRecord(record)

        XCTAssertEqual(current.activeEnergyKcal, 77)
        XCTAssertEqual(current.energyMethod, "旧记录")
    }

    func testCurrentAlgorithmRecordKeepsPersistedEnergyWithHeartRateCurve() {
        let store = AppStore(defaults: makeDefaults())
        var user = testProfile(goal: .hypertrophy, split: .fullBody)
        user.ageYears = 30
        user.biologicalSex = .female
        store.finishOnboarding(with: user)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "FIT 3",
            confidence: .measured,
            coverage: 1
        )
        let record = WorkoutRecord(
            sessionName: "力量",
            startedAt: start,
            completedAt: start.addingTimeInterval(3_600),
            readinessScore: 80,
            sets: [],
            activeEnergyKcal: 177,
            energyMethod: "FitTune 心率 + 力量模型估算",
            energyLowerBoundKcal: 120,
            energyUpperBoundKcal: 220,
            energyAlgorithmVersion: EnergyEngine.algorithmVersion,
            metricSamples: [
                .init(timestamp: start, heartRateBPM: 130, provenance: source),
                .init(timestamp: start.addingTimeInterval(5), heartRateBPM: 132, provenance: source)
            ]
        )

        let current = store.currentEnergyRecord(record)

        XCTAssertEqual(current.activeEnergyKcal, 177)
        XCTAssertEqual(current.energyLowerBoundKcal, 120)
        XCTAssertEqual(current.energyUpperBoundKcal, 220)
    }

    func testWearableStrengthMergeKeepsStructuralEnergyAndStoresDeviceComparison() throws {
        let store = AppStore(defaults: makeDefaults())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.workoutHistory = [
            WorkoutRecord(
                sessionName: "力量",
                startedAt: start,
                completedAt: start.addingTimeInterval(3_600),
                readinessScore: 80,
                sets: [],
                activeEnergyKcal: 160,
                energyMethod: "旧记录"
            )
        ]

        store.mergeWearableStrengthWorkout(
            WearableStrengthWorkout(
                date: start,
                durationMinutes: 60,
                activeEnergyKcal: 240,
                averageHeartRate: 135,
                externalID: "watch-workout"
            )
        )

        let merged = try XCTUnwrap(store.workoutHistory.first)
        XCTAssertNotEqual(merged.activeEnergyKcal, 240)
        XCTAssertEqual(merged.deviceActiveEnergyEstimateKcal, 240)
        XCTAssertEqual(merged.deviceEnergySource, .appleWatch)
        XCTAssertEqual(merged.energyDiagnostics?.comparisonEstimateKcal, 240)
        XCTAssertEqual(merged.energyAlgorithmVersion, EnergyEngine.algorithmVersion)
    }

    func testWearableStrengthMergeRegeneratesSummaryFromStructuralEnergy() throws {
        let store = AppStore(defaults: makeDefaults())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var record = WorkoutRecord(
            sessionName: "力量",
            startedAt: start,
            completedAt: start.addingTimeInterval(3_600),
            readinessScore: 80,
            sets: [],
            activeEnergyKcal: 160,
            energyMethod: "旧记录"
        )
        record.summary = SummaryEngine.strengthSummary(for: record, bodyWeightKg: 70)
        store.workoutHistory = [record]

        store.mergeWearableStrengthWorkout(
            WearableStrengthWorkout(
                date: start,
                durationMinutes: 60,
                activeEnergyKcal: 240,
                averageHeartRate: 135,
                externalID: "watch-workout"
            )
        )

        let merged = try XCTUnwrap(store.workoutHistory.first)
        XCTAssertEqual(merged.summary?.activeEnergyKcal?.value, merged.activeEnergyKcal)
        XCTAssertNotEqual(merged.summary?.activeEnergyKcal?.value, 240)
        XCTAssertNotEqual(merged.summary?.activeEnergyKcal?.provenance.confidence, .measured)
    }

    func testStrengthSavePreservesDraftRPEAndClosesOpenPause() throws {
        let store = AppStore(defaults: makeDefaults())
        let exercise = ExercisePrescription(
            name: "卧推",
            pattern: .horizontalPush,
            sets: 1,
            repLower: 8,
            repUpper: 10,
            targetRIR: 1,
            isPriority: true
        )
        store.startWorkout(TrainingSession(name: "胸", focus: "胸", exercises: [exercise]))
        let completedPauseStart = Date.now.addingTimeInterval(-1_200)
        let openPauseStart = Date.now.addingTimeInterval(-300)
        store.completeCurrentDraftSet(at: completedPauseStart.addingTimeInterval(-60))
        store.updateWorkoutDraft {
            $0.pauseIntervals = [WorkoutPauseInterval(startedAt: completedPauseStart, endedAt: completedPauseStart.addingTimeInterval(120))]
        }
        store.pauseWorkout(at: openPauseStart)
        store.setWorkoutSessionRPE(4.5)

        let record = try XCTUnwrap(store.saveActiveWorkout(status: .completed))

        XCTAssertEqual(record.sessionRPE, 4.5)
        XCTAssertEqual(record.pauseIntervals?.count, 2)
        XCTAssertEqual(record.pauseIntervals?.last?.startedAt, openPauseStart)
        XCTAssertEqual(record.pauseIntervals?.last?.endedAt, record.completedAt)
    }

    func testTodayEnergyReportKeepsSavedCurrentAlgorithmValueAfterWeightChange() throws {
        let store = AppStore(defaults: makeDefaults())
        var user = testProfile(goal: .hypertrophy, split: .fullBody)
        user.ageYears = 30
        user.biologicalSex = .female
        store.finishOnboarding(with: user)
        let exercise = ExercisePrescription(
            name: "卧推",
            pattern: .horizontalPush,
            sets: 1,
            repLower: 8,
            repUpper: 10,
            targetRIR: 1,
            isPriority: true
        )
        store.startWorkout(TrainingSession(name: "胸", focus: "胸", exercises: [exercise]))
        let start = Date.now.addingTimeInterval(-3_600)
        store.updateWorkoutDraft { $0.startedAt = start }
        store.completeCurrentDraftSet()
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "FIT 3",
            confidence: .measured,
            coverage: 1
        )
        store.appendLiveMetricSample(
            .init(timestamp: start, heartRateBPM: 130, provenance: source),
            validity: .valid
        )
        store.appendLiveMetricSample(
            .init(timestamp: start.addingTimeInterval(5), heartRateBPM: 132, provenance: source),
            validity: .valid
        )
        let saved = try XCTUnwrap(store.saveActiveWorkout(status: .completed))

        store.addWeight(140)

        XCTAssertEqual(
            store.todayEnergyReport.strength.value,
            try XCTUnwrap(saved.activeEnergyKcal),
            accuracy: 0.001
        )
    }

    private func testProfile(goal: TrainingGoal, split: TrainingSplit) -> UserProfile {
        UserProfile(
            nickname: "测试",
            goal: goal,
            secondaryGoal: .none,
            experience: .intermediate,
            weeklyDays: split == .chestBackShouldersLegs ? 4 : 3,
            sessionMinutes: 60,
            equipment: .fullGym,
            bodyWeightKg: 70,
            loadIncrementKg: 2.5,
            splitPreference: split
        )
    }

    private func configuredStore(weightKg: Double) -> AppStore {
        let store = AppStore(defaults: makeDefaults())
        store.weightHistory = [
            WeightEntry(
                date: Date(timeIntervalSince1970: 1_699_999_000),
                kilograms: weightKg,
                source: "测试"
            )
        ]
        return store
    }

    private func watchEnergySample(kcal: Double, at date: Date) -> WorkoutMetricSample {
        WorkoutMetricSample(
            timestamp: date,
            activeEnergyKcal: kcal,
            provenance: MetricProvenance(
                source: .appleWatch,
                sourceName: "Apple Watch",
                confidence: .estimated,
                coverage: 1
            )
        )
    }
}
