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

## Fix Round 1

### RED

- A legacy record containing only a cumulative Apple Watch energy sample recalculated from 100 to 213.15 kcal instead of preserving its saved center and marking the device value as comparison data.
- A workload update at the session start created a zero-duration closed segment and a second open segment.
- A finish timestamp before the session start saved an invalid record whose workload segment ended before it began.

### GREEN

- Legacy recalculation now requires valid mechanical evidence or a usable heart-rate series. Device-only energy remains a diagnostics comparison alongside the legacy warning.
- Workload updates reject timestamps at or before the draft/start of the open segment; finishes before the draft start return `nil` without clearing or changing the draft.
- `CardioSessionTests`: 8 passed. `AppStoreTests`: 41 passed. Final `swift test`: 221 passed, 0 failures.
