import XCTest
@testable import FitTune

final class WorkoutPrimaryActionResolverTests: XCTestCase {
    func testPausedWorkoutAlwaysResolvesToResume() {
        for phase in [
            WorkoutDraftPhase.training,
            .setActive,
            .resting,
            .exerciseComplete
        ] {
            XCTAssertEqual(
                WorkoutPrimaryActionResolver.resolve(
                    phase: phase,
                    isPaused: true,
                    hasNextExercise: true
                ),
                .resumeWorkout
            )
        }
    }

    func testTrainingResolvesToStartSet() {
        XCTAssertEqual(
            WorkoutPrimaryActionResolver.resolve(
                phase: .training,
                isPaused: false,
                hasNextExercise: true
            ),
            .startSet
        )
    }

    func testActiveSetResolvesToCompleteSet() {
        XCTAssertEqual(
            WorkoutPrimaryActionResolver.resolve(
                phase: .setActive,
                isPaused: false,
                hasNextExercise: true
            ),
            .completeSet
        )
    }

    func testRestResolvesToStartNextSet() {
        XCTAssertEqual(
            WorkoutPrimaryActionResolver.resolve(
                phase: .resting,
                isPaused: false,
                hasNextExercise: true
            ),
            .startNextSet
        )
    }

    func testCompletedExerciseResolvesToAdvanceWhenAnotherExerciseExists() {
        XCTAssertEqual(
            WorkoutPrimaryActionResolver.resolve(
                phase: .exerciseComplete,
                isPaused: false,
                hasNextExercise: true
            ),
            .advanceExercise
        )
    }

    func testCompletedFinalExerciseResolvesToFinishWorkout() {
        XCTAssertEqual(
            WorkoutPrimaryActionResolver.resolve(
                phase: .exerciseComplete,
                isPaused: false,
                hasNextExercise: false
            ),
            .finishWorkout
        )
    }
}
