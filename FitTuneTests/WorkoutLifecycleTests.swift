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
}
