# Task 6 Report: Cardio Workload Lifecycle

## Status

Completed from base `8071288`.

## RED / GREEN

- RED: the specified lifecycle tests failed to compile because `startCardioSession` accepted only modality and intensity, and `updateCardioWorkload` and `setConfirmedCardioDistance` did not exist.
- GREEN: `CardioSessionTests` passed 6 tests and `AppStoreTests` passed 40 tests.

## Implementation

- `AppStore` starts a persisted cardio draft with an optional open user-entered workload segment; no segment is created when all workload inputs are absent and handrail support is `.none`.
- Workload updates close the prior open segment at the supplied timestamp, append a replacement segment only when the values changed, and ignore identical updates.
- Finishing a cardio session closes the final segment, uses confirmed distance before sensor distance while retaining both values, and builds the saved record directly from `CardioEnergyEstimator` output.
- Finalized cardio records persist workload segments, diagnostics, Apple Watch comparison energy/source, and a summary generated after energy finalization.
- Legacy cardio records recalculate only with valid stored speed/incline or power evidence, valid saved segments, or usable raw heart-rate/Apple Watch samples. Unsupported legacy records retain their saved energy and receive a historical-data warning.

## Verification

- `swift test --filter CardioSessionTests`: 6 passed.
- `swift test --filter AppStoreTests`: 40 passed.
- Final `swift test`: 218 passed, 0 failures.
- `git diff --check`: passed.

## Self-review and concerns

- Confirmed the new public signatures and `.none` handrail default exactly match the brief.
- Confirmed confirmed distance does not replace the independently persisted sensor distance.
- No UI or machine-level calibration behavior was added. Task 9 remains responsible for level calibration.
