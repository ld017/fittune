# FitTune v0.6 Resumable User-Controlled Workouts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship FitTune v0.6 with crash-safe workout drafts, prominent user-controlled set progression, RIR-based load and rest recommendations, a canonical exercise catalog, and permanent trash deletion.

**Architecture:** Import the accepted v0.5 source, then make `AppStore.activeWorkoutDraft` the sole persisted source of truth for an in-progress workout. Keep recommendation logic pure in `TrainingEngine`, retain legacy decoding, and present the workout globally from `RootView` whenever a draft exists.

**Tech Stack:** Swift 6, SwiftUI, Observation, Codable/UserDefaults, Swift Package Manager tests, Xcode iOS 26.5 SDK.

## Global Constraints

- User-entered total sets and warm-up sets are hard constraints; advice never reduces them or automatically ends an exercise or workout.
- Next-set load uses reps, RIR, readiness, same-exercise history, and load increment only.
- Technique quality and pain remain independent safety inputs and do not change numeric load or rest advice.
- Rest advice is advisory, bounded to 60–300 seconds, explains its inputs, and never blocks the next set.
- v0.5 snapshots remain decodable; new sets keep legacy `feeling` nil.
- No cloud account, background timer execution, or single-set history editing is added.
- Baseline source is `/Users/lindui017/Documents/Codex/2026-07-19/bang/outputs/FitTune`; generated build and Xcode-user files are excluded.

---

### Task 1: Import and Freeze the v0.5 Baseline

**Files:**
- Copy: `FitTune/`, `FitTune.xcodeproj/`, `FitTuneTests/`, `Package.swift`, `.gitignore`, `README.md`, `SCIENTIFIC_BASIS.md`, `VALIDATION.md`

**Interfaces:**
- Consumes: accepted v0.5 source tree.
- Produces: buildable baseline in `/Users/lindui017/Documents/fit` with 26 passing tests.

- [ ] **Step 1: Copy source-controlled baseline content**

```bash
rsync -a --exclude '.build' --exclude '.swiftpm' --exclude '*.xcuserdata' --exclude '*.xcuserstate' --exclude '.DS_Store' --exclude '*.zip' /Users/lindui017/Documents/Codex/2026-07-19/bang/outputs/FitTune/ /Users/lindui017/Documents/fit/
```

- [ ] **Step 2: Verify the untouched baseline**

```bash
swift test
xcodebuild -project FitTune.xcodeproj -scheme FitTune -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: 26 tests pass and Xcode reports `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add .gitignore FitTune FitTune.xcodeproj FitTuneTests Package.swift README.md SCIENTIFIC_BASIS.md VALIDATION.md
git commit -m "chore: import FitTune v0.5 baseline"
```

---

### Task 2: Add Codable Draft, Set-Kind, and Rest Models

**Files:**
- Modify: `FitTune/Models/DomainModels.swift`
- Modify: `FitTuneTests/TrainingEngineTests.swift`

**Interfaces:**
- Produces: `SetKind`, `WorkoutDraftPhase`, `RestRecommendation`, `WorkoutDraft`, `SetResult.setKind`, `AppSnapshot.activeWorkoutDraft`.
- Consumers: Tasks 3–7.

- [ ] **Step 1: Write failing model tests**

```swift
func testWorkoutDraftRoundTripsProgress() throws {
    let exercise = ExercisePrescription(name: "杠铃卧推", pattern: .horizontalPush, sets: 5, repLower: 6, repUpper: 10, targetRIR: 2, isPriority: true, equipmentKind: .barbell)
    let session = TrainingSession(name: "胸部训练", focus: "胸", exercises: [exercise])
    let draft = WorkoutDraft(sourceSessionID: session.id, session: session, exerciseIndex: 0, setNumber: 4, warmupSetsByExercise: [exercise.id: 2], loadKg: 80, reps: 8, rir: 1, techniqueQuality: 4, hasPain: false)
    let restored = try JSONDecoder().decode(WorkoutDraft.self, from: JSONEncoder().encode(draft))
    XCTAssertEqual(restored, draft)
    XCTAssertEqual(restored.currentSetKind, .working)
    XCTAssertEqual(restored.workingSetOrdinal, 2)
}

