# Workout Energy and Heart-Rate Resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the duplicated strength set count, calculate defensible strength/cardio energy from the best available samples, and alert during active workouts when a remembered BLE heart-rate broadcast cannot recover.

**Architecture:** `TrainingEngine` remains the stateless owner of workout-energy calculations, extended with time-weighted heart-rate integration and model-backed gap filling. `AppStore` resolves cumulative Apple Watch energy and applies the current estimator when saving or presenting records. `LiveSensorCoordinator` owns a deterministic silence monitor and exposes one shared reminder state consumed by both workout views.

**Tech Stack:** Swift 6 package tests, SwiftUI, Observation, CoreBluetooth, WatchConnectivity, HealthKit, XCTest, Xcode iOS Simulator.

## Global Constraints

- Keep iOS deployment target 17.0 and watchOS deployment target 10.0.
- Add no runtime dependency, cloud service, or analytics SDK.
- FIT 3 and standard BLE broadcasts are heart-rate sources only; never label their calculated energy as device-measured energy.
- Apple Watch cumulative active energy remains the only live device-measured workout energy in scope.
- A workout must continue when live heart rate is missing or invalid.
- Show the reconnect reminder no earlier than 15 seconds after the last valid heart-rate sample, once per interruption.
- Do not modify plan generation, exercise recommendation, rest recommendation, or training-load behavior.
- Use energy algorithm identifier `1.1.1-energy-timeseries-2`.

---

### Task 1: Time-Weighted Workout Energy

**Files:**
- Modify: `FitTune/Engine/TrainingEngine.swift`
- Modify: `FitTune/Engine/EnergyEngine.swift`
- Test: `FitTuneTests/TrainingEngineTests.swift`

**Interfaces:**
- Consumes: `WorkoutMetricSample`, `WorkoutRecord`, `CardioModality`, `CardioIntensity`, `UserProfile`, and existing `heartRateActiveEnergy`, `netActiveEnergy`, and `cardioMET`.
- Produces: `TrainingEngine.appleWatchActiveEnergy(from:)`, time-series-aware `strengthEnergyEstimate(record:weightKg:profile:)`, and optional `metricSamples`/`startedAt` inputs on `cardioEnergyEstimate`.

- [ ] **Step 1: Write failing strength time-series tests**

Add these tests to `TrainingEngineTests`:

```swift
func testLowHeartRateStrengthSessionUsesModelFloorInsteadOfSingleDigitEnergy() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var user = profile(goal: .hypertrophy, experience: .intermediate)
    user.ageYears = 30
    user.biologicalSex = .female
    let provenance = MetricProvenance(
        source: .bluetooth,
        sourceName: "HUAWEI WATCH FIT 3",
        confidence: .measured,
        coverage: 1
    )
    let samples = stride(from: 0.0, through: 3_600.0, by: 5.0).map {
        WorkoutMetricSample(
            timestamp: start.addingTimeInterval($0),
            heartRateBPM: 70,
            provenance: provenance
        )
    }
    let record = WorkoutRecord(
        sessionName: "力量",
        startedAt: start,
        completedAt: start.addingTimeInterval(3_600),
        readinessScore: 80,
        sets: [],
        sessionRPE: 7,
        averageHeartRate: 70,
        metricSamples: samples
    )

    let estimate = TrainingEngine.strengthEnergyEstimate(
        record: record,
        weightKg: 70,
        profile: user
    )

    XCTAssertGreaterThan(estimate.kilocalories, 100)
    XCTAssertTrue(estimate.method.contains("心率 + 力量模型"))
    XCTAssertLessThan(estimate.lowerBound, estimate.kilocalories)
    XCTAssertGreaterThan(estimate.upperBound, estimate.kilocalories)
}

func testStrengthHeartRateGapsAreFilledWithoutDoubleCounting() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var user = profile(goal: .hypertrophy, experience: .intermediate)
    user.ageYears = 30
    user.biologicalSex = .male
    let provenance = MetricProvenance(
        source: .bluetooth,
        sourceName: "H10",
        confidence: .measured,
        coverage: 1
    )
    let samples = [0.0, 5.0, 1_800.0, 1_805.0].map {
        WorkoutMetricSample(
            timestamp: start.addingTimeInterval($0),
            heartRateBPM: 140,
            provenance: provenance
        )
    }
    let record = WorkoutRecord(
        sessionName: "力量",
        startedAt: start,
        completedAt: start.addingTimeInterval(3_600),
        readinessScore: 80,
        sets: [],
        sessionRPE: 7,
        metricSamples: samples
    )

    let estimate = TrainingEngine.strengthEnergyEstimate(
        record: record,
        weightKg: 70,
        profile: user
    )
    let fallback = TrainingEngine.netActiveEnergy(met: 5, weightKg: 70, minutes: 60)

    XCTAssertEqual(estimate.kilocalories, fallback, accuracy: fallback * 0.05)
    XCTAssertEqual(estimate.confidence, "低至中")
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter TrainingEngineTests/testLowHeartRateStrengthSessionUsesModelFloorInsteadOfSingleDigitEnergy
swift test --filter TrainingEngineTests/testStrengthHeartRateGapsAreFilledWithoutDoubleCounting
```

