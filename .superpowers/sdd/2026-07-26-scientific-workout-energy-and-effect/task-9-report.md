# Task 9 Report: Live Cardio Input and Feedback UI

## Status

Completed from base `32a9762`.

## Implementation

- Today’s cardio entry now starts live sessions with speed, incline or power, and handrail inputs intact; incline walking defaults to 20% grade and no handrail.
- Added percent-grade and machine-level modes. Level mode defaults to current/max level 20 and supports rise/run maximum-grade calibration using `rise / horizontal run * 100`.
- Machine levels, maximum level, and calibration persist in backward-compatible workload segments. Calibrated levels convert proportionally to actual grade; uncalibrated levels remain recorded but demote the ACSM center estimate to heart-rate/MET with a warning.
- Live controls update speed, incline/level, power, handrail support, and treadmill-confirmed distance without locking training. Workload changes create timestamped segments.
- Sensor and treadmill-confirmed distances are displayed separately, data warnings remain visible, and the heart-rate reconnect alert is preserved.
- Live Activity workload text now reflects current speed, grade/level, power, and incline-walking handrail state.
- Added the three existing scientific engine files to the Xcode app target; they were already in Swift Package Manager but missing from the project, which blocked the required simulator build.

## TDD Evidence

- The specified entry regression initially failed because `CardioSessionDraft.currentWorkload` was absent, then passed after adding the computed accessor.
- Machine-level persistence/store tests initially failed to compile because mode, calibration, resolved grade, and store parameters were absent.
- Estimator tests initially failed to compile because calibrated/uncalibrated machine-level workload fields were absent.
- Manual-workout coverage initially failed to compile because `TrainingEngine` did not accept or preserve machine-level inputs.

## Verification

- `swift test --filter CardioSessionTests`: 13 tests, 0 failures.
- `swift test --filter CardioEnergyEstimatorTests`: 12 tests, 0 failures.
- `xcodebuild -project FitTune.xcodeproj -scheme FitTune -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build`: `** BUILD SUCCEEDED **`.
- `git diff --check`: passed.

## Self-review and concerns

- Confirmed non-incline modalities cannot retain stale incline-mode or handrail inputs.
- Confirmed speed edits remain normal segment changes and do not trigger failure or control-lock behavior.
- Persisted additions are optional and legacy percent-grade segments decode as percent mode.
- No remaining Task 9 concerns.

## Fix Round 1

### Findings addressed

- Replaced transient-only treadmill calibration with a reusable `TreadmillMachineCalibration` containing the machine maximum level and rise/run grade measurement. It is optional in `AppSnapshot`, survives relaunch and session discard, clears with full data reset, and is reused only when the machine maximum level matches.
- Today and live-session calibration controls now persist every valid calibration. Future level-mode sessions automatically restore the saved machine maximum and actual-grade calibration.
- Passed `cardioPowerWatts` into Today’s manual `cardioEnergyEstimate` preview so cycling/rowing preview and saved energy use the same power input.

### TDD evidence

- RED: `testTreadmillCalibrationPersistsAndReusesForFutureMachineLevelSession` failed to compile because the reusable calibration model, store property, and persistence API did not exist.
- GREEN: the test now verifies snapshot relaunch, reuse at a proportional level, retention after discarding a session, and reuse in a later session.

### Verification

- `swift test --filter CardioSessionTests`: 14 tests, 0 failures.
- `swift test --filter CardioEnergyEstimatorTests`: 12 tests, 0 failures.
- `swift test --filter TrainingEngineTests/testLegacyCardioWrapperDerivesSpeedFromDistanceAndPreservesPower`: 1 test, 0 failures.
- Debug simulator build: `** BUILD SUCCEEDED **`.
- `git diff --check`: passed.

### Remaining concerns

- None.
