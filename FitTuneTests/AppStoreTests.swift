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
}