func testLegacySetWithoutKindResolvesAsWorking() throws {
    let json = #"{"id":"00000000-0000-0000-0000-000000000001","exerciseID":"00000000-0000-0000-0000-000000000002","exerciseName":"卧推","setNumber":1,"loadKg":60,"reps":8,"rir":2,"completedAt":"2026-07-21T10:00:00Z"}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let result = try decoder.decode(SetResult.self, from: Data(json.utf8))
    XCTAssertEqual(result.resolvedSetKind, .working)
}
```

- [ ] **Step 2: Confirm RED**

Run: `swift test --filter 'WorkoutDraft|LegacySet'`

Expected: compilation fails because the new types do not exist.

- [ ] **Step 3: Implement the minimal models**

```swift
enum SetKind: String, Codable, Equatable { case warmup, working }
enum WorkoutDraftPhase: String, Codable, Equatable { case training, resting, exerciseComplete }

struct RestRecommendation: Codable, Equatable {
    var lowerSeconds: Int
    var recommendedSeconds: Int
    var upperSeconds: Int
    var confidence: String
    var reasons: [String]
    var inputsUsed: [String]
}

struct WorkoutDraft: Identifiable, Codable, Equatable {
    var id = UUID()
    var sourceSessionID: UUID
    var session: TrainingSession
    var startedAt: Date = .now
    var updatedAt: Date = .now
    var exerciseIndex: Int
    var setNumber: Int
    var warmupSetsByExercise: [UUID: Int] = [:]
    var loadKg: Double
    var reps: Int
    var rir: Int
    var techniqueQuality: Int
    var hasPain: Bool
    var averageHeartRate = 0.0
    var measuredActiveEnergyKcal = 0.0
    var results: [SetResult] = []
    var recommendation: SetRecommendation? = nil
    var restRecommendation: RestRecommendation? = nil
    var restStartedAt: Date? = nil
    var phase: WorkoutDraftPhase = .training
    var userOverrodeSuggestedLoad = false

    var currentExercise: ExercisePrescription { session.exercises[exerciseIndex] }
    var currentWarmupSets: Int { min(currentExercise.sets, max(0, warmupSetsByExercise[currentExercise.id] ?? 0)) }
    var currentSetKind: SetKind { setNumber <= currentWarmupSets ? .warmup : .working }
    var workingSetOrdinal: Int { max(0, setNumber - currentWarmupSets) }
    var totalWorkingSets: Int { max(0, currentExercise.sets - currentWarmupSets) }
}
```

Add these exact compatibility properties:

```swift
// SetResult
var setKind: SetKind? = nil
var resolvedSetKind: SetKind { setKind ?? .working }

// AppSnapshot
var activeWorkoutDraft: WorkoutDraft? = nil
```

- [ ] **Step 4: Verify GREEN and commit**

```bash
swift test --filter 'WorkoutDraft|LegacySet'
swift test
git add FitTune/Models/DomainModels.swift FitTuneTests/TrainingEngineTests.swift
git commit -m "feat: model persistent workout drafts"
```

---

### Task 3: Persist Draft Lifecycle and Permanent Deletion

**Files:**
- Modify: `Package.swift`
- Modify: `FitTune/Store/AppStore.swift`
- Create: `FitTuneTests/AppStoreTests.swift`
- Modify: `FitTune.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `activeWorkoutDraft`, lifecycle methods, permanent-delete methods, and `emptyTrash()`.

- [ ] **Step 1: Add AppStore to Package sources and the new test to Xcode**

Set package sources to:

```swift
sources: ["Models/DomainModels.swift", "Engine/TrainingEngine.swift", "Store/AppStore.swift"]
```

Register `AppStoreTests.swift` in the Xcode test group and test Sources phase with unique PBX IDs.

- [ ] **Step 2: Write failing persistence and permanent-delete tests**

