# FitTune 2.0 Architecture and Sports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship FitTune 2.0.0 with lower-overhead persistence, thumb-reachable workout controls, corrected readiness handoff, paused cardio sessions, and a complete seven-sport real-time recording, analysis, history, export, Watch, Live Activity, and migration path.

**Architecture:** Keep `AppStore` as the SwiftUI facade while extracting atomic snapshot persistence, pure sport analysis, reusable sport models, and indexed history queries. Strength, cardio, and sport retain distinct records but share sensor sources, metric provenance, checkpoint policy, Live Activity, and unified history.

**Tech Stack:** Swift 5 language mode, SwiftUI, Observation, Foundation, HealthKit, CoreLocation, CoreMotion, CoreBluetooth, WatchConnectivity, ActivityKit, XCTest/Swift Testing through Swift Package Manager, Xcode iOS/watchOS/widget targets.

## Global Constraints

- Marketing version is exactly `2.0.0`; build number is exactly `20`; `AppSnapshot.currentSchemaVersion` is exactly `16`.
- Deployment floors remain iOS 17.0 and watchOS 10.0; add no third-party dependencies.
- Preserve the bundle identifier `com.codex.fittune` and cover-install without uninstalling or clearing user data.
- Schema 15 and older snapshots must retain profiles, plans, strength/cardio history, recovery, favorites, custom exercises, deleted records, and active strength/cardio drafts.
- At most one real-time heart-rate source is active: Apple Watch or standard BLE; iPhone location/pedometer may run alongside it; Huawei Health remains delayed HealthKit import.
- Missing sensors or permissions lower confidence but never block starting, pausing, saving, or discarding a session.
- Sensor checkpoints occur at most once per 15 seconds during continuous sampling; start, pause, resume, lifecycle background, finish, and discard force immediate persistence.
- Main workout actions use at least 44×44 pt targets and remain reachable without scrolling.
- No automatic strokes, rallies, scores, ball contacts, sprint counts, climbing grades, altitude illness diagnoses, or arbitrary VO2max estimates.
- Energy, training load, and recovery show source, coverage/confidence, algorithm version, and a reasonable range where applicable.
- New behavior is implemented test-first: every production behavior has a test observed failing for the missing behavior before implementation.

---

## File Structure

- `FitTune/Services/SnapshotRepository.swift`: production atomic-file storage, backup recovery, and test UserDefaults adapter.
- `FitTune/Models/SportModels.swift`: sport kinds, environments, capabilities, draft, record, aggregates, and analysis result.
- `FitTune/Engine/SportAnalysisEngine.swift`: effective duration, MET energy, HR/load, recovery, and capability decisions.
- `FitTune/Engine/HistoryBrowserEngine.swift`: unified strength/cardio/sport indexed search snapshot.
- `FitTune/Store/AppStore+Sports.swift`: sport session lifecycle, checkpoint, finish, delete/restore, and summary presentation.
- `FitTune/Views/SportsHubView.swift`: sport tab, recent activities, grouped quick start, and setup sheet.
- `FitTune/Views/SportSessionView.swift`: active sport metrics, pause/resume, finish, source state, and sticky controls.
- `FitTune/Views/SportHistoryDetailView.swift`: sport detail and analysis display.
- Existing store, sensor, Watch, widget, root, today, workout/cardio, history, export, project, and docs files are modified only at their integration boundaries.

---

### Task 1: Atomic Snapshot Repository and Continuous-Sample Checkpoints

**Files:**
- Create: `FitTune/Services/SnapshotRepository.swift`
- Create: `FitTuneTests/SnapshotRepositoryTests.swift`
- Modify: `FitTune/Store/AppStore.swift`
- Modify: `FitTune/Models/WorkoutModels.swift`
- Modify: `Package.swift`

**Interfaces:**
- Produces: `protocol SnapshotRepository`, `UserDefaultsSnapshotRepository`, `FileSnapshotRepository`, `SnapshotLoadResult`, and `AppStore.lastPersistenceError`.
- Produces: `AppStore.shouldPersistLiveMetric(lastPersistedAt:now:interval:)` as the common 15-second policy for strength, cardio, and sport.
- Preserves: `AppStore(defaults:)` synchronous semantics used by current tests.