Expected: the first test fails because the current Keytel average-heart-rate result is near zero; the second fails because the current implementation does not inspect sample timestamps or report gap-adjusted confidence.

- [ ] **Step 3: Add the time-weighted integration and strength blend**

Add a private result type and helpers inside `TrainingEngine`:

```swift
private struct TimeWeightedHeartRateEnergy {
    var kilocalories: Double
    var coverage: Double
}

private static func timeWeightedHeartRateEnergy(
    samples: [WorkoutMetricSample],
    startedAt: Date,
    completedAt: Date,
    weightKg: Double,
    profile: UserProfile,
    fallbackKcalPerMinute: Double,
    lowerRateFactor: Double,
    upperRateFactor: Double
) -> TimeWeightedHeartRateEnergy? {
    let totalSeconds = max(60, completedAt.timeIntervalSince(startedAt))
    let valid = samples
        .compactMap { sample -> (Date, Double)? in
            guard let bpm = sample.heartRateBPM,
                  (60...210).contains(bpm),
                  sample.timestamp >= startedAt,
                  sample.timestamp <= completedAt else { return nil }
            return (sample.timestamp, bpm)
        }
        .sorted { $0.0 < $1.0 }
    guard valid.count >= 2 else { return nil }

    var energy = 0.0
    var coveredSeconds = 0.0
    var cursor = startedAt
    for pair in zip(valid, valid.dropFirst()) {
        let left = pair.0
        let right = pair.1
        if left.0 > cursor {
            energy += fallbackKcalPerMinute * left.0.timeIntervalSince(cursor) / 60
        }
        let interval = right.0.timeIntervalSince(left.0)
        if interval > 0, interval <= 15 {
            let bpm = (left.1 + right.1) / 2
            let heartRateRate = heartRateActiveEnergy(
                averageHeartRate: bpm,
                minutes: 1,
                weightKg: weightKg,
                profile: profile
            ) ?? fallbackKcalPerMinute
            let boundedRate = min(
                fallbackKcalPerMinute * upperRateFactor,
                max(fallbackKcalPerMinute * lowerRateFactor, heartRateRate)
            )
            energy += boundedRate * interval / 60
            coveredSeconds += interval
        } else if interval > 0 {
            energy += fallbackKcalPerMinute * interval / 60
        }
        cursor = max(cursor, right.0)
    }
    if cursor < completedAt {
        energy += fallbackKcalPerMinute * completedAt.timeIntervalSince(cursor) / 60
    }
    return TimeWeightedHeartRateEnergy(
        kilocalories: energy,
        coverage: min(1, coveredSeconds / totalSeconds)
    )
}

private static func strengthFallbackEstimate(
    record: WorkoutRecord,
    weightKg: Double
) -> EnergyEstimate {
    let minutes = max(1, record.completedAt.timeIntervalSince(record.startedAt) / 60)
    let inferredRPE = record.sessionRPE ?? average(record.sets.compactMap { $0.feeling?.rpe })
    let met: Double
    if inferredRPE >= 9 { met = 6 }
    else if inferredRPE >= 7 { met = 5 }
    else if inferredRPE >= 5 { met = 3.5 }
    else { met = 3 }
    let value = netActiveEnergy(met: met, weightKg: weightKg, minutes: minutes)
    return EnergyEstimate(
        kilocalories: value,
        lowerBound: value * 0.65,
        upperBound: value * 1.35,
        method: "2024 Adult Compendium MET + session-RPE",
        confidence: "低至中"
    )
}
```

Update `strengthEnergyEstimate` so measured energy remains first, the fallback is calculated once, and time-series heart rate is blended with that fallback:

```swift
let fallback = strengthFallbackEstimate(record: record, weightKg: weightKg)
if let profile,
   let samples = record.metricSamples,
   let blended = timeWeightedHeartRateEnergy(
       samples: samples,
       startedAt: record.startedAt,
       completedAt: record.completedAt,
       weightKg: weightKg,
       profile: profile,
       fallbackKcalPerMinute: fallback.kilocalories / minutes,
       lowerRateFactor: 0.65,
       upperRateFactor: 1.35
   ) {
    let lowerFactor = 0.65 + 0.10 * blended.coverage
    let upperFactor = 1.35 - 0.10 * blended.coverage
    return EnergyEstimate(
        kilocalories: blended.kilocalories,
        lowerBound: blended.kilocalories * lowerFactor,
        upperBound: blended.kilocalories * upperFactor,
        method: "FitTune 心率 + 力量模型估算",
        confidence: blended.coverage >= 0.8 ? "中" : "低至中"
    )
}
return fallback
```

