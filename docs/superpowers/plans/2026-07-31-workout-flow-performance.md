# FitTune Workout Flow and Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate repeated heart-rate advice, start the next set with one tap, and remove repeated catalog/history/persistence work that freezes exercise search.

**Architecture:** Keep scientific decisions in the existing engines, but make live adaptation idempotent and add an atomic store transition for starting the next set. Build immutable exercise-browser snapshots only when inputs change, and throttle non-critical live-sample persistence while retaining immediate lifecycle checkpoints.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, Xcode iOS targets, CoreDevice.

## Global Constraints

- Never auto-start a set, auto-increase load, or auto-end an exercise.
- Preserve decoding of existing workout drafts and histories.
- Critical lifecycle changes persist immediately; only continuous live samples are throttled.
- Use Bundle ID `com.codex.fittune` and cover-install without uninstalling or deleting app data.

---

### Task 1: Idempotent Live Heart-Rate Advice and Bounded Persistence

**Files:**
- Modify: `FitTune/Engine/LiveAdaptationEngine.swift`
- Modify: `FitTune/Store/AppStore.swift`
- Test: `FitTuneTests/LiveAdaptationEngineTests.swift`
- Test: `FitTuneTests/WorkoutLifecycleTests.swift`

**Interfaces:**
- Produces: `LiveAdaptationEngine.adapt(...)` with stable unique reasons.
- Produces: `AppStore.shouldPersistLiveMetric(lastPersistedAt:now:interval:) -> Bool`.

- [ ] **Step 1: Write failing regression tests**

Add tests that feed the output of one `.insufficientHistory` adaptation back as the next base input and assert the reason occurs once. Add a lifecycle test with repeated recovery samples and assert the decision log only changes when the decision effect changes. Add pure interval assertions for a 15-second live-persistence window.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter 'LiveAdaptationEngineTests|WorkoutLifecycleTests'
```

Expected: repeated reason/log and missing persistence-policy assertions fail.

- [ ] **Step 3: Implement the minimal fix**

Normalize reason fragments by splitting `；`, removing prior dynamic heart-rate fragments, and appending the current state once. Append rest reasons/inputs only when absent. In `AppStore`, update the decision log only when `(setResultID, effect)` changes, compute the running average without rescanning after initialization, and call `persist()` for continuous samples no more than once per 15 seconds.

- [ ] **Step 4: Verify GREEN and commit**

Run the focused tests, then commit:

```bash
git add FitTune/Engine/LiveAdaptationEngine.swift FitTune/Store/AppStore.swift FitTuneTests/LiveAdaptationEngineTests.swift FitTuneTests/WorkoutLifecycleTests.swift
git commit -m "fix: stabilize live heart rate updates"
```

---

### Task 2: One-Tap Start for the Next Set

**Files:**
- Modify: `FitTune/Store/AppStore.swift`
- Modify: `FitTune/Views/WorkoutSessionView.swift`
- Modify: `FitTune/App/FitTuneApp.swift`
- Test: `FitTuneTests/WorkoutLifecycleTests.swift`

**Interfaces:**
- Produces: `AppStore.startNextDraftSet(at:)`.

- [ ] **Step 1: Write failing lifecycle tests**

Assert that one call from `.resting` closes the previous rest, increments `setNumber`, applies the recommendation, sets `currentSetStartedAt` to the same timestamp, and ends in `.setActive`. Assert paused and retrograde calls do nothing.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter WorkoutLifecycleTests
```

Expected: `startNextDraftSet` is missing.

- [ ] **Step 3: Implement the atomic transition and UI**

Extract the existing next-set input preparation into a private helper shared by `advanceDraftToNextSet` and `startNextDraftSet`. The new method finalizes the previous response, sets the start timestamp, and persists once. Replace “准备下一组” with “开始下一组” and route the Live Activity deep link to the same method.

- [ ] **Step 4: Verify GREEN and commit**

```bash
swift test --filter WorkoutLifecycleTests
git add FitTune/Store/AppStore.swift FitTune/Views/WorkoutSessionView.swift FitTune/App/FitTuneApp.swift FitTuneTests/WorkoutLifecycleTests.swift
git commit -m "fix: start the next set with one tap"
```

---

### Task 3: Cached Exercise Browser Snapshot

**Files:**
- Modify: `FitTune/Engine/ExerciseReplacementEngine.swift`
- Modify: `FitTune/Views/ExerciseReplacementView.swift`
- Test: `FitTuneTests/ExerciseReplacementEngineTests.swift`

**Interfaces:**
- Produces: `ExerciseBrowserSnapshot` containing recommended candidates, grouped browse sections, and load transfers.
- Produces: `ExerciseReplacementEngine.browserSnapshot(catalog:context:search:filters:history:)`.

- [ ] **Step 1: Write failing snapshot tests**

Cover normalized search, muscle/pattern/equipment filters, unavailable-equipment policy, favorite ordering, stable grouping, and one indexed most-recent load per replacement.

- [ ] **Step 2: Run tests and verify RED**

```bash
swift test --filter ExerciseReplacementEngineTests
```

Expected: snapshot API is missing.

- [ ] **Step 3: Implement snapshot and cancellable search refresh**

Build ranked IDs, recent-load index, filtered items, and grouped sections once per refresh. Store the snapshot in `@State`; use `.task(id:)` with a 120 ms cancellable delay for search text and immediate refresh for filter/favorite changes. Rows read precomputed transfers and never sort workout history during `body`.

- [ ] **Step 4: Verify GREEN and commit**

```bash
swift test --filter ExerciseReplacementEngineTests
git add FitTune/Engine/ExerciseReplacementEngine.swift FitTune/Views/ExerciseReplacementView.swift FitTuneTests/ExerciseReplacementEngineTests.swift
git commit -m "perf: cache exercise replacement search"
```

---

### Task 4: Full Verification and Cover Install

**Files:**
- Modify only if verification finds an in-scope defect.

- [ ] **Step 1: Run full tests and structural checks**

```bash
swift test
git diff --check
plutil -lint FitTune.xcodeproj/project.pbxproj
```

- [ ] **Step 2: Build simulator and signed Release**

```bash
xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Release -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

- [ ] **Step 3: Verify and cover-install**

Verify bundle ID, version, build, signing authority, and provisioning expiry. Install with `devicectl device install app`, launch `com.codex.fittune`, and confirm the process remains present. Never uninstall the existing app.