- [ ] **Step 1: Add failing repository tests**

Add literal-behavior tests that prove:

```swift
func testFileRepositoryKeepsLastKnownGoodBackup() throws
func testFileRepositoryLoadsBackupWhenPrimaryIsCorrupt() throws
func testUserDefaultsRepositoryKeepsExistingSynchronousRoundTrip() throws
func testCardioLiveSamplesUseFifteenSecondCheckpointPolicy()
```

Use a `mkdtemp`-style unique temporary directory and hand-authored `Data("first".utf8)` / `Data("second".utf8)` values. The mutation each test catches is loss of backup, failure to fall back, asynchronous test storage, or returning `true` before 15 seconds.

- [ ] **Step 2: Run RED**

Run:

```bash
swift test --filter SnapshotRepositoryTests
```

Expected: compile/test failure because repository types and cardio checkpoint behavior do not exist.

- [ ] **Step 3: Implement repository and migration boundary**

Implement:

```swift
protocol SnapshotRepository: AnyObject {
    func loadCandidates() -> [Data]
    func save(_ data: Data) throws
    func removeAll() throws
}

struct SnapshotLoadResult: Equatable {
    var usedBackup: Bool
    var migratedLegacyStorage: Bool
}
```

`FileSnapshotRepository` stores `snapshot.json` and `snapshot.backup.json` under Application Support/FitTune, writes atomically, and preserves the previous valid primary as backup. `AppStore()` uses file storage and migrates the old `FitTune.snapshot.v1` blob after a successful file save; `AppStore(defaults:)` remains test-compatible.

Add transient sample-ID sets and per-draft checkpoint timestamps. Change `appendCardioMetricSample` to O(1)-style set membership, incremental aggregates, and the same 15-second persistence window already used by strength. Lifecycle checkpoint functions remain immediate.

- [ ] **Step 4: Run GREEN and regression tests**

Run:

```bash
swift test --filter SnapshotRepositoryTests
swift test --filter CardioSessionTests
swift test --filter WorkoutLifecycleTests
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit**

```bash
git add FitTune/Services/SnapshotRepository.swift FitTune/Store/AppStore.swift FitTune/Models/WorkoutModels.swift FitTuneTests/SnapshotRepositoryTests.swift Package.swift
git commit -m "perf: add resilient snapshot persistence"
```

---

### Task 2: Sport Domain and Scientific Analysis

**Files:**
- Create: `FitTune/Models/SportModels.swift`
- Create: `FitTune/Engine/SportAnalysisEngine.swift`
- Create: `FitTuneTests/SportAnalysisEngineTests.swift`
- Modify: `FitTune/Models/HealthMetricModels.swift`
- Modify: `FitTune/Engine/HeartRateAnalysisEngine.swift`
- Modify: `Package.swift`

**Interfaces:**
- Produces: `SportKind`, `SportEnvironment`, `SportIntensity`, `SportMetricCapability`, `SportSessionDraft`, `SportSessionRecord`, `SportAnalysisResult`.
- Produces: `SportAnalysisEngine.analyze(draft:completedAt:sessionRPE:weightKg:restingHeartRate:maximumHeartRate:)`.
- Produces: `SportAnalysisEngine.capabilities(kind:environment:hasHeartRate:hasLocation:hasPedometer:hasElevation:)`.

- [ ] **Step 1: Add failing sport mapping and analysis tests**

Add table-driven tests with hand-derived literals:

```swift
func testSevenSportsExposeStableTitlesSymbolsAndWatchActivityKeys()
func testIndoorRacketSportsNeverClaimDistanceOrElevation()
func testOutdoorTrailSportsExposeDistancePaceAndElevationOnlyWithEvidence()
func testPausedTimeIsExcludedFromEffectiveDurationAndSessionRPELoad()
func testBadmintonMETEstimateUsesNetActiveEnergyRange()
func testSportAnalysisRejectsHeartRateGapsLongerThanFifteenSeconds()
func testPercentMaxZonesDoNotReuseHeartRateReserveThresholds()
```

For a 70 kg, 60-minute social badminton session at 5.5 MET, assert the net center is `330.75 kcal` (`(5.5 - 1) × 3.5 × 70 / 200 × 60`) before rounding. For a 45-minute session at RPE 7 with 5 paused minutes, assert load is `280 AU`, not `315 AU`.

- [ ] **Step 2: Run RED**

```bash
swift test --filter SportAnalysisEngineTests
```

Expected: missing sport types and APIs.

- [ ] **Step 3: Implement minimal pure domain and engine**

Use the seven exact raw values from the spec. Extend `WorkoutMetricSample` with optional `altitudeMeters`, `elevationGainMeters`, and `speedMetersPerSecond`, preserving old decoding with optional fields.

Implement sport-specific MET lower/center/upper values, net active-energy calculation, effective duration, session-RPE load, heart-rate summary through existing time-weighted analysis, and conservative recovery ranges. Every result includes provenance, coverage, warnings, and algorithm version `2.0.0-sport-analysis-1`.

- [ ] **Step 4: Run GREEN**

```bash
swift test --filter SportAnalysisEngineTests
swift test --filter HeartRateAnalysisEngineTests
swift test --filter DomainModelTests
```

Expected: all selected tests pass and old JSON fixtures still decode.

- [ ] **Step 5: Commit**

```bash
git add FitTune/Models/SportModels.swift FitTune/Models/HealthMetricModels.swift FitTune/Engine/SportAnalysisEngine.swift FitTune/Engine/HeartRateAnalysisEngine.swift FitTuneTests/SportAnalysisEngineTests.swift Package.swift
git commit -m "feat: add scientific multi-sport domain"
```

---

### Task 3: Sport Store Lifecycle, Schema 16, Trash, and Export

**Files:**
- Create: `FitTune/Store/AppStore+Sports.swift`
- Create: `FitTuneTests/SportSessionTests.swift`
- Modify: `FitTune/Store/AppStore.swift`
- Modify: `FitTune/Models/DomainModels.swift`
- Modify: `FitTune/Services/DataExportService.swift`
- Modify: `FitTuneTests/DataExportServiceTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: Task 2 sport models/engine and Task 1 repository/checkpoint policy.
- Produces:

```swift
func startSportSession(kind: SportKind, environment: SportEnvironment, intensity: SportIntensity, at: Date)
func appendSportMetricSample(_ sample: WorkoutMetricSample, validity: LiveMetricValidity, now: Date)
func pauseSportSession(at: Date)
func resumeSportSession(at: Date)
func checkpointActiveSport()
func finishSportSession(status: WorkoutCompletionStatus, sessionRPE: Double, at: Date) -> SportSessionRecord?
func discardSportSession()
```

- [ ] **Step 1: Add failing lifecycle/migration/export tests**

Cover mutual exclusion with strength/cardio, pause accounting, duplicate samples, 15-second checkpoint decisions, complete/partial finish, summary generation, trash/restore/permanent delete, schema 15 decoding, and `sports.csv` headers/rows.

The schema fixture test must construct a schema-15 JSON without sport keys and assert `sportWorkouts == []`, `deletedSportWorkouts == []`, and `activeSportDraft == nil` after restore.

- [ ] **Step 2: Run RED**

```bash
swift test --filter SportSessionTests
swift test --filter DataExportServiceTests
```

Expected: missing sport store and export behavior.

- [ ] **Step 3: Implement store facade and schema**

Add optional/default sport fields to `AppSnapshot`, set schema to 16, include sport data in `currentSnapshot`, restore, reset, clear-to-trash, restore-all, empty-trash, delete counts, JSON, workout CSV, metrics CSV, and a new `sports.csv` export.

The sport extension owns only session and sport-record behavior; it calls internal AppStore persistence/checkpoint helpers rather than duplicating encoding.

- [ ] **Step 4: Run GREEN**

```bash
swift test --filter SportSessionTests
swift test --filter AppStoreTests
swift test --filter DataExportServiceTests
```

Expected: selected tests pass and existing record management remains unchanged.

- [ ] **Step 5: Commit**

```bash
git add FitTune/Store/AppStore+Sports.swift FitTune/Store/AppStore.swift FitTune/Models/DomainModels.swift FitTune/Services/DataExportService.swift FitTuneTests/SportSessionTests.swift FitTuneTests/DataExportServiceTests.swift Package.swift
git commit -m "feat: persist and export sport sessions"
```