```swift
@MainActor
final class AppStoreTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "FitTuneTests.\(UUID().uuidString)"
        let value = UserDefaults(suiteName: suite)!
        value.removePersistentDomain(forName: suite)
        return value
    }

    func testDraftPersistsAcrossStoreRecreation() {
        let defaults = defaults()
        let store = AppStore(defaults: defaults)
        let exercise = ExercisePrescription(name: "卧推", pattern: .horizontalPush, sets: 5, repLower: 6, repUpper: 10, targetRIR: 2, isPriority: true)
        store.startWorkout(TrainingSession(name: "胸", focus: "胸", exercises: [exercise]))
        store.updateWorkoutDraft { $0.setNumber = 4; $0.loadKg = 82.5; $0.rir = 1 }
        let restored = AppStore(defaults: defaults)
        XCTAssertEqual(restored.activeWorkoutDraft?.setNumber, 4)
        XCTAssertEqual(restored.activeWorkoutDraft?.loadKg, 82.5)
    }

    func testPermanentWorkoutDeletionCannotBeRestored() {
        let store = AppStore(defaults: defaults())
        let record = WorkoutRecord(sessionName: "胸", startedAt: .now, completedAt: .now, readinessScore: 80, sets: [])
        store.workoutHistory = [record]
        store.deleteWorkout(id: record.id)
        store.permanentlyDeleteWorkout(id: record.id)
        store.restoreWorkout(id: record.id)
        XCTAssertFalse(store.workoutHistory.contains { $0.id == record.id })
    }
}
```

- [ ] **Step 3: Confirm RED**

Run: `swift test --filter AppStoreTests`

Expected: the lifecycle and permanent-delete methods are missing.

- [ ] **Step 4: Implement persistence methods**

```swift
func startWorkout(_ session: TrainingSession) {
    guard activeWorkoutDraft == nil, let first = session.exercises.first else { return }
    let starting = loadRecommendation(for: first)
    activeWorkoutDraft = WorkoutDraft(sourceSessionID: session.id, session: session, exerciseIndex: 0, setNumber: 1, loadKg: starting.loadKg ?? 0, reps: first.repLower, rir: first.targetRIR, techniqueQuality: 4, hasPain: false)
    persist()
}

func updateWorkoutDraft(_ mutation: (inout WorkoutDraft) -> Void) {
    guard var draft = activeWorkoutDraft else { return }
    mutation(&draft)
    draft.updatedAt = .now
    activeWorkoutDraft = draft
    persist()
}

func discardWorkoutDraft() { activeWorkoutDraft = nil; persist() }

func finishWorkoutDraft(with record: WorkoutRecord) {
    workoutHistory.insert(record, at: 0)
    learnWorkingLoads(from: record)
    activeWorkoutDraft = nil
    persist()
}
```

Encode/decode `activeWorkoutDraft`. Add permanent deletion for workout, cardio, and weight trash arrays and `emptyTrash()`. Rebuild learned loads after workout deletion and empty-trash.

- [ ] **Step 5: Verify GREEN and commit**

```bash
swift test --filter AppStoreTests
swift test
git add Package.swift FitTune/Store/AppStore.swift FitTuneTests/AppStoreTests.swift FitTune.xcodeproj/project.pbxproj
git commit -m "feat: persist workouts and support permanent deletion"
```

---

### Task 4: Make Load and Rest Advice Purely Advisory

**Files:**
- Modify: `FitTune/Engine/TrainingEngine.swift`
- Modify: `FitTuneTests/TrainingEngineTests.swift`

**Interfaces:**
- Produces: revised `recommendNextSet` and `recommendRest`.

- [ ] **Step 1: Write failing recommendation tests**

