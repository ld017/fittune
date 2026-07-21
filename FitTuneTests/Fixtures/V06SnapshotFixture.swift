import Foundation
import XCTest
@testable import FitTune

enum V06SnapshotFixture {
    static let completedWorkoutID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let deletedWorkoutID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    static let draftID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!

    static func data() throws -> Data {
        let date = Date(timeIntervalSince1970: 1_721_563_200)
        let exercise = ExercisePrescription(
            name: "卧推",
            pattern: .horizontalPush,
            sets: 5,
            repLower: 6,
            repUpper: 10,
            targetRIR: 0,
            isPriority: true
        )
        let completedSet = SetResult(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            setNumber: 1,
            loadKg: 80,
            reps: 8,
            rir: 0,
            completedAt: date,
            movementPattern: exercise.pattern,
            techniqueQuality: 4,
            setKind: .working
        )
        let completed = WorkoutRecord(
            id: completedWorkoutID,
            sessionName: "胸",
            startedAt: date,
            completedAt: date.addingTimeInterval(3600),
            readinessScore: 82,
            sets: [completedSet]
        )
        let deleted = WorkoutRecord(
            id: deletedWorkoutID,
            sessionName: "腿",
            startedAt: date,
            completedAt: date.addingTimeInterval(1800),
            readinessScore: 70,
            sets: []
        )
        let session = TrainingSession(name: "胸", focus: "胸", exercises: [exercise])
        let draft = WorkoutDraft(
            id: draftID,
            sourceSessionID: session.id,
            session: session,
            startedAt: date,
            updatedAt: date,
            exerciseIndex: 0,
            setNumber: 2,
            loadKg: 82.5,
            reps: 8,
            rir: 0,
            techniqueQuality: 4,
            hasPain: false,
            results: [completedSet]
        )
        let snapshot = AppSnapshot(
            profile: nil,
            plan: nil,
            readiness: ReadinessInput(date: date),
            workoutHistory: [completed],
            weightHistory: [WeightEntry(date: date, kilograms: 75, source: "手动")],
            cardioWorkouts: [
                CardioWorkoutRecord(
                    date: date,
                    modality: .running,
                    intensity: .zone2,
                    durationMinutes: 30,
                    activeEnergyKcal: 220,
                    source: "手动"
                )
            ],
            deletedWorkoutHistory: [deleted],
            activeWorkoutDraft: draft
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "schemaVersion")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