---

### Task 4: Sensor, Watch, and Live Activity Integration

**Files:**
- Modify: `FitTune/Services/MotionLocationSource.swift`
- Modify: `FitTune/Services/LiveSensorCoordinator.swift`
- Modify: `FitTune/Services/BluetoothHeartRateSource.swift`
- Modify: `FitTune/Services/WorkoutActivityController.swift`
- Modify: `FitTune/Engine/WorkoutActivitySnapshot.swift`
- Modify: `FitTune/Models/WorkoutActivityAttributes.swift`
- Modify: `FitTuneWatch/WatchWorkoutSessionManager.swift`
- Modify: `FitTuneWidgets/WorkoutLiveActivityWidget.swift`
- Modify: `FitTuneTests/LiveSensorCoordinatorTests.swift`
- Modify: `FitTuneTests/WorkoutLifecycleTests.swift`

**Interfaces:**
- Consumes: `SportKind.watchActivityKey`, sport environment/capabilities, and metric altitude fields.
- Produces: `MotionLocationSource.start(sport:environment:from:)`, `LiveSensorCoordinator.endWorkoutCollectionKeepingPreference()`, and `WorkoutActivitySnapshot.sport(...)`.

- [ ] **Step 1: Add failing state-machine/snapshot tests**

Add tests that prove:

```swift
func testEndingCollectionStopsReconnectButKeepsPreferredSource()
func testSportSnapshotUsesSportSymbolTimerDistanceAndElevation()
func testEquivalentLiveActivitySnapshotsAreCoalesced()
func testElevationGainRejectsInvalidAccuracyAndSmallNoise()
```

Use fake Bluetooth providers and literal samples. Do not assert framework internals; assert coordinator state, emitted snapshot, and update-gate decisions.

- [ ] **Step 2: Run RED**

```bash
swift test --filter LiveSensorCoordinatorTests
swift test --filter WorkoutLifecycleTests
```

Expected: new APIs are missing.

- [ ] **Step 3: Implement sensors and Watch mappings**

Generalize motion/location start without removing the cardio overload. Reset accumulators per session, start GPS only for supported outdoor modes, add filtered altitude/elevation gain, and make stop idempotent.

Separate “end current collection” from “forget device.” Stop BLE notifications/scanning/reconnect while retaining the preferred descriptor.

Add explicit Watch Health authorization before first session and map sport activity keys to `.badminton`, `.tableTennis`, `.soccer`, `.climbing`, `.hiking`, and `.running`. Watch failure sends a rejected acknowledgement and iPhone falls back.

Coalesce identical ActivityKit states and cap updates at 1 Hz. Sport activities show timer, heart rate, distance or elevation and end immediately with the session.

- [ ] **Step 4: Run GREEN and target builds**

```bash
swift test --filter LiveSensorCoordinatorTests
swift test --filter WorkoutLifecycleTests
xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: tests pass and iOS app, Watch, and Widget compile through the FitTune scheme.

- [ ] **Step 5: Commit**

```bash
git add FitTune/Services/MotionLocationSource.swift FitTune/Services/LiveSensorCoordinator.swift FitTune/Services/BluetoothHeartRateSource.swift FitTune/Services/WorkoutActivityController.swift FitTune/Engine/WorkoutActivitySnapshot.swift FitTune/Models/WorkoutActivityAttributes.swift FitTuneWatch/WatchWorkoutSessionManager.swift FitTuneWidgets/WorkoutLiveActivityWidget.swift FitTuneTests/LiveSensorCoordinatorTests.swift FitTuneTests/WorkoutLifecycleTests.swift
git commit -m "feat: connect sports to live sensors"
```

---

### Task 5: Sports UI, Navigation, History, and Summary

**Files:**
- Create: `FitTune/Views/SportsHubView.swift`
- Create: `FitTune/Views/SportSessionView.swift`
- Create: `FitTune/Views/SportHistoryDetailView.swift`
- Create: `FitTune/Engine/HistoryBrowserEngine.swift`
- Create: `FitTuneTests/HistoryBrowserEngineTests.swift`
- Modify: `FitTune/Views/RootView.swift`
- Modify: `FitTune/Views/HistoryDetailView.swift`
- Modify: `FitTune/Views/ProfileView.swift`
- Modify: `FitTune/App/FitTuneApp.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: sport store lifecycle, sensors, Activity snapshot, analysis result.
- Produces: five tabs `今天 / 计划 / 运动 / 记录 / 我的` and unified searchable history.