```swift
func testRIRZeroDoesNotReduceUserPlannedSetsOrForceStop() {
    let exercise = ExercisePrescription(name: "卧推", pattern: .horizontalPush, sets: 5, repLower: 6, repUpper: 10, targetRIR: 2, isPriority: true)
    let result = SetResult(exerciseID: exercise.id, exerciseName: exercise.name, setNumber: 4, loadKg: 80, reps: 8, rir: 0, techniqueQuality: 2, feeling: .maximal)
    let readiness = ReadinessAssessment(score: 70, level: .moderate, summary: "测试", loadMultiplier: 0.95, setReduction: 1)
    let advice = TrainingEngine.recommendNextSet(prescription: exercise, result: result, readiness: readiness, increment: 2.5)
    XCTAssertEqual(advice.suggestedRemainingSets, 1)
    XCTAssertEqual(advice.continuation, .continueTraining)
}

func testTechniqueAndFeelingDoNotChangeNextLoad() {
    let exercise = ExercisePrescription(name: "卧推", pattern: .horizontalPush, sets: 5, repLower: 6, repUpper: 10, targetRIR: 2, isPriority: true)
    let readiness = ReadinessAssessment(score: 80, level: .ready, summary: "测试", loadMultiplier: 1, setReduction: 0)
    let first = SetResult(exerciseID: exercise.id, exerciseName: exercise.name, setNumber: 2, loadKg: 80, reps: 8, rir: 1, techniqueQuality: 5, feeling: .easy)
    let second = SetResult(exerciseID: exercise.id, exerciseName: exercise.name, setNumber: 2, loadKg: 80, reps: 8, rir: 1, techniqueQuality: 1, feeling: .pain)
    XCTAssertEqual(
        TrainingEngine.recommendNextSet(prescription: exercise, result: first, readiness: readiness, increment: 2.5).nextLoadKg,
        TrainingEngine.recommendNextSet(prescription: exercise, result: second, readiness: readiness, increment: 2.5).nextLoadKg
    )
}

func testRestRecommendationExtendsForRIRZeroRepDropAndLowReadiness() {
    let id = UUID()
    let previous = SetResult(exerciseID: id, exerciseName: "卧推", setNumber: 3, loadKg: 80, reps: 10, rir: 2)
    let current = SetResult(exerciseID: id, exerciseName: "卧推", setNumber: 4, loadKg: 80, reps: 8, rir: 0)
    let readiness = ReadinessAssessment(score: 40, level: .low, summary: "测试", loadMultiplier: 0.9, setReduction: 1)
    let rest = TrainingEngine.recommendRest(current: current, previous: previous, setKind: .working, pattern: .horizontalPush, historicalE1RM: 100, readiness: readiness)
    XCTAssertEqual(rest.recommendedSeconds, 300)
    XCTAssertTrue(rest.reasons.contains("RIR 0，增加 60 秒"))
    XCTAssertTrue(rest.reasons.contains("次数较前组下降超过 10%，增加 30 秒"))
    XCTAssertTrue(rest.reasons.contains("今日恢复偏低，增加 30 秒"))
}
```

- [ ] **Step 2: Confirm RED**

Run: `swift test --filter 'RIRZero|TechniqueAndFeeling|RestRecommendation'`

Expected: old stopping behavior fails and `recommendRest` is missing.

- [ ] **Step 3: Remove non-permitted load inputs and stopping behavior**

Keep reps, RIR, target range, readiness, same-exercise history, and increment. Set:

```swift
let remainingSets = max(0, prescription.sets - result.setNumber)
let continuation = TrainingContinuation.continueTraining
```

Do not inspect `techniqueQuality` or `feeling` when calculating load, remaining sets, or continuation.

- [ ] **Step 4: Implement transparent rest rules**

```swift
let compoundPatterns: Set<MovementPattern> = [.squat, .hinge, .horizontalPush, .horizontalPull, .verticalPush, .verticalPull, .singleLeg]
let isCompound = compoundPatterns.contains(pattern)
let relativeLoad = historicalE1RM.flatMap { $0 > 0 ? current.loadKg / $0 : nil }
var lower = setKind == .warmup ? 60 : (isCompound ? 120 : 90)
var upper = setKind == .warmup ? 120 : (isCompound ? 240 : 180)
var recommended = setKind == .warmup ? 90 : (isCompound ? 180 : 120)
if setKind == .working && ((relativeLoad ?? 0) >= 0.80 || current.reps <= 6) { lower = 180; upper = 300; recommended = 240 }
if current.rir == 0 { recommended += 60 }
if current.rir == 1 { recommended += 30 }
if let previous, current.loadKg <= previous.loadKg, Double(current.reps) < Double(previous.reps) * 0.90 { recommended += 30 }
if readiness.level == .low { recommended += 30 }
recommended = min(300, max(lower, recommended))
upper = min(300, max(upper, recommended))
```