Remove the old whole-session `record.averageHeartRate` Keytel branch from strength estimation.

- [ ] **Step 4: Add failing cardio gap and Apple Watch extraction tests**

```swift
func testCardioHeartRateSeriesFillsLongGapWithModalityMET() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var user = profile(goal: .generalFitness, experience: .intermediate)
    user.ageYears = 30
    user.biologicalSex = .male
    let provenance = MetricProvenance(
        source: .bluetooth,
        sourceName: "FIT 3",
        confidence: .measured,
        coverage: 1
    )
    let samples = [0.0, 5.0, 1_795.0, 1_800.0].map {
        WorkoutMetricSample(
            timestamp: start.addingTimeInterval($0),
            heartRateBPM: 145,
            provenance: provenance
        )
    }

    let estimate = TrainingEngine.cardioEnergyEstimate(
        modality: .cycling,
        intensity: .zone2,
        minutes: 30,
        weightKg: 70,
        profile: user,
        metricSamples: samples,
        startedAt: start
    )
    let fallback = TrainingEngine.netActiveEnergy(
        met: TrainingEngine.cardioMET(modality: .cycling, intensity: .zone2),
        weightKg: 70,
        minutes: 30
    )

    XCTAssertEqual(estimate.kilocalories, fallback, accuracy: fallback * 0.05)
    XCTAssertTrue(estimate.method.contains("心率 + 有氧模型"))
}

func testOnlyAppleWatchSamplesProvideMeasuredWorkoutEnergy() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let watch = MetricProvenance(
        source: .appleWatch,
        sourceName: "Apple Watch",
        confidence: .measured,
        coverage: 1
    )
    let bluetooth = MetricProvenance(
        source: .bluetooth,
        sourceName: "FIT 3",
        confidence: .measured,
        coverage: 1
    )

    XCTAssertEqual(
        TrainingEngine.appleWatchActiveEnergy(from: [
            .init(timestamp: date, activeEnergyKcal: 120, provenance: watch),
            .init(timestamp: date.addingTimeInterval(5), activeEnergyKcal: 180, provenance: watch)
        ]),
        180
    )
    XCTAssertNil(TrainingEngine.appleWatchActiveEnergy(from: [
        .init(timestamp: date, activeEnergyKcal: 180, provenance: bluetooth)
    ]))
}
```

- [ ] **Step 5: Run the new cardio tests and verify RED**

Run:

```bash
swift test --filter TrainingEngineTests/testCardioHeartRateSeriesFillsLongGapWithModalityMET
swift test --filter TrainingEngineTests/testOnlyAppleWatchSamplesProvideMeasuredWorkoutEnergy
```

Expected: compile failure because `metricSamples`, `startedAt`, and `appleWatchActiveEnergy(from:)` do not exist.

- [ ] **Step 6: Implement cardio time-series inputs and Apple Watch extraction**

Add:

```swift
static func appleWatchActiveEnergy(from samples: [WorkoutMetricSample]) -> Double? {
    samples
        .filter { $0.provenance.source == .appleWatch }
        .compactMap(\.activeEnergyKcal)
        .filter { $0 > 0 }
        .max()
}
```

Extend `cardioEnergyEstimate` with:

```swift
metricSamples: [WorkoutMetricSample] = [],
startedAt: Date? = nil
```

Keep measured energy and ACSM speed/grade branches first. Before the old average-heart-rate branch, calculate the MET fallback and use `timeWeightedHeartRateEnergy` when `profile`, `startedAt`, and at least two valid samples exist. Use `startedAt.addingTimeInterval(Double(minutes) * 60)` as the end, factors `0.75...1.25`, method `FitTune 心率 + 有氧模型估算`, and confidence `中` for coverage at least `0.8`, otherwise `低至中`. Retain the old average-heart-rate branch for manually entered cardio without a sample curve.

Update:

```swift
static let algorithmVersion = "1.1.1-energy-timeseries-2"
```

in `EnergyEngine`.

- [ ] **Step 7: Run focused and full engine tests**

Run:

```bash
swift test --filter TrainingEngineTests
```

Expected: all `TrainingEngineTests` pass.

- [ ] **Step 8: Commit Task 1**