- [ ] **Step 1: Add failing history snapshot tests**

Create strength, cardio, and sport records with fixed dates/names. Assert the literal sorted IDs for `all`, `strength`, `cardio`, and `sport` filters; assert searches for an exercise and `羽毛球`; assert a deleted sport is absent.

- [ ] **Step 2: Run RED**

```bash
swift test --filter HistoryBrowserEngineTests
```

Expected: unified history types do not exist.

- [ ] **Step 3: Implement UI and indexed history**

`SportsHubView` groups the seven sports, shows recent quick starts, and opens a compact setup sheet. Starting any sport requires at most two taps from the sport tab.

`SportSessionView` uses large timer/metrics, current source/coverage, optional location/elevation, pause overlay, sticky pause/finish controls, session-RPE completion sheet, automatic checkpoints, sensor cleanup on all exit paths, and no unavailable fake metrics.

Root presents active sport drafts full-screen and reconciles sport Live Activities. History adds the sport filter, debounced snapshot search, sport rows, and direct details. Profile trash UI includes sport records.

- [ ] **Step 4: Run GREEN and simulator build**

```bash
swift test --filter HistoryBrowserEngineTests
xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: tests pass and all new SwiftUI files compile.

- [ ] **Step 5: Commit**

```bash
git add FitTune/Views/SportsHubView.swift FitTune/Views/SportSessionView.swift FitTune/Views/SportHistoryDetailView.swift FitTune/Engine/HistoryBrowserEngine.swift FitTune/Views/RootView.swift FitTune/Views/HistoryDetailView.swift FitTune/Views/ProfileView.swift FitTune/App/FitTuneApp.swift FitTuneTests/HistoryBrowserEngineTests.swift Package.swift
git commit -m "feat: add the FitTune sports experience"
```

---

### Task 6: Strength, Cardio, Today, and Device Usability Pass

**Files:**
- Modify: `FitTune/Views/TodayView.swift`
- Modify: `FitTune/Views/WorkoutSessionView.swift`
- Modify: `FitTune/Views/CardioSessionView.swift`
- Modify: `FitTune/Views/DesignSystem.swift`
- Modify: `FitTune/Views/DeviceCenterView.swift`
- Modify: `FitTune/Views/PlanEditorView.swift`
- Modify: `FitTune/Store/AppStore.swift`
- Modify: `FitTune/Models/WorkoutModels.swift`
- Modify: `FitTuneTests/AppStoreTests.swift`
- Modify: `FitTuneTests/CardioSessionTests.swift`
- Modify: `FitTuneTests/WorkoutLifecycleTests.swift`

**Interfaces:**
- Produces: `startWorkout(_:readiness:recoveryCheckIn:)`, cardio pause/resume/effective duration, and a single sticky action model for strength states.

- [ ] **Step 1: Add failing behavior tests**

Add tests proving:

```swift
func testStartingWorkoutAtomicallyUsesCurrentRecoveryDraft()
func testCardioPauseIntervalsAreExcludedFromEffectiveDuration()
func testCardioResumeRejectsRetrogradeTimestamp()
func testCardioLiveInputsDefaultToNoInventedWorkload()
func testWorkoutPrimaryActionMatchesEveryDraftPhase()
```

The recovery test creates an older stored check-in and a different current draft, starts the session, and asserts the current values drive the saved store/check-in and resulting readiness score.

- [ ] **Step 2: Run RED**

```bash
swift test --filter AppStoreTests
swift test --filter CardioSessionTests
swift test --filter WorkoutLifecycleTests
```

Expected: new atomic start, cardio pause, and primary-action contracts are absent.

- [ ] **Step 3: Implement the usability pass**

Move the strength primary button to a bottom safe-area inset and expose one action per state. Add a paused overlay and one-time rest-complete sensory feedback. Keep all user-planned sets authoritative.

Split Today’s cardio sheet into explicit real-time and completed-entry paths; real-time workload defaults to zero/nil. Add cardio pause/resume and effective-duration analysis, sticky controls, device status button, and guaranteed cleanup on disappearance.

Place quick-start actions before energy on Today. Starting strength atomically saves current readiness and four-dimensional recovery. Increase numeric +/- tap targets to 44 pt, localize device state strings, and fix the plan editor interpolation typo.

- [ ] **Step 4: Run GREEN and UI build**

```bash
swift test --filter AppStoreTests
swift test --filter CardioSessionTests
swift test --filter WorkoutLifecycleTests
xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: selected tests and build pass.