Return exact reasons and inputs for each applied branch. Technique and pain are absent from the function signature.

- [ ] **Step 5: Verify GREEN and commit**

```bash
swift test --filter 'RIRZero|TechniqueAndFeeling|RestRecommendation'
swift test
git add FitTune/Engine/TrainingEngine.swift FitTuneTests/TrainingEngineTests.swift
git commit -m "feat: add advisory RIR load and rest guidance"
```

---

### Task 5: Canonicalize the Exercise Catalog

**Files:**
- Modify: `FitTune/Models/DomainModels.swift`
- Modify: `FitTune/Engine/TrainingEngine.swift`
- Modify: `FitTuneTests/TrainingEngineTests.swift`

**Interfaces:**
- Produces: stable IDs, canonical names, aliases, secondary-category labels, compound metadata, unique catalog queries.

- [ ] **Step 1: Write failing catalog tests**

```swift
func testExerciseCatalogHasUniqueIDsAndNames() {
    let items = TrainingEngine.allExerciseOptions
    XCTAssertEqual(Set(items.map(\.id)).count, items.count)
    XCTAssertEqual(Set(items.map { $0.name.normalizedExerciseName }).count, items.count)
}

func testCatalogHasNoCombinedExercises() {
    XCTAssertFalse(TrainingEngine.allExerciseOptions.contains { $0.name.contains(" + ") })
}

func testLegacyAliasesResolve() {
    XCTAssertEqual(TrainingEngine.canonicalExercise(named: "蝴蝶机夹胸（肘垫）")?.name, "蝴蝶机夹胸")
    XCTAssertEqual(TrainingEngine.canonicalExercise(named: "器械推肩")?.equipment, .selectorizedMachine)
}
```

- [ ] **Step 2: Confirm RED**

Run: `swift test --filter 'ExerciseCatalog|CombinedExercises|LegacyAliases'`

- [ ] **Step 3: Extend ExerciseOption compatibly**

Add these defaulted properties and resolutions:

```swift
var stableID: String? = nil
var aliases: [String] = []
var secondaryCategories: [ExerciseCategory] = []
var isCompound: Bool? = nil

var id: String { stableID ?? "\(pattern.rawValue)-\(name)" }
var resolvedIsCompound: Bool {
    isCompound ?? [.squat, .hinge, .horizontalPush, .horizontalPull, .verticalPush, .verticalPull, .singleLeg].contains(pattern)
}
```

- [ ] **Step 4: Replace all appended arrays with one catalog**

Use stable IDs such as `chest.barbell.flat_bench_press`. Keep one canonical row per normalized name, split every `" + "` item into individual exercises, keep each exercise in one primary category, and preserve old names as aliases. Normalize full-width parentheses, trim whitespace, and ignore parenthetical equipment clarifiers without merging different movement patterns.

Implement:

```swift
static func canonicalExercise(named name: String) -> ExerciseOption? {
    let key = name.normalizedExerciseName
    return exerciseLibrary.first { item in
        item.name.normalizedExerciseName == key || item.aliases.contains { $0.normalizedExerciseName == key }
    }
}
```

Use canonical matching in history lookup, with exact-name and movement-pattern fallback for unknown legacy names.

- [ ] **Step 5: Verify and commit**

```bash
swift test --filter 'ExerciseCatalog|CombinedExercises|LegacyAliases'
swift test
git add FitTune/Models/DomainModels.swift FitTune/Engine/TrainingEngine.swift FitTuneTests/TrainingEngineTests.swift
git commit -m "refactor: canonicalize the exercise catalog"
```

---

### Task 6: Rebuild the Workout Screen Around the Draft