```bash
git add FitTune/Engine/TrainingEngine.swift FitTune/Engine/EnergyEngine.swift FitTuneTests/TrainingEngineTests.swift
git commit -m "fix: bound workout heart rate energy estimates"
```

---

### Task 2: Save and Present the Best Available Energy

**Files:**
- Modify: `FitTune/Engine/TrainingEngine.swift`
- Modify: `FitTune/Store/AppStore.swift`
- Modify: `FitTune/Views/HistoryDetailView.swift`
- Test: `FitTuneTests/AppStoreTests.swift`

**Interfaces:**
- Consumes: `TrainingEngine.appleWatchActiveEnergy(from:)` and the Task 1 estimators.
- Produces: `AppStore.currentEnergyRecord(_:)` overloads for strength and cardio presentation, plus save-time Apple Watch measured-energy propagation.

- [ ] **Step 1: Write failing save-time Apple Watch energy tests**

```swift
func testStrengthSaveUsesLatestAppleWatchCumulativeEnergy() throws {
    let store = AppStore(defaults: makeDefaults())
    let exercise = ExercisePrescription(
        name: "卧推",
        pattern: .horizontalPush,
        sets: 1,
        repLower: 8,
        repUpper: 10,
        targetRIR: 1,
        isPriority: true
    )
    store.startWorkout(TrainingSession(name: "胸", focus: "胸", exercises: [exercise]))
    store.completeCurrentDraftSet()
    let source = MetricProvenance(
        source: .appleWatch,
        sourceName: "Apple Watch",
        confidence: .measured,
        coverage: 1
    )
    store.appendLiveMetricSample(
        .init(timestamp: .now, heartRateBPM: 130, activeEnergyKcal: 120, provenance: source),
        validity: .valid
    )
    store.appendLiveMetricSample(
        .init(timestamp: .now, heartRateBPM: 132, activeEnergyKcal: 210, provenance: source),
        validity: .valid
    )

    let record = try XCTUnwrap(store.saveActiveWorkout(status: .completed))

    XCTAssertEqual(record.measuredActiveEnergyKcal, 210)
    XCTAssertEqual(record.activeEnergyKcal, 210)
    XCTAssertEqual(record.energyMethod, "Apple Watch / 设备实测")
}

func testCardioSaveUsesLatestAppleWatchCumulativeEnergy() throws {
    let store = AppStore(defaults: makeDefaults())
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    store.startCardioSession(modality: .cycling, intensity: .zone2)
    store.activeCardioDraft?.startedAt = start
    let source = MetricProvenance(
        source: .appleWatch,
        sourceName: "Apple Watch",
        confidence: .measured,
        coverage: 1
    )
    store.appendCardioMetricSample(
        .init(timestamp: start, heartRateBPM: 130, activeEnergyKcal: 80, provenance: source)
    )
    store.appendCardioMetricSample(
        .init(timestamp: start.addingTimeInterval(1_800), heartRateBPM: 140, activeEnergyKcal: 190, provenance: source)
    )

    let record = try XCTUnwrap(
        store.finishCardioSession(
            status: .completed,
            at: start.addingTimeInterval(1_800)
        )
    )

    XCTAssertEqual(record.activeEnergyKcal, 190)
    XCTAssertEqual(record.energyMethod, "Apple Watch / 设备实测")
    XCTAssertTrue(record.source.contains("Apple Watch"))
}
```

- [ ] **Step 2: Run save tests and verify RED**

Run:

```bash
swift test --filter AppStoreTests/testStrengthSaveUsesLatestAppleWatchCumulativeEnergy
swift test --filter AppStoreTests/testCardioSaveUsesLatestAppleWatchCumulativeEnergy
```

Expected: both tests fail because save paths ignore `activeEnergyKcal` in live samples.

- [ ] **Step 3: Wire live samples into strength and cardio save**

In `saveActiveWorkout`, resolve:

```swift
let watchEnergy = TrainingEngine.appleWatchActiveEnergy(
    from: draft.metricSamples ?? []
)
let measuredEnergy = draft.measuredActiveEnergyKcal > 0
    ? draft.measuredActiveEnergyKcal
    : watchEnergy
```

Pass `measuredEnergy` into `WorkoutRecord.measuredActiveEnergyKcal`.

In `finishCardioSession`, resolve the same Apple Watch maximum and pass it together with `draft.metricSamples` and `draft.startedAt` into `makeCardioWorkout`. Extend `makeCardioWorkout` to accept and forward:

```swift
metricSamples: [WorkoutMetricSample] = [],
startedAt: Date? = nil
```

Set the cardio record source to `Apple Watch 设备实测` when measured energy came from Apple Watch, otherwise preserve the existing source.