- [ ] **Step 5: Commit**

```bash
git add FitTune/Views/TodayView.swift FitTune/Views/WorkoutSessionView.swift FitTune/Views/CardioSessionView.swift FitTune/Views/DesignSystem.swift FitTune/Views/DeviceCenterView.swift FitTune/Views/PlanEditorView.swift FitTune/Store/AppStore.swift FitTune/Models/WorkoutModels.swift FitTuneTests/AppStoreTests.swift FitTuneTests/CardioSessionTests.swift FitTuneTests/WorkoutLifecycleTests.swift
git commit -m "feat: streamline live workout controls"
```

---

### Task 7: Health Refresh Coalescing, Version 2.0, Documentation, and Final Verification

**Files:**
- Modify: `FitTune/Services/HealthDataSyncCoordinator.swift`
- Modify: `FitTune/App/FitTuneApp.swift`
- Modify: `FitTune/Engine/EnergyEngine.swift`
- Modify: `FitTune/Engine/SummaryEngine.swift`
- Modify: `FitTune/Views/AlgorithmInfoView.swift`
- Modify: `docs/scientific-basis.md`
- Modify: `FitTune.xcodeproj/project.pbxproj`
- Modify: relevant tests for health refresh and algorithm fixtures

**Interfaces:**
- Produces: coalesced pending HealthKit refresh, sport energy in daily breakdown, version identifiers `2.0.0-*`, and release `2.0.0 (20)`.

- [ ] **Step 1: Add failing health-coalescing and daily-energy tests**

Use a controllable fake service to assert an observer event received during refresh causes exactly one follow-up refresh. Add a daily-energy test proving sport energy is included only when HealthKit all-day active energy is absent and is not double-counted when it is present.

- [ ] **Step 2: Run RED**

Run the focused new test cases and confirm they fail because pending refresh and sport energy integration are missing.

- [ ] **Step 3: Implement coalescing, versions, and documentation**

Retain one root ingest path, skip semantically identical health snapshots, coalesce observer requests, add sport contribution to the explanatory energy breakdown, and preserve HealthKit all-day total precedence.

Update algorithm/version strings where changed, algorithm info, scientific basis with 2024 Compendium and session-RPE limits, every target’s `MARKETING_VERSION = 2.0.0`, and every target’s `CURRENT_PROJECT_VERSION = 20`.

- [ ] **Step 4: Run complete verification**

```bash
swift test
git diff --check
plutil -lint FitTune.xcodeproj/project.pbxproj
xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/FitTune-v2-debug CODE_SIGNING_ALLOWED=NO clean build
xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/FitTune-v2-release -allowProvisioningUpdates clean build
```

Expected: all tests pass, plist is valid, both builds say `BUILD SUCCEEDED`, the Release app identifies as `com.codex.fittune`, version `2.0.0`, build `20`, and `codesign --verify --deep --strict` succeeds.

- [ ] **Step 5: Commit**

```bash
git add FitTune docs/scientific-basis.md FitTune.xcodeproj/project.pbxproj FitTuneTests Package.swift
git commit -m "chore: release FitTune 2.0.0"
```

- [ ] **Step 6: Merge and cover-install**

Fast-forward the reviewed feature branch into `main`, run `swift test` on the merged tree, install `/tmp/FitTune-v2-release/Build/Products/Release-iphoneos/FitTune.app` with `xcrun devicectl device install app`, launch `com.codex.fittune`, and verify the process is running. Do not uninstall the prior app.