**Files:**
- Modify: `FitTune/Store/AppStore.swift`
- Modify: `FitTune/Views/WorkoutSessionView.swift`
- Modify: `FitTune/Views/DesignSystem.swift`
- Modify: `FitTuneTests/AppStoreTests.swift`

**Interfaces:**
- Produces: explicit complete/rest/advance transitions, prominent set status, completed-set list, editable suggested load, and rest countdown.

- [ ] **Step 1: Write failing progression test**

```swift
func testFourthOfFiveAtRIRZeroKeepsFifthAvailable() {
    let store = AppStore(defaults: defaults())
    let exercise = ExercisePrescription(name: "卧推", pattern: .horizontalPush, sets: 5, repLower: 6, repUpper: 10, targetRIR: 2, isPriority: true)
    store.startWorkout(TrainingSession(name: "胸", focus: "胸", exercises: [exercise]))
    store.updateWorkoutDraft { $0.setNumber = 4; $0.loadKg = 80; $0.reps = 8; $0.rir = 0 }
    store.completeCurrentDraftSet()
    XCTAssertEqual(store.activeWorkoutDraft?.setNumber, 4)
    XCTAssertEqual(store.activeWorkoutDraft?.phase, .resting)
    XCTAssertEqual(store.activeWorkoutDraft?.session.exercises[0].sets, 5)
    store.advanceDraftToNextSet()
    XCTAssertEqual(store.activeWorkoutDraft?.setNumber, 5)
}
```

- [ ] **Step 2: Confirm RED**

Run: `swift test --filter FourthOfFive`

- [ ] **Step 3: Implement tested store transitions**

`completeCurrentDraftSet()` appends a result with `feeling: nil` and current `setKind`, calculates load/rest advice, sets `.resting`, and does not increment or alter planned sets. `advanceDraftToNextSet()` increments only after the explicit call; it fills suggested load unless `userOverrodeSuggestedLoad` is true.

- [ ] **Step 4: Bind WorkoutSessionView to AppStore**

Remove view-owned session, exercise index, group, load, reps, RIR, results, pending result, and feeling-prompt state. Keep only presentation state. Every numeric control writes through `updateWorkoutDraft`.

- [ ] **Step 5: Make group progress prominent**

Render large monospaced `第 N / 总组数组`, warm-up or formal-group ordinal, `动作 N / 总动作数`, full-session completed groups, and per-exercise completed rows with kind/load/reps/RIR.

- [ ] **Step 6: Replace feeling dialog with advisory rest UI**

“完成本组” directly calls the store transition. Show recommended seconds, range, confidence, reasons, and a timestamp-derived countdown with “开始下一组”, “+30 秒”, and “跳过计时”. No recommendation disables these controls.

- [ ] **Step 7: Keep safety warnings independent**

Technique 1–2 and pain display warning cards. Pain does not disable training controls. Continuing, saving, or ending always requires a user tap and never changes numeric recommendations implicitly.

- [ ] **Step 8: Verify and commit**

```bash
swift test
xcodebuild -project FitTune.xcodeproj -scheme FitTune -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
git add FitTune/Store/AppStore.swift FitTune/Views/WorkoutSessionView.swift FitTune/Views/DesignSystem.swift FitTuneTests/AppStoreTests.swift
git commit -m "feat: drive workout sessions from recoverable drafts"
```

---

### Task 7: Auto-Resume and Explicitly Exit Active Workouts

**Files:**
- Modify: `FitTune/App/FitTuneApp.swift`
- Modify: `FitTune/Views/RootView.swift`
- Modify: `FitTune/Views/TodayView.swift`
- Modify: `FitTune/Views/WorkoutSessionView.swift`

**Interfaces:**
- Produces: automatic launch/foreground resume and continue/save/discard decisions.

- [ ] **Step 1: Move presentation to RootView**

Remove `TodayView.activeSession`; starting calls `store.startWorkout(session)`. `RootView` presents `WorkoutSessionView()` whenever `activeWorkoutDraft != nil`. Apply `.interactiveDismissDisabled()` so in-app dismissal uses the close button; iOS Home, lock, and app switching remain unaffected.

