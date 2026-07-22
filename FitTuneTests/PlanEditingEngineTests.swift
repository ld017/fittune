import XCTest
@testable import FitTune

@MainActor
final class PlanEditingEngineTests: XCTestCase {
    func testMoveWithinAndAcrossPhasesProducesCanonicalSectionOrder() throws {
        let primary = prescription("杠铃卧推", phase: .primary)
        let accessoryA = prescription("哑铃卧推", phase: .accessory)
        let accessoryB = prescription("哑铃飞鸟", phase: .accessory)
        let finisher = prescription("俯卧撑", phase: .finisher)
        var draft = PlanEditorDraft(
            sourceSessionID: UUID(),
            sessionName: "胸",
            focus: "胸",
            exercises: [primary, accessoryA, accessoryB, finisher]
        )

        draft = try PlanEditingEngine.move(exerciseID: accessoryB.id, to: .accessory, at: 0, in: draft)
        XCTAssertEqual(draft.exercises(in: .accessory).map(\.id), [accessoryB.id, accessoryA.id])

        draft = try PlanEditingEngine.move(exerciseID: accessoryA.id, to: .finisher, at: 0, in: draft)
        XCTAssertEqual(draft.exercises.map(\.resolvedPhase), [.primary, .accessory, .finisher, .finisher])
        XCTAssertEqual(draft.exercises(in: .finisher).map(\.id), [accessoryA.id, finisher.id])
    }

    func testReplacementPreservesPrescriptionIdentityAndTrainingTargets() throws {
        let original = ExercisePrescription(
            name: "杠铃卧推",
            pattern: .horizontalPush,
            sets: 5,
            repLower: 6,
            repUpper: 10,
            targetRIR: 0,
            isPriority: true,
            suggestedLoadKg: 80,
            equipmentKind: .barbell,
            phase: .primary
        )
        let replacement = try exercise("哑铃卧推")
        let draft = PlanEditorDraft(sourceSessionID: UUID(), sessionName: "胸", focus: "胸", exercises: [original])
        let transfer = ReplacementLoadTransfer(suggestedLoadKg: nil, confidence: .unavailable, reason: "需重新校准")

        let updated = try PlanEditingEngine.replace(
            exerciseID: original.id,
            with: replacement,
            loadTransfer: transfer,
            in: draft
        )
        let result = try XCTUnwrap(updated.exercises.first)

        XCTAssertEqual(result.id, original.id)
        XCTAssertEqual(result.name, replacement.name)
        XCTAssertEqual(result.pattern, replacement.pattern)
        XCTAssertEqual(result.sets, 5)
        XCTAssertEqual(result.repLower, 6)
        XCTAssertEqual(result.repUpper, 10)
        XCTAssertEqual(result.targetRIR, 0)
        XCTAssertEqual(result.phase, .primary)
        XCTAssertNil(result.suggestedLoadKg)
        XCTAssertEqual(result.suggestedLoadReason, "需重新校准")
    }

    func testRemovingLastExerciseIsRejected() {
        let only = prescription("杠铃卧推", phase: .primary)
        let draft = PlanEditorDraft(sourceSessionID: UUID(), sessionName: "胸", focus: "胸", exercises: [only])

        XCTAssertThrowsError(try PlanEditingEngine.remove(exerciseID: only.id, from: draft)) { error in
            XCTAssertEqual(error as? PlanEditError, .cannotRemoveLastExercise)
        }
    }

    func testDraftLocksAnyExerciseWithRecordedSet() {
        let started = prescription("杠铃卧推", phase: .primary)
        let future = prescription("哑铃飞鸟", phase: .accessory)
        let session = TrainingSession(name: "胸", focus: "胸", exercises: [started, future])
        var draft = WorkoutDraft(
            sourceSessionID: session.id,
            session: session,
            exerciseIndex: 0,
            setNumber: 2,
            loadKg: 80,
            reps: 8,
            rir: 0,
            techniqueQuality: 4,
            hasPain: false
        )
        draft.results = [SetResult(
            exerciseID: started.id,
            exerciseName: started.name,
            setNumber: 1,
            loadKg: 80,
            reps: 8,
            rir: 0,
            movementPattern: started.pattern
        )]

        XCTAssertTrue(PlanEditingEngine.isLocked(exerciseID: started.id, in: draft))
        XCTAssertFalse(PlanEditingEngine.isLocked(exerciseID: future.id, in: draft))
    }