- [ ] **Step 4: Add current-algorithm presentation tests**

```swift
func testCurrentStrengthEnergyRecordRecalculatesWithoutMutatingInput() {
    let store = AppStore(defaults: makeDefaults())
    var user = testProfile(goal: .hypertrophy, split: .fullBody)
    user.ageYears = 30
    user.biologicalSex = .female
    store.finishOnboarding(with: user)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let source = MetricProvenance(
        source: .bluetooth,
        sourceName: "FIT 3",
        confidence: .measured,
        coverage: 1
    )
    let samples = stride(from: 0.0, through: 3_600.0, by: 5.0).map {
        WorkoutMetricSample(
            timestamp: start.addingTimeInterval($0),
            heartRateBPM: 70,
            provenance: source
        )
    }
    let oldRecord = WorkoutRecord(
        sessionName: "力量",
        startedAt: start,
        completedAt: start.addingTimeInterval(3_600),
        readinessScore: 80,
        sets: [],
        activeEnergyKcal: 5,
        sessionRPE: 7,
        averageHeartRate: 70,
        energyMethod: "Keytel 心率模型（力量训练修正区间）",
        metricSamples: samples
    )

    let updated = store.currentEnergyRecord(oldRecord)

    XCTAssertGreaterThan(updated.activeEnergyKcal ?? 0, 100)
    XCTAssertEqual(oldRecord.activeEnergyKcal, 5)
    XCTAssertTrue(updated.energyMethod?.contains("心率 + 力量模型") == true)
}

func testCurrentCardioEnergyRecordRecalculatesWithoutMutatingInput() {
    let store = AppStore(defaults: makeDefaults())
    var user = testProfile(goal: .generalFitness, split: .fullBody)
    user.ageYears = 30
    user.biologicalSex = .male
    store.finishOnboarding(with: user)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let source = MetricProvenance(
        source: .bluetooth,
        sourceName: "FIT 3",
        confidence: .measured,
        coverage: 1
    )
    let samples = stride(from: 0.0, through: 1_800.0, by: 5.0).map {
        WorkoutMetricSample(
            timestamp: start.addingTimeInterval($0),
            heartRateBPM: 135,
            provenance: source
        )
    }
    let oldRecord = CardioWorkoutRecord(
        date: start,
        modality: .cycling,
        intensity: .zone2,
        durationMinutes: 30,
        averageHeartRate: 135,
        activeEnergyKcal: 5,
        source: "旧心率估算",
        energyMethod: "Keytel 平均心率模型",
        metricSamples: samples
    )

    let updated = store.currentEnergyRecord(oldRecord)

    XCTAssertNotEqual(updated.activeEnergyKcal, 5)
    XCTAssertEqual(oldRecord.activeEnergyKcal, 5)
    XCTAssertTrue(updated.energyMethod?.contains("心率 + 有氧模型") == true)
}
```

- [ ] **Step 5: Run presentation tests and verify RED**

Run:

```bash
swift test --filter AppStoreTests
```

Expected: compile failure because `currentEnergyRecord` overloads do not exist.

- [ ] **Step 6: Implement non-mutating current-energy record copies**

Add these overloads:

```swift
func currentEnergyRecord(_ record: WorkoutRecord) -> WorkoutRecord {
    guard record.metricSamples?.isEmpty == false else { return record }
    var current = record
    current.measuredActiveEnergyKcal =
        record.measuredActiveEnergyKcal
        ?? TrainingEngine.appleWatchActiveEnergy(from: record.metricSamples ?? [])
    let weight = latestWeight ?? profile?.bodyWeightKg ?? 70
    let estimate = TrainingEngine.strengthEnergyEstimate(
        record: current,
        weightKg: weight,
        profile: profile
    )
    current.activeEnergyKcal = estimate.kilocalories
    current.energyLowerBoundKcal = estimate.lowerBound
    current.energyUpperBoundKcal = estimate.upperBound
    current.energyMethod = estimate.method
    current.summary = SummaryEngine.strengthSummary(
        for: current,
        bodyWeightKg: weight,
        maximumHeartRate: resolvedMaximumHeartRate
    )
    return current
}

func currentEnergyRecord(_ record: CardioWorkoutRecord) -> CardioWorkoutRecord {
    guard record.metricSamples?.isEmpty == false else { return record }
    var current = record
    let measured = TrainingEngine.appleWatchActiveEnergy(
        from: record.metricSamples ?? []
    )
    let estimate = TrainingEngine.cardioEnergyEstimate(
        modality: record.modality,
        intensity: record.intensity,
        minutes: record.durationMinutes,
        weightKg: latestWeight ?? profile?.bodyWeightKg ?? 70,
        profile: profile,
        distanceKm: record.distanceKm,
        averageHeartRate: record.averageHeartRate,
        speedKph: record.speedKph,
        inclinePercent: record.inclinePercent,
        measuredActiveEnergy: measured,
        metricSamples: record.metricSamples ?? [],
        startedAt: record.date
    )
    current.activeEnergyKcal = estimate.kilocalories
    current.energyLowerBoundKcal = estimate.lowerBound
    current.energyUpperBoundKcal = estimate.upperBound
    current.energyMethod = estimate.method
    if measured != nil { current.source = "Apple Watch 设备实测" }
    current.summary = SummaryEngine.cardioSummary(
        for: current,
        maximumHeartRate: resolvedMaximumHeartRate
    )
    return current
}
```

