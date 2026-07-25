# Task 10 Report: Strength Timing, Session-RPE, and Summary UI

## Status

DONE_WITH_CONCERNS

## Implementation

- Wired the stable strength action between preparation (`开始本组`) and active-set completion (`完成本组`), with a fixed-size monospaced active timer that excludes recorded pauses.
- Added an accessible top-bar pause/resume control.
- Routed every completed or partial save through a user-confirmed `1...10` session-RPE sheet. Session-RPE is not derived from per-set RIR.
- Preserved all existing exit choices, discard confirmation, and the heart-rate reconnect alert.
- Added honest delayed-peak, HRR, insufficient-sample, and personal-calibration rest states. Rest and heart-rate advice never disables the preparation/start action, auto-stops training, or directly changes load in the view.
- Expanded cardio and strength summaries and history details with scientific dose, timing, recovery, model/range/warning, and device-comparison rows.
- Updated the algorithm hierarchy to `专项机械模型 -> 心率 -> MET -> 仅设备降级` and added the evidence links listed by the approved specification.

## Test and Build Evidence

The consumed Task 7 lifecycle and RPE persistence behavior was already developed test-first. Before UI wiring, the focused lifecycle/RPE suite passed. After the final implementation:

```sh
swift test --filter WorkoutLifecycleTests --filter SummaryEngineTests --filter AppStoreTests.testPauseTimeIsExcludedAndRealSessionRPEIsSaved
# 22 tests, 0 failures

xcodebuild -project FitTune.xcodeproj -scheme FitTune -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
# ** BUILD SUCCEEDED **

git diff --check
# exit 0
```

No new model or engine behavior was added by this four-view task; the new work is SwiftUI wiring and presentation over the already-tested interfaces.

## Self-review

- The only disabled controls remain unrelated exercise-navigation/editing safeguards; no set preparation/start control is disabled by elapsed rest, heart rate, or history.
- The rest countdown remains advisory and requires an explicit user action to prepare the next set.
- All record saves occur only after session-RPE confirmation.
- No universal heart-rate recovery threshold, fat-gram estimate, VO2max fabrication, exact EPOC calories, or long-term adaptation percentage is shown.
- Accessibility-large summary metrics switch to a single-column grid, long model names wrap, and the active-set timer reserves a fixed layout slot.

## Concern

The iPhone 17 Pro simulator booted, but the install/launch command stalled before confirming that FitTune was available. It was stopped without claiming any rendered-screen evidence. Default and accessibility-large visual acceptance for the cardio live page, strength preparation/set/rest states, and both summaries remains deferred to Task 13 as directed by the controller.

## Fix Round 1

- Explicit pause now freezes set completion, next-set preparation, and exercise navigation in both the store and the strength-session controls. Resume restores those actions; advisory rest, heart-rate, and history states still do not lock them.
- Added `WorkoutTimeline.effectiveDuration` as the shared pause-aware duration calculation for the live timer, strength summary, and history detail. It clamps pauses to the measured interval and merges overlaps before subtracting them.
- Added set metadata alongside each heart-rate response so summaries retain the source exercise and original set number. The legacy response-only field remains decodable; old summaries use neutral “恢复记录” labels instead of inventing set numbers.

### TDD evidence

```sh
swift test --filter WorkoutLifecycleTests.testPauseFreezes
# RED: 6 assertion failures; paused store operations advanced phases/results
# GREEN: 2 tests, 0 failures

swift test --filter SummaryEngineTests.testStrengthSummarySubtractsOverlappingPausesFromSetDuration
# RED: average 30 vs 15; ratio 1/3 vs 1/6
# GREEN: 1 test, 0 failures

swift test --filter SummaryEngineTests.testStrengthSummaryPreservesOriginalSetNumberWhenEarlierResponseIsMissing
# RED: StrengthSummaryMetrics had no heartRateResponseSets member
# GREEN: 1 test, 0 failures

swift test --filter SummaryEngineTests.testStrengthSummaryDecodesLegacyHeartRateResponsesWithoutSetMetadata
# GREEN: 1 test, 0 failures
```

### Final verification

```sh
swift test --filter WorkoutLifecycleTests
# 12 tests, 0 failures

swift test --filter SummaryEngineTests
# 15 tests, 0 failures

xcodebuild -project FitTune.xcodeproj -scheme FitTune -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
# exit 0

git diff --check
# exit 0
```

The known visual-inspection concern remains deferred to Task 13; this fix round adds no new concern.

## Fix Round 2

- Centralized the explicit-pause check in `canMutateActiveWorkout` and applied it to generic draft edits, set configuration, workflow transitions, exercise add/replace/remove, active-workout editor commits, and source-plan layout saves.
- While paused, the strength view disables the exercise/configuration, set-input, and rest cards; any open exercise library/editor/replacement flow is dismissed. Resume and all save/discard exit paths remain available.
- Added a dedicated paused-editor error so a stale editor cannot commit after an external pause.
- Updated the open-pause save test to complete its set before pausing, matching the new full-freeze contract while preserving its RPE and pause-closing assertions.

### TDD evidence

```sh
swift test --filter 'WorkoutLifecycleTests.testPauseFreezesDraftInputsSetConfigurationAndRestExtension|WorkoutLifecycleTests.testPauseFreezesExerciseReplacementRemovalAndEditorCommit'
# RED: 2 tests, 10 assertion failures
# GREEN: 2 tests, 0 failures
```

### Final verification

```sh
swift test --filter WorkoutLifecycleTests
# 15 tests, 0 failures

swift test --filter AppStoreTests
# 43 tests, 0 failures

xcodebuild -project FitTune.xcodeproj -scheme FitTune -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build -quiet
# exit 0

git diff --check
# exit 0
```

Advisory rest, heart-rate, and history behavior outside an explicit user pause is unchanged. The known visual-inspection concern remains deferred to Task 13.
