enum WorkoutPrimaryAction: Equatable {
    case resumeWorkout
    case startSet
    case completeSet
    case startNextSet
    case advanceExercise
    case finishWorkout

    var title: String {
        switch self {
        case .resumeWorkout: "继续训练"
        case .startSet: "开始本组"
        case .completeSet: "完成本组"
        case .startNextSet: "开始下一组"
        case .advanceExercise: "进入下一个动作"
        case .finishWorkout: "完成本次训练"
        }
    }

    var systemImage: String {
        switch self {
        case .resumeWorkout, .startSet, .startNextSet: "play.fill"
        case .completeSet: "checkmark"
        case .advanceExercise: "arrow.right"
        case .finishWorkout: "flag.checkered"
        }
    }
}

enum WorkoutPrimaryActionResolver {
    static func resolve(
        phase: WorkoutDraftPhase,
        isPaused: Bool,
        hasNextExercise: Bool
    ) -> WorkoutPrimaryAction {
        if isPaused {
            return .resumeWorkout
        }

        switch phase {
        case .training:
            return .startSet
        case .setActive:
            return .completeSet
        case .resting:
            return .startNextSet
        case .exerciseComplete:
            return hasNextExercise ? .advanceExercise : .finishWorkout
        }
    }
}
