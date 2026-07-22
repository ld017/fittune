import Foundation

struct PlanEditorDraft: Equatable {
    var sourceSessionID: UUID
    var sessionName: String
    var focus: String
    var exercises: [ExercisePrescription]

    func exercises(in phase: TrainingPhase) -> [ExercisePrescription] {
        exercises.filter { $0.resolvedPhase == phase }
    }
}

enum PlanEditError: Error, Equatable {
    case missingExercise
    case lockedExercise
    case cannotRemoveLastExercise
}

enum PlanEditingEngine {
    static func move(
        exerciseID: UUID,
        to phase: TrainingPhase,
        at index: Int,
        in draft: PlanEditorDraft
    ) throws -> PlanEditorDraft {
        guard let exerciseIndex = draft.exercises.firstIndex(where: { $0.id == exerciseID }) else {
            throw PlanEditError.missingExercise
        }
        var updated = draft
        var exercise = updated.exercises.remove(at: exerciseIndex)
        exercise.phase = phase

        var sections = grouped(updated.exercises)
        let insertionIndex = min(max(0, index), sections[phase, default: []].count)
        sections[phase, default: []].insert(exercise, at: insertionIndex)
        updated.exercises = flattened(sections)
        return updated
    }

    static func add(
        _ prescription: ExercisePrescription,
        to phase: TrainingPhase,
        at index: Int? = nil,
        in draft: PlanEditorDraft
    ) -> PlanEditorDraft {
        var updated = draft
        var exercise = prescription
        exercise.phase = phase
        var sections = grouped(updated.exercises)
        let insertionIndex = min(max(0, index ?? sections[phase, default: []].count), sections[phase, default: []].count)
        sections[phase, default: []].insert(exercise, at: insertionIndex)
        updated.exercises = flattened(sections)
        return updated
    }

    static func replace(
        exerciseID: UUID,
        with option: ExerciseOption,
        loadTransfer: ReplacementLoadTransfer,
        in draft: PlanEditorDraft
    ) throws -> PlanEditorDraft {
        guard let index = draft.exercises.firstIndex(where: { $0.id == exerciseID }) else {
            throw PlanEditError.missingExercise
        }
        var updated = draft
        updated.exercises[index].name = option.name
        updated.exercises[index].pattern = option.pattern
        updated.exercises[index].equipmentKind = option.equipment
        updated.exercises[index].suggestedLoadKg = loadTransfer.suggestedLoadKg
        updated.exercises[index].suggestedLoadReason = loadTransfer.reason
        return updated
    }

    static func remove(
        exerciseID: UUID,
        from draft: PlanEditorDraft
    ) throws -> PlanEditorDraft {
        guard draft.exercises.contains(where: { $0.id == exerciseID }) else {
            throw PlanEditError.missingExercise
        }
        guard draft.exercises.count > 1 else {
            throw PlanEditError.cannotRemoveLastExercise
        }
        var updated = draft
        updated.exercises.removeAll { $0.id == exerciseID }
        return updated
    }

    static func isLocked(exerciseID: UUID, in draft: WorkoutDraft) -> Bool {
        draft.results.contains { $0.exerciseID == exerciseID }
    }

    private static func grouped(
        _ exercises: [ExercisePrescription]
    ) -> [TrainingPhase: [ExercisePrescription]] {
        Dictionary(grouping: exercises, by: \ExercisePrescription.resolvedPhase)
    }

    private static func flattened(
        _ sections: [TrainingPhase: [ExercisePrescription]]
    ) -> [ExercisePrescription] {
        TrainingPhase.allCases.flatMap { sections[$0, default: []] }
    }
}