    func testPlanDraftCancelDoesNotPersistAndCommitPersistsAtomically() throws {
        let defaults = makeDefaults()
        let store = AppStore(defaults: defaults)
        let original = prescription("杠铃卧推", phase: .primary)
        let session = TrainingSession(name: "胸", focus: "胸", exercises: [original])
        store.plan = TrainingPlan(title: "测试", rationale: "测试", sessions: [session], generatedAt: .now, ruleVersion: TrainingEngine.ruleVersion)
        var editorDraft = try XCTUnwrap(store.makePlanEditorDraft(sessionID: session.id))
        editorDraft.sessionName = "取消的名称"

        XCTAssertEqual(store.plan?.sessions[0].name, "胸")

        editorDraft.sessionName = "胸部主课"
        store.commitPlanEditorDraft(editorDraft)
        let restored = AppStore(defaults: defaults)

        XCTAssertEqual(restored.plan?.sessions[0].name, "胸部主课")
    }

    func testActiveWorkoutEditIsCurrentOnlyUntilExplicitTemplateSaveAndSnapshotNeverChanges() throws {
        let store = AppStore(defaults: makeDefaults())
        store.profile = profile()
        let first = prescription("杠铃卧推", phase: .primary)
        let second = prescription("哑铃飞鸟", phase: .accessory)
        let session = TrainingSession(name: "胸", focus: "胸", exercises: [first, second])
        store.plan = TrainingPlan(title: "测试", rationale: "测试", sessions: [session], generatedAt: .now, ruleVersion: TrainingEngine.ruleVersion)
        store.startWorkout(session)
        let originalSnapshot = try XCTUnwrap(store.activeWorkoutDraft?.planSnapshot)
        var editorDraft = try XCTUnwrap(store.makeActiveWorkoutEditorDraft())
        editorDraft = try PlanEditingEngine.move(exerciseID: second.id, to: .finisher, at: 0, in: editorDraft)

        try store.commitActiveWorkoutEditorDraft(editorDraft)

        XCTAssertEqual(store.activeWorkoutDraft?.session.exercises.last?.resolvedPhase, .finisher)
        XCTAssertEqual(store.plan?.sessions[0].exercises.last?.resolvedPhase, .accessory)
        XCTAssertEqual(store.activeWorkoutDraft?.planSnapshot, originalSnapshot)
        XCTAssertTrue(store.activeWorkoutDraft?.changeEvents?.contains { $0.kind == .exerciseReordered } == true)

        try store.saveActiveWorkoutLayoutToSourcePlan()

        XCTAssertEqual(store.plan?.sessions[0].exercises.last?.resolvedPhase, .finisher)
        XCTAssertEqual(store.activeWorkoutDraft?.planSnapshot, originalSnapshot)
    }

    func testActiveWorkoutRejectsMutationOfStartedExercise() throws {
        let store = AppStore(defaults: makeDefaults())
        store.profile = profile()
        let first = prescription("杠铃卧推", phase: .primary)
        let second = prescription("哑铃飞鸟", phase: .accessory)
        let session = TrainingSession(name: "胸", focus: "胸", exercises: [first, second])
        store.plan = TrainingPlan(title: "测试", rationale: "测试", sessions: [session], generatedAt: .now, ruleVersion: TrainingEngine.ruleVersion)
        store.startWorkout(session)
        store.completeCurrentDraftSet()
        var editorDraft = try XCTUnwrap(store.makeActiveWorkoutEditorDraft())
        let replacement = try exercise("哑铃卧推")
        editorDraft = try PlanEditingEngine.replace(
            exerciseID: first.id,
            with: replacement,
            loadTransfer: .init(suggestedLoadKg: nil, confidence: .unavailable, reason: "测试"),
            in: editorDraft
        )

        XCTAssertThrowsError(try store.commitActiveWorkoutEditorDraft(editorDraft)) { error in
            XCTAssertEqual(error as? PlanEditError, .lockedExercise)
        }
    }

    private func prescription(_ name: String, phase: TrainingPhase) -> ExercisePrescription {
        let option = try! exercise(name)
        return ExercisePrescription(
            name: option.name,
            pattern: option.pattern,
            sets: 3,
            repLower: 8,
            repUpper: 12,
            targetRIR: 0,
            isPriority: phase == .primary,
            equipmentKind: option.equipment,
            phase: phase
        )
    }

    private func exercise(_ name: String) throws -> ExerciseOption {
        try XCTUnwrap(ExerciseCatalog.builtIns.first { $0.name == name })
    }

    private func profile() -> UserProfile {
        UserProfile(
            nickname: "测试",
            goal: .hypertrophy,
            secondaryGoal: .none,
            experience: .intermediate,
            weeklyDays: 4,
            sessionMinutes: 60,
            equipment: .fullGym,
            bodyWeightKg: 75,
            loadIncrementKg: 2.5
        )
    }

    private func makeDefaults() -> UserDefaults {
        let name = "PlanEditingEngineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

