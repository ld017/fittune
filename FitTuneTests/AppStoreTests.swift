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
}
