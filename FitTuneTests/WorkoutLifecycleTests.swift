import XCTest
@testable import FitTune

final class WorkoutLifecycleTests: XCTestCase {
    func testLiveMetricPersistenceWindowOnlyAllowsPeriodicWrites() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertTrue(AppStore.shouldPersistLiveMetric(lastPersistedAt: nil, now: start, interval: 15))
        XCTAssertFalse(AppStore.shouldPersistLiveMetric(lastPersistedAt: start, now: start.addingTimeInterval(14), interval: 15))
        XCTAssertTrue(AppStore.shouldPersistLiveMetric(lastPersistedAt: start, now: start.addingTimeInterval(15), interval: 15))
    }

    @MainActor
    func testExplicitSetStartAndNextSetPersistActualTimeline() throws {
        let store = makeStrengthStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        store.startCurrentDraftSet(at: start)
        store.completeCurrentDraftSet(at: start.addingTimeInterval(35))
        store.advanceDraftToNextSet(at: start.addingTimeInterval(215))

        let set = try XCTUnwrap(store.activeWorkoutDraft?.results.first)
        XCTAssertEqual(set.startedAt, start)
        XCTAssertEqual(set.completedAt, start.addingTimeInterval(35))
        XCTAssertEqual(set.restEndedAt, start.addingTimeInterval(215))
        XCTAssertEqual(set.actualRestSeconds, 180)
    }

    @MainActor
    func testOneTapNextSetClosesRestAndStartsSetTimer() throws {
        let store = makeStrengthStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.startCurrentDraftSet(at: start)
        store.completeCurrentDraftSet(at: start.addingTimeInterval(30))

        store.startNextDraftSet(at: start.addingTimeInterval(210))

        let draft = try XCTUnwrap(store.activeWorkoutDraft)
        XCTAssertEqual(draft.setNumber, 2)
        XCTAssertEqual(draft.phase, .setActive)
        XCTAssertEqual(draft.currentSetStartedAt, start.addingTimeInterval(210))
        XCTAssertEqual(draft.results.last?.restEndedAt, start.addingTimeInterval(210))
        XCTAssertEqual(draft.results.last?.actualRestSeconds, 180)
    }

    @MainActor
    func testOneTapNextSetRejectsPausedAndRetrogradeStarts() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let pausedStore = makeStrengthStore()
        pausedStore.startCurrentDraftSet(at: start)
        pausedStore.completeCurrentDraftSet(at: start.addingTimeInterval(30))
        pausedStore.pauseWorkout(at: start.addingTimeInterval(40))

        pausedStore.startNextDraftSet(at: start.addingTimeInterval(210))

        XCTAssertEqual(pausedStore.activeWorkoutDraft?.phase, .resting)
        XCTAssertEqual(pausedStore.activeWorkoutDraft?.setNumber, 1)

        let staleStore = makeStrengthStore()
        staleStore.startCurrentDraftSet(at: start)
        staleStore.completeCurrentDraftSet(at: start.addingTimeInterval(30))

        staleStore.startNextDraftSet(at: start.addingTimeInterval(29))

        XCTAssertEqual(staleStore.activeWorkoutDraft?.phase, .resting)
        XCTAssertEqual(staleStore.activeWorkoutDraft?.setNumber, 1)
    }

    @MainActor
    func testDelayedPeakIsAttachedToMostRecentlyCompletedSet() throws {
        let store = makeStrengthStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "FIT 3",
            confidence: .measured,
            coverage: 1
        )

        store.startCurrentDraftSet(at: start)
        store.completeCurrentDraftSet(at: start.addingTimeInterval(30))
        store.advanceDraftToNextSet(at: start.addingTimeInterval(45))
        store.startCurrentDraftSet(at: start.addingTimeInterval(60))
        store.completeCurrentDraftSet(at: start.addingTimeInterval(90))
        store.appendLiveMetricSample(
            .init(timestamp: start.addingTimeInterval(120), heartRateBPM: 170, provenance: source),
            validity: .valid,
            now: start.addingTimeInterval(120)
        )

        let sets = try XCTUnwrap(store.activeWorkoutDraft?.results)
        XCTAssertNil(sets.first?.heartRateResponse)
        XCTAssertEqual(sets.last?.heartRateResponse?.peakBPM, 170)
    }

    @MainActor
    func testLegacyCompletionWithoutExplicitStartLeavesTimelineLowConfidence() throws {
        let store = makeStrengthStore()

        store.completeCurrentDraftSet(at: Date(timeIntervalSince1970: 1_700_000_030))

        XCTAssertNil(try XCTUnwrap(store.activeWorkoutDraft?.results.first).startedAt)
    }

    @MainActor
    func testStaleAdvanceDoesNotMoveNextSetOrExercise() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let setStore = makeStrengthStore()
        setStore.startCurrentDraftSet(at: start)
        setStore.completeCurrentDraftSet(at: start.addingTimeInterval(30))

        setStore.advanceDraftToNextSet(at: start.addingTimeInterval(29))

        XCTAssertEqual(setStore.activeWorkoutDraft?.setNumber, 1)
        XCTAssertEqual(setStore.activeWorkoutDraft?.phase, .resting)
        XCTAssertNil(setStore.activeWorkoutDraft?.results.last?.restEndedAt)

        let exerciseStore = makeTwoExerciseStrengthStore()
        exerciseStore.startCurrentDraftSet(at: start)
        exerciseStore.completeCurrentDraftSet(at: start.addingTimeInterval(30))

        XCTAssertFalse(exerciseStore.advanceDraftToNextExercise(at: start.addingTimeInterval(29)))
        XCTAssertEqual(exerciseStore.activeWorkoutDraft?.exerciseIndex, 0)
        XCTAssertNil(exerciseStore.activeWorkoutDraft?.results.last?.restEndedAt)
    }

    @MainActor
    func testRetrogradeSetStartIsRejectedAfterRestHasEnded() {
        let store = makeStrengthStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.startCurrentDraftSet(at: start)
        store.completeCurrentDraftSet(at: start.addingTimeInterval(30))
        store.advanceDraftToNextSet(at: start.addingTimeInterval(210))

        store.startCurrentDraftSet(at: start.addingTimeInterval(200))

        XCTAssertEqual(store.activeWorkoutDraft?.phase, .training)
        XCTAssertNil(store.activeWorkoutDraft?.currentSetStartedAt)
    }

    @MainActor
    func testPauseFreezesActiveSetCompletionUntilResume() throws {
        let store = makeStrengthStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.startCurrentDraftSet(at: start)
        store.pauseWorkout(at: start.addingTimeInterval(10))

        store.completeCurrentDraftSet(at: start.addingTimeInterval(30))

        XCTAssertEqual(store.activeWorkoutDraft?.phase, .setActive)
        XCTAssertTrue(store.activeWorkoutDraft?.results.isEmpty == true)

        store.resumeWorkout(at: start.addingTimeInterval(40))
        store.completeCurrentDraftSet(at: start.addingTimeInterval(50))

        XCTAssertEqual(store.activeWorkoutDraft?.results.count, 1)
    }

    @MainActor
    func testPauseFreezesSetStartUntilResume() {
        let store = makeStrengthStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.pauseWorkout(at: start)

        store.startCurrentDraftSet(at: start.addingTimeInterval(10))

        XCTAssertEqual(store.activeWorkoutDraft?.phase, .training)
        XCTAssertNil(store.activeWorkoutDraft?.currentSetStartedAt)

        store.resumeWorkout(at: start.addingTimeInterval(20))
        store.startCurrentDraftSet(at: start.addingTimeInterval(30))

        XCTAssertEqual(store.activeWorkoutDraft?.phase, .setActive)
        XCTAssertEqual(store.activeWorkoutDraft?.currentSetStartedAt, start.addingTimeInterval(30))
    }

    @MainActor
    func testPauseFreezesRestAndExerciseNavigationUntilResume() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let setStore = makeStrengthStore()
        setStore.startCurrentDraftSet(at: start)
        setStore.completeCurrentDraftSet(at: start.addingTimeInterval(30))
        setStore.pauseWorkout(at: start.addingTimeInterval(40))

        setStore.advanceDraftToNextSet(at: start.addingTimeInterval(180))

        XCTAssertEqual(setStore.activeWorkoutDraft?.phase, .resting)
        XCTAssertEqual(setStore.activeWorkoutDraft?.setNumber, 1)

        let exerciseStore = makeTwoExerciseStrengthStore()
        exerciseStore.pauseWorkout(at: start)

        XCTAssertFalse(exerciseStore.advanceDraftToNextExercise(at: start.addingTimeInterval(10)))
        XCTAssertEqual(exerciseStore.activeWorkoutDraft?.exerciseIndex, 0)
    }

    @MainActor
    func testPauseFreezesDraftInputsSetConfigurationAndRestExtension() throws {
        let store = makeStrengthStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.startCurrentDraftSet(at: start)
        store.completeCurrentDraftSet(at: start.addingTimeInterval(30))
        store.pauseWorkout(at: start.addingTimeInterval(40))
        let before = try XCTUnwrap(store.activeWorkoutDraft)

        store.updateWorkoutDraft {
            $0.loadKg = 999
            $0.reps = 99
            $0.rir = 9
            $0.techniqueQuality = 1
            $0.restRecommendation?.recommendedSeconds += 30
        }
        store.setDraftCurrentSetKind(.drop)
        store.setDraftPlannedSets(10)
        store.setDraftWarmupSets(6)

        let paused = try XCTUnwrap(store.activeWorkoutDraft)
        XCTAssertEqual(paused.loadKg, before.loadKg)
        XCTAssertEqual(paused.reps, before.reps)
        XCTAssertEqual(paused.rir, before.rir)
        XCTAssertEqual(paused.techniqueQuality, before.techniqueQuality)
        XCTAssertEqual(paused.restRecommendation, before.restRecommendation)
        XCTAssertEqual(paused.currentSetKind, before.currentSetKind)
        XCTAssertEqual(paused.totalWorkingSets, before.totalWorkingSets)
        XCTAssertEqual(paused.currentWarmupSets, before.currentWarmupSets)

        store.resumeWorkout(at: start.addingTimeInterval(50))
        store.updateWorkoutDraft { $0.loadKg = 42.5 }

        XCTAssertEqual(store.activeWorkoutDraft?.loadKg, 42.5)
    }

    @MainActor
    func testPauseFreezesExerciseReplacementRemovalAndEditorCommit() throws {
        let store = makeTwoExerciseStrengthStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let before = try XCTUnwrap(store.activeWorkoutDraft?.session)
        let replacement = ExerciseOption(
            name: "高脚杯深蹲",
            pattern: .squat,
            equipment: .dumbbell,
            category: .quadriceps,
            subcategory: .squat,
            stableID: "test.pause.goblet-squat"
        )
        store.pauseWorkout(at: start)

        store.replaceDraftCurrentExercise(with: replacement)
        store.removeDraftCurrentExercise()
        var editor = try XCTUnwrap(store.makeActiveWorkoutEditorDraft())
        editor.sessionName = "暂停时不应改名"

        XCTAssertThrowsError(try store.commitActiveWorkoutEditorDraft(editor)) { error in
            XCTAssertEqual(error as? PlanEditError, .workoutPaused)
        }
        XCTAssertEqual(store.activeWorkoutDraft?.session, before)
    }

    @MainActor
    func testPauseStillAllowsSessionRPEAndSaveExit() throws {
        let store = makeStrengthStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.completeCurrentDraftSet(at: start.addingTimeInterval(30))
        store.pauseWorkout(at: start.addingTimeInterval(40))

        store.setWorkoutSessionRPE(8)
        let record = try XCTUnwrap(store.saveActiveWorkout(status: .partial, at: start.addingTimeInterval(60)))

        XCTAssertEqual(record.sessionRPE, 8)
        XCTAssertEqual(record.pauseIntervals?.last?.endedAt, start.addingTimeInterval(60))
        XCTAssertNil(store.activeWorkoutDraft)
    }

    @MainActor
    func testNextSetStartFinalizesPreviousResponseAtCutoff() throws {
        let store = makeStrengthStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = MetricProvenance(source: .bluetooth, sourceName: "H10", confidence: .measured, coverage: 1)
        store.startCurrentDraftSet(at: start)
        store.completeCurrentDraftSet(at: start.addingTimeInterval(30))
        for (seconds, bpm) in [(30.0, 170.0), (90.0, 140.0), (150.0, 120.0)] {
            store.appendLiveMetricSample(
                .init(timestamp: start.addingTimeInterval(seconds), heartRateBPM: bpm, provenance: source),
                validity: .valid,
                now: start.addingTimeInterval(seconds)
            )
        }
        XCTAssertEqual(try XCTUnwrap(store.activeWorkoutDraft?.results.first).heartRateResponse?.hrr120, 50)

        store.advanceDraftToNextSet(at: start.addingTimeInterval(100))
        store.startCurrentDraftSet(at: start.addingTimeInterval(110))
        store.appendLiveMetricSample(
            .init(timestamp: start.addingTimeInterval(160), heartRateBPM: 110, provenance: source),
            validity: .valid,
            now: start.addingTimeInterval(160)
        )

        let response = try XCTUnwrap(store.activeWorkoutDraft?.results.first?.heartRateResponse)
        XCTAssertEqual(response.hrr60, 30)
        XCTAssertNil(response.hrr120)
    }

    @MainActor
    func testRepeatedLiveRecoveryStateDoesNotDuplicateDecisionLogEffect() throws {
        let store = makeStrengthStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = MetricProvenance(source: .bluetooth, sourceName: "FIT 3", confidence: .measured, coverage: 1)
        store.startCurrentDraftSet(at: start)
        store.completeCurrentDraftSet(at: start.addingTimeInterval(30))

        for (seconds, bpm) in [(35.0, 170.0), (45.0, 165.0), (55.0, 160.0)] {
            store.appendLiveMetricSample(
                .init(timestamp: start.addingTimeInterval(seconds), heartRateBPM: bpm, provenance: source),
                validity: .valid,
                now: start.addingTimeInterval(seconds)
            )
        }

        let events = try XCTUnwrap(store.activeWorkoutDraft?.heartRateDecisionLog)
        XCTAssertEqual(Set(events.map(\.effect)).count, events.count)
    }

    func testLockScreenSnapshotUsesCurrentUserPlannedSetAndHeartRate() {
        let exercise = ExercisePrescription(name: "杠铃卧推", pattern: .horizontalPush, sets: 5, repLower: 6, repUpper: 8, targetRIR: 0, isPriority: true, equipmentKind: .barbell)
        let session = TrainingSession(name: "胸", focus: "胸", exercises: [exercise])
        let draft = WorkoutDraft(sourceSessionID: session.id, session: session, exerciseIndex: 0, setNumber: 4, loadKg: 80, reps: 8, rir: 0, techniqueQuality: 4, hasPain: false)

        let snapshot = WorkoutActivitySnapshot.strength(draft: draft, heartRate: 151)

        XCTAssertEqual(snapshot.currentItem, "杠铃卧推")
        XCTAssertEqual(snapshot.progress, "正式组 4 / 5")
        XCTAssertEqual(snapshot.heartRate, 151)
    }

    func testStrengthRestSnapshotExposesNextSetDeepLinkForOwningSession() throws {
        let exercise = ExercisePrescription(name: "卧推", pattern: .horizontalPush, sets: 4, repLower: 6, repUpper: 10, targetRIR: 0, isPriority: true, workingSets: 4)
        var draft = WorkoutDraft(sourceSessionID: UUID(), session: TrainingSession(name: "胸", focus: "胸", exercises: [exercise]), exerciseIndex: 0, setNumber: 1, loadKg: 80, reps: 8, rir: 0, techniqueQuality: 4, hasPain: false)
        draft.usesSeparateWarmups = true
        draft.phase = .resting
        draft.restStartedAt = Date(timeIntervalSince1970: 1_700_000_000)
        draft.restRecommendation = RestRecommendation(lowerSeconds: 120, recommendedSeconds: 180, upperSeconds: 240, confidence: "高", reasons: [], inputsUsed: [])

        let snapshot = WorkoutActivitySnapshot.strength(draft: draft, heartRate: 132)
        let action = try XCTUnwrap(WorkoutActivitySnapshot.parseActionURL(snapshot.nextSetURL))

        XCTAssertEqual(action.sessionID, draft.id)
        XCTAssertEqual(action.action, .nextSet)
        XCTAssertFalse(snapshot.isCardio)
    }

    func testCardioSnapshotContainsElapsedAndAvailableDistanceCadence() {
        var draft = CardioSessionDraft(modality: .running, intensity: .zone2, startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        draft.distanceMeters = 2_340
        draft.metricSamples = [WorkoutMetricSample(
            timestamp: .now,
            cadence: 166,
            provenance: MetricProvenance(source: .phoneSensor, sourceName: "iPhone", confidence: .measured, coverage: 1)
        )]

        let snapshot = WorkoutActivitySnapshot.cardio(draft: draft, heartRate: 148)

        XCTAssertTrue(snapshot.isCardio)
        XCTAssertEqual(snapshot.distanceMeters, 2_340)
        XCTAssertEqual(snapshot.cadence, 166)
    }

    @MainActor
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

    @MainActor
    private func makeTwoExerciseStrengthStore() -> AppStore {
        let suite = "FitTuneTests.StrengthTimeline.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AppStore(defaults: defaults)
        let first = ExercisePrescription(name: "杠铃深蹲", pattern: .squat, sets: 1, repLower: 5, repUpper: 8, targetRIR: 1, isPriority: true, workingSets: 1)
        let second = ExercisePrescription(name: "卧推", pattern: .horizontalPush, sets: 1, repLower: 5, repUpper: 8, targetRIR: 1, isPriority: true, workingSets: 1)
        store.startWorkout(TrainingSession(name: "全身", focus: "全身", exercises: [first, second]))
        return store
    }
}