Update `todayEnergyReport` to use these methods for both strength and cardio. In `StrengthHistoryDetailView` and `CardioHistoryDetailView`, read `AppStore` from the environment and render the returned current-energy copy for the energy label and complete summary.

- [ ] **Step 7: Run AppStore and summary regressions**

Run:

```bash
swift test --filter AppStoreTests
swift test --filter SummaryEngineTests
```

Expected: all selected tests pass.

- [ ] **Step 8: Commit Task 2**

```bash
git add FitTune/Store/AppStore.swift FitTune/Views/HistoryDetailView.swift FitTuneTests/AppStoreTests.swift FitTune/Engine/TrainingEngine.swift
git commit -m "fix: save measured workout energy from Apple Watch"
```

---

### Task 3: Deterministic BLE Silence and Reconnect Monitoring

**Files:**
- Modify: `FitTune/Services/LiveSensorCoordinator.swift`
- Modify: `FitTune/Services/BluetoothHeartRateSource.swift`
- Test: `FitTuneTests/LiveSensorCoordinatorTests.swift`

**Interfaces:**
- Consumes: active workout session ID, active/preferred `LiveSourceDescriptor`, valid BLE heart-rate samples, and CoreBluetooth disconnect callbacks.
- Produces: `HeartRateReconnectReminder`, `HeartRateSilenceMonitor`, observable `LiveSensorCoordinator.reconnectReminder`, `retryPreferredSource()`, and `dismissReconnectReminder()`.

- [ ] **Step 1: Write failing pure monitor tests**

```swift
func testSilenceMonitorReconnectsAtFiveSecondsAndRemindsAtFifteen() {
    let start = Date(timeIntervalSince1970: 100)
    let sessionID = UUID()
    let source = LiveSourceDescriptor(id: "fit3", kind: .bluetooth, name: "FIT 3")
    var monitor = HeartRateSilenceMonitor()

    monitor.begin(sessionID: sessionID, source: source, at: start)

    XCTAssertEqual(monitor.evaluate(at: start.addingTimeInterval(4)), .none)
    XCTAssertEqual(
        monitor.evaluate(at: start.addingTimeInterval(5)),
        .reconnect(source)
    )
    guard case let .remind(reminder) = monitor.evaluate(
        at: start.addingTimeInterval(15)
    ) else {
        return XCTFail("Expected reconnect reminder")
    }
    XCTAssertEqual(reminder.sourceName, "FIT 3")
    XCTAssertEqual(monitor.evaluate(at: start.addingTimeInterval(20)), .none)
}

func testValidSampleRearmsReminderForANewInterruption() {
    let start = Date(timeIntervalSince1970: 100)
    let source = LiveSourceDescriptor(id: "fit3", kind: .bluetooth, name: "FIT 3")
    var monitor = HeartRateSilenceMonitor()
    monitor.begin(sessionID: UUID(), source: source, at: start)
    _ = monitor.evaluate(at: start.addingTimeInterval(15))

    monitor.receiveValidSample(at: start.addingTimeInterval(16))

    XCTAssertEqual(
        monitor.evaluate(at: start.addingTimeInterval(21)),
        .reconnect(source)
    )
    guard case .remind = monitor.evaluate(at: start.addingTimeInterval(31)) else {
        return XCTFail("Expected a reminder for the new interruption")
    }
}

func testEndedOrManuallyDisconnectedMonitorNeverReminds() {
    let start = Date(timeIntervalSince1970: 100)
    let source = LiveSourceDescriptor(id: "fit3", kind: .bluetooth, name: "FIT 3")
    var monitor = HeartRateSilenceMonitor()
    monitor.begin(sessionID: UUID(), source: source, at: start)
    monitor.end()

    XCTAssertEqual(monitor.evaluate(at: start.addingTimeInterval(30)), .none)
}
```

- [ ] **Step 2: Run monitor tests and verify RED**

Run:

```bash
swift test --filter LiveSensorCoordinatorTests/testSilenceMonitorReconnectsAtFiveSecondsAndRemindsAtFifteen
swift test --filter LiveSensorCoordinatorTests/testValidSampleRearmsReminderForANewInterruption
swift test --filter LiveSensorCoordinatorTests/testEndedOrManuallyDisconnectedMonitorNeverReminds
```

Expected: compile failure because monitor and action types do not exist.

- [ ] **Step 3: Implement the pure monitor**

Add:

```swift
struct HeartRateReconnectReminder: Identifiable, Equatable {
    let id = UUID()
    let sessionID: UUID
    let sourceName: String
}

enum HeartRateMonitoringAction: Equatable {
    case none
    case reconnect(LiveSourceDescriptor)
    case remind(HeartRateReconnectReminder)
}

struct HeartRateSilenceMonitor {
    private(set) var sessionID: UUID?
    private(set) var source: LiveSourceDescriptor?
    private(set) var lastValidSampleAt: Date?
    private var requestedReconnect = false
    private var showedReminder = false

    mutating func begin(
        sessionID: UUID,
        source: LiveSourceDescriptor,
        at date: Date
    ) {
        self.sessionID = sessionID
        self.source = source
        lastValidSampleAt = date
        requestedReconnect = false
        showedReminder = false
    }

    mutating func receiveValidSample(at date: Date) {
        guard sessionID != nil else { return }
        lastValidSampleAt = date
        requestedReconnect = false
        showedReminder = false
    }

    mutating func evaluate(at date: Date) -> HeartRateMonitoringAction {
        guard let sessionID, let source, let lastValidSampleAt else { return .none }
        let elapsed = date.timeIntervalSince(lastValidSampleAt)
        if elapsed >= 15, !showedReminder {
            showedReminder = true
            return .remind(.init(sessionID: sessionID, sourceName: source.name))
        }
        if elapsed >= 5, !requestedReconnect {
            requestedReconnect = true
            return .reconnect(source)
        }
        return .none
    }

    mutating func end() {
        sessionID = nil
        source = nil
        lastValidSampleAt = nil
        requestedReconnect = false
        showedReminder = false
    }
}
```

- [ ] **Step 4: Integrate monitor actions with the coordinator**

Add to `LiveSensorCoordinator`:

```swift
private(set) var reconnectReminder: HeartRateReconnectReminder?
private var silenceMonitor = HeartRateSilenceMonitor()
private var silenceTask: Task<Void, Never>?
```

On BLE workout begin, call `silenceMonitor.begin(...)` and start a one-second cancellable loop scoped to the session ID. The loop calls `evaluate(at:)`; `.reconnect` starts scanning the remembered BLE source and updates status, while `.remind` publishes `reconnectReminder`.

On each valid BLE measurement:

```swift
silenceMonitor.receiveValidSample(at: date)
reconnectReminder = nil
```

On explicit BLE disconnect, start scanning immediately and retain the same 15-second deadline from the last valid sample. On `endWorkout()` and user `disconnect()`, cancel the task, end the monitor, and clear the reminder.

Expose:

```swift
func retryPreferredSource() {
    reconnectReminder = nil
    guard preferredLiveSource?.kind == .bluetooth else { return }
    statusMessage = "正在重新扫描 \(preferredLiveSource?.name ?? "蓝牙心率设备")"
    bluetoothSource.startScanning()
}

func dismissReconnectReminder() {
    reconnectReminder = nil
}
```

Keep `BluetoothHeartRateSource` responsible for its immediate `central.connect(peripheral)` attempt after an explicit disconnect. The coordinator's scan is the fallback for silent notification loss and rediscovery.

- [ ] **Step 5: Add coordinator lifecycle tests**

```swift
@MainActor
func testEndingWorkoutClearsReconnectMonitoringState() {
    let coordinator = LiveSensorCoordinator()
    let source = LiveSourceDescriptor(
        id: "fit3",
        kind: .bluetooth,
        name: "FIT 3"
    )
    coordinator.select(source)
    coordinator.beginWorkout(sessionID: UUID(), activity: "strength")

    coordinator.endWorkout()

    XCTAssertNil(coordinator.reconnectReminder)
    XCTAssertNil(coordinator.activeSessionID)
}

@MainActor
func testManualDisconnectClearsReconnectReminderAndSession() {
    let coordinator = LiveSensorCoordinator()
    let source = LiveSourceDescriptor(
        id: "fit3",
        kind: .bluetooth,
        name: "FIT 3"
    )
    coordinator.select(source)
    coordinator.beginWorkout(sessionID: UUID(), activity: "strength")

    coordinator.disconnect()

    XCTAssertNil(coordinator.reconnectReminder)
    XCTAssertNil(coordinator.activeSessionID)
}
```