- [ ] **Step 2: Checkpoint scene transitions**

Read `scenePhase` in `FitTuneApp`. On `.inactive` and `.background`, call `store.checkpointActiveWorkout()`, which writes the existing snapshot without starting background execution.

- [ ] **Step 3: Implement the close decisions**

“继续未完成训练” closes the dialog only. “保存并结束” builds a partial record when results exist, then clears the draft. With no result it only clears the draft. “放弃训练” requires a second confirmation, then clears the draft. Normal completion records `.completed` and clears the draft.

- [ ] **Step 4: Build and commit**

```bash
xcodebuild -project FitTune.xcodeproj -scheme FitTune -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
git add FitTune/App/FitTuneApp.swift FitTune/Views/RootView.swift FitTune/Views/TodayView.swift FitTune/Views/WorkoutSessionView.swift
git commit -m "feat: automatically resume interrupted workouts"
```

---

### Task 8: Permanent-Delete UI, Documentation, and Version

**Files:**
- Modify: `FitTune/Views/ProfileView.swift`
- Modify: `README.md`
- Modify: `SCIENTIFIC_BASIS.md`
- Modify: `VALIDATION.md`
- Modify: `FitTune.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: recover/permanently-delete actions, empty-trash confirmation, and v0.6 metadata.

- [ ] **Step 1: Add destructive confirmations**

Each trash row shows restore and permanent delete. Store selected record kind/ID, present “永久删除后无法恢复”, and call the exact store method only after confirmation. Add “清空回收站” with the same boundary.

- [ ] **Step 2: Update scientific documentation**

Cite `PMID 26605807`, `30747900`, `41549493`, and `36135029`. State that rest values are evidence-informed engineering ranges, not a universal clinically validated personal formula.

- [ ] **Step 3: Update version and behavior docs**

Set `MARKETING_VERSION = 0.6.0` and `CURRENT_PROJECT_VERSION = 6`. Update README and add v0.6 acceptance items to VALIDATION.

- [ ] **Step 4: Commit**

```bash
git add FitTune/Views/ProfileView.swift README.md SCIENTIFIC_BASIS.md VALIDATION.md FitTune.xcodeproj/project.pbxproj
git commit -m "feat: expose permanent deletion and document v0.6"
```

---

### Task 9: Final Verification, Simulator Acceptance, and Delivery

**Files:**
- Modify: `VALIDATION.md`
- Create: `Screenshots/FitTune-v0.6-resumed-workout-simulator.jpeg`
- Create: `Screenshots/FitTune-v0.6-rest-advice-simulator.jpeg`
- Create: `Screenshots/FitTune-v0.6-permanent-delete-simulator.jpeg`

- [ ] **Step 1: Invoke verification-before-completion and run clean checks**

```bash
swift test
xcodebuild -project FitTune.xcodeproj -scheme FitTune -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO clean build
git diff --check
```

Expected: all tests pass, Xcode reports `** BUILD SUCCEEDED **`, and `git diff --check` emits no output.

- [ ] **Step 2: Complete simulator acceptance**

Verify forced process termination at set 4/5, RIR 0 with set 5 still available, editable suggested load, advisory rest controls, no feeling dialog, unique catalog display, three-way exit, and irreversible trash deletion.

- [ ] **Step 3: Complete overwrite-install device acceptance when connected**

Use the existing Apple Development configuration and `com.codex.fittune`. Do not uninstall. Verify `0.6.0 (6)`, lock/unlock, app switching, termination/relaunch, v0.5 history migration, and active-draft restoration.

- [ ] **Step 4: Record evidence and commit**

```bash
git add VALIDATION.md Screenshots
git commit -m "test: validate FitTune v0.6 workout recovery"
```

- [ ] **Step 5: Create and verify the delivery archive**

Create `/Users/lindui017/Documents/fit/FitTune-iOS-MVP-v0.6.0.zip`, excluding `.git`, `.build`, `.swiftpm`, Xcode user data, `.DS_Store`, and archives. Verify with `unzip -tq` and report `shasum -a 256`.
