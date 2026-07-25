# Task 5 Report: Evidence-Based and Personally Calibrated Rest

## Status

Completed and committed from base `dc97897`.

## Implementation

- Added `StrengthRestContext` and goal/load evidence floors: warmup and light isolation `60...120`, hypertrophy isolation `90...180`, hypertrophy compound `120...240`, and max-strength compound or low-rep/high-relative-load `180...300`.
- Added valid historical comparable-pair filtering, retention scoring, a five-pair personal-rest median/MAD basis, 15-second upward rounding, and range-clamped midpoint calibration.
- Replaced universal 12/22 bpm recovery rules with `PersonalRecoveryComparison`; personal HRR60/HRR120 baselines use median/MAD thresholds and can only extend rest or block an increase.
- Migrated the existing AppStore call sites to the new signal and context contracts without adding sample lifecycle or UI behavior. A no-history signal now remains advisory.
- Set `TrainingEngine.ruleVersion` and the rest benchmark fixture to `1.2.0-strength-rest-1`.

## Tests

- RED: the specified new interfaces failed to compile before implementation.
- Focused: `TrainingEngineTests` 49/49, `LiveAdaptationEngineTests` 2/2, and `BenchmarkFixtureTests/testRestAndE1RMBenchmarks` 1/1.
- Final: `swift test` passed 212 tests with 0 failures.

## Scope and Concerns

- Modified 7 source/test/fixture files: 396 insertions and 98 deletions.
- No remaining fixed `recovery < 12`, `recovery < 22`, or `calibrationSessions` references.
- AppStore changes are a minimal contract migration; historical set timing/heart-rate persistence remains outside this task as requested.
