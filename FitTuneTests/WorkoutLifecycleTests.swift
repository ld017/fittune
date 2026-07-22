import XCTest
@testable import FitTune

final class WorkoutLifecycleTests: XCTestCase {
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
}