- [ ] **Step 6: Run live sensor tests**

Run:

```bash
swift test --filter LiveSensorCoordinatorTests
swift test --filter BluetoothHeartRateParserTests
```

Expected: all selected tests pass.

- [ ] **Step 7: Commit Task 3**

```bash
git add FitTune/Services/LiveSensorCoordinator.swift FitTune/Services/BluetoothHeartRateSource.swift FitTuneTests/LiveSensorCoordinatorTests.swift
git commit -m "feat: alert when heart rate broadcast cannot recover"
```

---

### Task 4: Workout UI Integration

**Files:**
- Modify: `FitTune/Views/WorkoutSessionView.swift`
- Modify: `FitTune/Views/CardioSessionView.swift`

**Interfaces:**
- Consumes: `LiveSensorCoordinator.reconnectReminder`, `retryPreferredSource()`, and `dismissReconnectReminder()`.
- Produces: one actionable reconnect alert in each active workout view and a centered strength title without the duplicated set total.

- [ ] **Step 1: Remove the duplicated strength top-bar count**

Replace:

```swift
Text("\(draft.results.count) 组")
    .font(.subheadline.bold().monospacedDigit())
    .frame(width: 52)
```

with:

```swift
Color.clear
    .frame(width: 42, height: 42)
    .accessibilityHidden(true)
```

Keep the main `prominentProgress` group count unchanged.

- [ ] **Step 2: Add the strength reconnect alert**

Attach to `WorkoutSessionView`:

```swift
.alert(
    "心率连接已中断",
    isPresented: Binding(
        get: { liveSensors.reconnectReminder != nil },
        set: { if !$0 { liveSensors.dismissReconnectReminder() } }
    )
) {
    Button("立即重新扫描") { liveSensors.retryPreferredSource() }
    Button("继续估算", role: .cancel) {
        liveSensors.dismissReconnectReminder()
    }
} message: {
    Text(
        "已尝试自动重连 \(liveSensors.reconnectReminder?.sourceName ?? "心率设备")，暂未恢复心率。可以重新扫描，训练记录不会中断。"
    )
}
```

- [ ] **Step 3: Add the same alert behavior to cardio**

Attach the same alert to `CardioSessionView`, using the same coordinator methods and copy. Do not create a second timer or local connection state in either view.

- [ ] **Step 4: Compile both workout views**

Run:

```bash
xcodebuild -project FitTune.xcodeproj \
  -scheme FitTune \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit Task 4**

```bash
git add FitTune/Views/WorkoutSessionView.swift FitTune/Views/CardioSessionView.swift
git commit -m "fix: simplify set progress and surface reconnect alert"
```

---

### Task 5: Full Regression and Visual Verification

**Files:**
- No planned file changes; any failure returns to the owning task before completion.

**Interfaces:**
- Consumes: all completed tasks.
- Produces: verified Swift package behavior, iOS build/test behavior, and visual confirmation of the strength and cardio workout screens.

- [ ] **Step 1: Run the full Swift package test suite**

```bash
swift test
```

Expected: all tests pass with 0 failures.

- [ ] **Step 2: Run the iOS simulator test suite**

```bash
xcodebuild -project FitTune.xcodeproj \
  -scheme FitTune \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Verify the strength screen**

Launch the current simulator build, enter a strength session, and verify:

- the top-bar title remains centered;
- the top bar no longer shows a second completed-set count;
- the main warmup/working-set progress remains visible;
- the layout does not shift at iPhone standard and large text sizes.

- [ ] **Step 4: Verify reconnect behavior in strength and cardio**

With a BLE source selected, simulate or trigger sample silence and verify:

- automatic reconnect status begins after 5 seconds;
- no alert appears before 15 seconds;
- one alert appears at 15 seconds;
- `立即重新扫描` restarts discovery of the remembered source;
- `继续估算` dismisses the alert without ending the workout;
- a valid sample clears the incident and permits one alert for a later interruption.

- [ ] **Step 5: Verify saved energy provenance**

Inspect one Apple Watch-sourced workout and one FIT 3/BLE-sourced workout:

- Apple Watch cumulative energy is shown as device measured;
- FIT 3 energy is shown as `FitTune 心率 + 力量模型估算` or `FitTune 心率 + 有氧模型估算`;
- a 60-minute low-heart-rate strength fixture does not produce single-digit active energy;
- today energy and history detail agree for the same record.

- [ ] **Step 6: Inspect the final diff**

```bash
git status --short
git diff --check
git log -5 --oneline
```

Expected: no uncommitted implementation changes, no whitespace errors, and the four task commits are present after the design/plan commits.
