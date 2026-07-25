# Scientific Workout Energy and Effect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace FitTune's watch-first workout calories and sample-count summaries with activity-specific energy estimates, time-weighted cardio effects, delayed strength heart-rate recovery, personal rest calibration, and the restored FitTune app icon.

**Architecture:** Keep `TrainingEngine` as the compatibility facade used by existing views and tests, while moving new calculations into three stateless engines: `HeartRateAnalysisEngine`, `CardioEnergyEstimator`, and `StrengthEnergyEstimator`. `AppStore` owns timestamped workout lifecycle state and persistence; `SummaryEngine` converts stored raw data into explainable metrics; SwiftUI views only collect inputs and render those results. Device energy is persisted as a comparison, never as calorimetry ground truth.

**Tech Stack:** Swift 6, SwiftUI, Observation, Charts, XCTest, Swift Package Manager, Xcode iOS 17+/watchOS 10+, Asset Catalog, CoreDevice.

## Global Constraints

- Implement the approved spec at `docs/superpowers/specs/2026-07-26-scientific-workout-energy-and-effect-design.md`.
- Keep the app offline-first and add no runtime dependency, cloud service, analytics SDK, or private API.
- Keep `PRODUCT_BUNDLE_IDENTIFIER = com.codex.fittune`.
- Bump the release to `1.2.0 (13)`, schema to `15`, energy version to `1.2.0-scientific-energy-1`, summary version to `1.2.0-workout-effect-1`, and training rule version to `1.2.0-strength-rest-1`.
- Every new persisted field must be optional or have a decoding default so schema 14 and older snapshots remain readable.
- All displayed workout calories are active calories, not gross calories.
- A valid activity-specific mechanical model owns the center estimate. Heart rate, MET, and device energy may check plausibility or fill missing intervals but may not silently override it.
- Apple Watch energy and user-entered device energy are estimates. They must not receive `measured` confidence or a `+/-5%` interval.
- Heart rate must never shorten an evidence-based strength rest floor or independently raise the next-set load.
- Do not estimate VO2max improvement, fat grams, long-term cardiorespiratory improvement percentage, or exact EPOC calories.
- Do not ask for the user's iPhone until all package tests, simulator tests, builds, icon checks, and code review pass.

## File Map

**New production files**

- `FitTune/Engine/HeartRateAnalysisEngine.swift`: valid interval construction, HRR intensity integration, workload-matched drift, and per-set delayed peak/HRR extraction.
- `FitTune/Engine/CardioEnergyEstimator.swift`: modality-specific active-energy candidates, ACSM segment integration, cycling power range, MET/heart-rate fallback, diagnostics, and device comparison.
- `FitTune/Engine/StrengthEnergyEstimator.swift`: resistance-session classification, effective duration, structural MET prior, bounded heart-rate correction, and device comparison.

**New test files**

- `FitTuneTests/HeartRateAnalysisEngineTests.swift`
- `FitTuneTests/CardioEnergyEstimatorTests.swift`
- `FitTuneTests/StrengthEnergyEstimatorTests.swift`

**Existing ownership**

- `FitTune/Models/WorkoutModels.swift`: cardio workload segments and live cardio draft inputs.
- `FitTune/Models/DomainModels.swift`: set timeline, pauses, record diagnostics, schema version.
- `FitTune/Models/HealthMetricModels.swift`: typed heart-rate analysis and summary results.
- `FitTune/Engine/TrainingEngine.swift`: compatibility wrappers, rest floors, personal rest comparison, training effects.
- `FitTune/Engine/LiveAdaptationEngine.swift`: advisory-only response to personal recovery state.
- `FitTune/Engine/SummaryEngine.swift`: stored-record summaries.
- `FitTune/Store/AppStore.swift`: lifecycle, persistence, energy invocation, summary invocation.
- `FitTune/Views/TodayView.swift`, `CardioSessionView.swift`, `WorkoutSessionView.swift`, `WorkoutSummaryView.swift`, `HistoryDetailView.swift`, `AlgorithmInfoView.swift`: user input and display.
- `FitTune.xcodeproj/project.pbxproj`, `Package.swift`: source/test/resource integration.
- `FitTune/Resources/Assets.xcassets`: restored icon.

---

### Task 1: Persisted Scientific Workout Contracts

**Files:**

- Modify: `FitTune/Models/WorkoutModels.swift`
- Modify: `FitTune/Models/DomainModels.swift`
- Modify: `FitTune/Models/HealthMetricModels.swift`
- Modify: `FitTuneTests/DomainModelTests.swift`
- Modify: `FitTuneTests/CardioSessionTests.swift`

**Interfaces:**

- Produces: `HandrailSupport`, `CardioWorkloadSource`, `CardioWorkloadSegment`, `WorkoutPauseInterval`, `EnergyEstimateDiagnostics`, `HeartRateIntensityZone`, `HeartRateIntensitySummary`, `SetHeartRateResponse`, `PersonalRecoveryComparison`.
- Extends: `CardioSessionDraft`, `CardioWorkoutRecord`, `WorkoutDraft`, `SetResult`, `WorkoutRecord`, `EnergyEstimate`, `CardioSummaryMetrics`, `StrengthSummaryMetrics`.
- Changes: `WorkoutDraftPhase` gains `.setActive`; `AppSnapshot.currentSchemaVersion` becomes `15`.

- [ ] **Step 1: Write failing compatibility and round-trip tests**

Add tests that express the complete persisted contract before adding the types:

```swift
func testScientificWorkoutFieldsRoundTripAndLegacyFieldsRemainOptional() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let segment = CardioWorkloadSegment(
        startedAt: start,
        endedAt: start.addingTimeInterval(600),
        speedKph: 5,
        inclinePercent: 8,
        handrailSupport: .none,
        source: .userEntered
    )
    let response = SetHeartRateResponse(
        peakBPM: 168,
        peakDelaySeconds: 30,
        hrr60: 24,
        hrr120: 38,
        sourceName: "HUAWEI WATCH FIT 3",
        confidence: .derived
    )
    let set = SetResult(
        exerciseID: UUID(),
        exerciseName: "杠铃深蹲",
        setNumber: 1,
        loadKg: 100,
        reps: 5,
        rir: 1,
        completedAt: start.addingTimeInterval(40),
        startedAt: start,
        restEndedAt: start.addingTimeInterval(220),
        actualRestSeconds: 180,
        heartRateResponse: response
    )

    let data = try JSONEncoder().encode(set)
    XCTAssertEqual(try JSONDecoder().decode(SetResult.self, from: data), set)
    XCTAssertEqual(segment.durationSeconds, 600)
    XCTAssertEqual(AppSnapshot.currentSchemaVersion, 15)
}

func testSchemaFourteenSetStillDecodesWithoutScientificTimeline() throws {
    let old = """
    {
      "id":"00000000-0000-0000-0000-000000000001",
      "exerciseID":"00000000-0000-0000-0000-000000000002",
      "exerciseName":"卧推",
      "setNumber":1,
      "loadKg":80,
      "reps":8,
      "rir":1,
      "completedAt":"2026-07-26T10:00:00Z"
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let set = try decoder.decode(SetResult.self, from: Data(old.utf8))

    XCTAssertNil(set.startedAt)
    XCTAssertNil(set.restEndedAt)
    XCTAssertNil(set.actualRestSeconds)
    XCTAssertNil(set.heartRateResponse)
}
```

Add a cardio draft test:

```swift
func testCardioDraftPersistsInitialWorkloadAndConfirmedDistance() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let segment = CardioWorkloadSegment(
        startedAt: start,
        speedKph: 5,
        inclinePercent: 8,
        handrailSupport: .none,
        source: .userEntered
    )
    let draft = CardioSessionDraft(
        modality: .inclineWalking,
        intensity: .zone2,
        startedAt: start,
        workloadSegments: [segment],
        confirmedDistanceMeters: 5_000
    )

    let restored = try JSONDecoder().decode(
        CardioSessionDraft.self,
        from: JSONEncoder().encode(draft)
    )

    XCTAssertEqual(restored.workloadSegments, [segment])
    XCTAssertEqual(restored.confirmedDistanceMeters, 5_000)
}
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
swift test --filter DomainModelTests/testScientificWorkoutFieldsRoundTripAndLegacyFieldsRemainOptional
swift test --filter CardioSessionTests/testCardioDraftPersistsInitialWorkloadAndConfirmedDistance
```

Expected: compile failure because the new scientific workout contracts do not exist.

- [ ] **Step 3: Add the model contracts**

Implement the enums and value objects with exact raw values and optional defaults:

```swift
enum HandrailSupport: String, CaseIterable, Codable, Identifiable {
    case none
    case occasional
    case sustained
    var id: String { rawValue }
}

enum CardioWorkloadSource: String, Codable {
    case userEntered
    case device
    case derived
}

struct CardioWorkloadSegment: Identifiable, Codable, Equatable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date? = nil
    var speedKph: Double? = nil
    var inclinePercent: Double? = nil
    var powerWatts: Double? = nil
    var handrailSupport: HandrailSupport = .none
    var source: CardioWorkloadSource

    var durationSeconds: TimeInterval? {
        endedAt.map { max(0, $0.timeIntervalSince(startedAt)) }
    }
}

struct EnergyEstimateDiagnostics: Codable, Equatable {
    var primaryModel: String
    var inputsUsed: [String]
    var warnings: [String]
    var comparisonEstimateKcal: Double?
    var dataCoverage: Double
}

struct WorkoutPauseInterval: Codable, Equatable {
    var startedAt: Date
    var endedAt: Date?

    var durationSeconds: TimeInterval? {
        endedAt.map { max(0, $0.timeIntervalSince(startedAt)) }
    }
}

enum HeartRateIntensityZone: String, CaseIterable, Codable, Hashable {
    case veryLight
    case light
    case moderate
    case vigorous
    case nearMaximum
}

struct HeartRateIntensitySummary: Codable, Equatable {
    var secondsByZone: [HeartRateIntensityZone: Double]
    var zoneLoadAU: Double
    var aerobicBaseMinutes: Double
    var vigorousMinutes: Double
    var fatOxidationOpportunityMinutes: Double
    var coverage: Double
    var usedHeartRateReserve: Bool
    var confidence: DataConfidence
}

struct HeartRateDriftResult: Codable, Equatable {
    var percent: Double
    var confidence: DataConfidence
    var workloadCoverage: Double
    var heartRateCoverage: Double
}

struct SetHeartRateResponse: Codable, Equatable {
    var peakBPM: Double
    var peakDelaySeconds: Int
    var hrr60: Double?
    var hrr120: Double?
    var sourceName: String
    var confidence: DataConfidence
}

enum PersonalRecoveryComparison: String, Codable, Equatable {
    case insufficientHistory
    case withinBaseline
    case slowerThanBaseline
}
```

Use the following exact additions. Keep them in the named owning types so
synthesized `Codable` continues to decode omitted fields:

```swift
// CardioSessionDraft
var workloadSegments: [CardioWorkloadSegment] = []
var confirmedDistanceMeters: Double? = nil
var workloadWarnings: [String] = []

// CardioWorkoutRecord
var workloadSegments: [CardioWorkloadSegment]? = nil
var confirmedDistanceMeters: Double? = nil
var sensorDistanceMeters: Double? = nil
var energyDiagnostics: EnergyEstimateDiagnostics? = nil
var deviceActiveEnergyEstimateKcal: Double? = nil
var deviceEnergySource: MetricSource? = nil

// SetResult
var startedAt: Date? = nil
var restEndedAt: Date? = nil
var actualRestSeconds: Double? = nil
var heartRateResponse: SetHeartRateResponse? = nil
var isCompound: Bool? = nil
var restRecommendationSnapshot: RestRecommendation? = nil

// ExercisePrescription
var isCompound: Bool? = nil

// WorkoutDraft
var currentSetStartedAt: Date? = nil
var pauseIntervals: [WorkoutPauseInterval] = []
var currentPauseStartedAt: Date? = nil
var sessionRPE: Double? = nil

// WorkoutRecord
var pauseIntervals: [WorkoutPauseInterval]? = nil
var energyDiagnostics: EnergyEstimateDiagnostics? = nil
var deviceActiveEnergyEstimateKcal: Double? = nil
var deviceEnergySource: MetricSource? = nil

// EnergyEstimate
var diagnostics: EnergyEstimateDiagnostics? = nil
```

Extend `StrengthSummaryMetrics` with optional `averageSetDurationSeconds`,
`averageActualRestSeconds`, `workToRestRatio`, `performanceRetention`,
`restRecommendationAccuracy`, and `[SetHeartRateResponse]? heartRateResponses`.
Extend `CardioSummaryMetrics` with optional
`[HeartRateIntensityZone: Double] secondsByIntensityZone`, `zoneLoadAU`,
`aerobicBaseMinutes`, `vigorousMinutes`, `fatOxidationOpportunityMinutes`,
`cardiorespiratoryStimulus`, `heartRateDriftPercent`,
`heartRateDriftConfidence`, `workloadConsistency`,
`heartRateCoverage`, and `workloadCoverage`. Optional fields default to
`nil`. Retain `measuredActiveEnergyKcal` only for legacy decoding.
`TrainingEngine.makePrescription` copies `ExerciseOption.resolvedIsCompound`
into `ExercisePrescription.isCompound`; set completion copies that value into
`SetResult.isCompound`. Old prescriptions and results fall back to the
existing movement-pattern compound set
`[.squat, .hinge, .horizontalPush, .horizontalPull, .verticalPush,
.verticalPull, .singleLeg]`.

- [ ] **Step 4: Bump schema and verify old snapshots**

Set:

```swift
static let currentSchemaVersion = 15
```

Run:

```bash
swift test --filter DomainModelTests
swift test --filter AppStoreTests/testV06SnapshotRestoresAllRecordKindsAndPersistsCurrentSchema
swift test --filter CardioSessionTests
```

Expected: PASS, including legacy snapshot decoding.

- [ ] **Step 5: Commit**

```bash
git add FitTune/Models FitTuneTests/DomainModelTests.swift FitTuneTests/CardioSessionTests.swift
git commit -m "feat: add scientific workout data contracts"
```

---

### Task 2: Time-Weighted Heart-Rate Analysis

**Files:**

- Create: `FitTune/Engine/HeartRateAnalysisEngine.swift`
- Create: `FitTuneTests/HeartRateAnalysisEngineTests.swift`
- Modify: `Package.swift`

**Interfaces:**

- Produces: `HeartRateAnalysisEngine.intensitySummary(samples:startedAt:completedAt:restingHeartRate:maximumHeartRate:)`.
- Produces: `HeartRateAnalysisEngine.setResponse(samples:setStartedAt:setCompletedAt:nextSetStartedAt:)`.
- Produces: `HeartRateAnalysisEngine.drift(samples:workloads:startedAt:completedAt:)`.
- Uses only samples from one dominant source and intervals no longer than 15 seconds.

- [ ] **Step 1: Write failing time-weighting and delayed-peak tests**

Create `HeartRateAnalysisEngineTests.swift`:

```swift
final class HeartRateAnalysisEngineTests: XCTestCase {
    func testIntensityUsesElapsedTimeInsteadOfSampleCount() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "H10",
            confidence: .measured,
            coverage: 1
        )
        let samples = [
            WorkoutMetricSample(timestamp: start, heartRateBPM: 100, provenance: source),
            WorkoutMetricSample(timestamp: start.addingTimeInterval(300), heartRateBPM: 100, provenance: source),
            WorkoutMetricSample(timestamp: start.addingTimeInterval(305), heartRateBPM: 160, provenance: source),
            WorkoutMetricSample(timestamp: start.addingTimeInterval(310), heartRateBPM: 160, provenance: source)
        ]

        let result = try XCTUnwrap(HeartRateAnalysisEngine.intensitySummary(
            samples: samples,
            startedAt: start,
            completedAt: start.addingTimeInterval(600),
            restingHeartRate: 60,
            maximumHeartRate: 180
        ))

        XCTAssertLessThan(result.coverage, 0.05)
        XCTAssertLessThan(result.secondsByZone[.vigorous] ?? 0, 10)
    }

    func testSetResponseFindsPeakThirtySecondsAfterSetThenMeasuresFromPeak() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(30)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "FIT 3",
            confidence: .measured,
            coverage: 1
        )
        let samples = [
            WorkoutMetricSample(timestamp: end, heartRateBPM: 145, provenance: source),
            WorkoutMetricSample(timestamp: end.addingTimeInterval(30), heartRateBPM: 170, provenance: source),
            WorkoutMetricSample(timestamp: end.addingTimeInterval(90), heartRateBPM: 142, provenance: source),
            WorkoutMetricSample(timestamp: end.addingTimeInterval(150), heartRateBPM: 126, provenance: source)
        ]

        let response = try XCTUnwrap(HeartRateAnalysisEngine.setResponse(
            samples: samples,
            setStartedAt: start,
            setCompletedAt: end,
            nextSetStartedAt: nil
        ))

        XCTAssertEqual(response.peakBPM, 170)
        XCTAssertEqual(response.peakDelaySeconds, 30)
        XCTAssertEqual(response.hrr60 ?? 0, 28, accuracy: 0.1)
        XCTAssertEqual(response.hrr120 ?? 0, 44, accuracy: 0.1)
    }
}
```

Add these exact regressions in the same test file:

```swift
func testSetResponseExcludesPeakBeforeCurrentSetStart() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(30)
    let source = MetricProvenance(
        source: .bluetooth,
        sourceName: "H10",
        confidence: .measured,
        coverage: 1
    )
    let response = try XCTUnwrap(HeartRateAnalysisEngine.setResponse(
        samples: [
            .init(
                timestamp: start.addingTimeInterval(-10),
                heartRateBPM: 190,
                provenance: source
            ),
            .init(timestamp: end, heartRateBPM: 150, provenance: source),
            .init(
                timestamp: end.addingTimeInterval(25),
                heartRateBPM: 170,
                provenance: source
            )
        ],
        setStartedAt: start,
        setCompletedAt: end,
        nextSetStartedAt: nil
    ))
    XCTAssertEqual(response.peakBPM, 170)
}

func testSampleAt119SecondsAfterPeakCannotBecomeHRR60() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(30)
    let source = MetricProvenance(
        source: .bluetooth,
        sourceName: "H10",
        confidence: .measured,
        coverage: 1
    )
    let peakAt = end.addingTimeInterval(30)
    let response = try XCTUnwrap(HeartRateAnalysisEngine.setResponse(
        samples: [
            .init(timestamp: peakAt, heartRateBPM: 170, provenance: source),
            .init(
                timestamp: peakAt.addingTimeInterval(119),
                heartRateBPM: 130,
                provenance: source
            )
        ],
        setStartedAt: start,
        setCompletedAt: end,
        nextSetStartedAt: nil
    ))
    XCTAssertNil(response.hrr60)
    XCTAssertEqual(response.hrr120, 40)
}

func testRecoveryWindowRejectsSourceSwitchAndMissingSamples() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(30)
    let h10 = MetricProvenance(
        source: .bluetooth,
        sourceName: "H10",
        confidence: .measured,
        coverage: 1
    )
    let watch = MetricProvenance(
        source: .appleWatch,
        sourceName: "Apple Watch",
        confidence: .measured,
        coverage: 1
    )
    let peakAt = end.addingTimeInterval(30)
    let switched = try XCTUnwrap(HeartRateAnalysisEngine.setResponse(
        samples: [
            .init(timestamp: peakAt, heartRateBPM: 170, provenance: h10),
            .init(
                timestamp: peakAt.addingTimeInterval(60),
                heartRateBPM: 140,
                provenance: watch
            )
        ],
        setStartedAt: start,
        setCompletedAt: end,
        nextSetStartedAt: nil
    ))
    XCTAssertNil(switched.hrr60)
    XCTAssertNil(switched.hrr120)
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter HeartRateAnalysisEngineTests
```

Expected: compile failure because `HeartRateAnalysisEngine` is absent.

- [ ] **Step 3: Implement interval normalization and intensity integration**

Create a stateless engine. The core interval rule must be explicit:

```swift
private static func validHeartRateIntervals(
    samples: [WorkoutMetricSample],
    startedAt: Date,
    completedAt: Date
) -> [(start: Date, end: Date, bpm: Double, source: String)] {
    let valid = samples
        .compactMap { sample -> (Date, Double, String)? in
            guard let bpm = sample.heartRateBPM,
                  (40...220).contains(bpm),
                  sample.timestamp >= startedAt,
                  sample.timestamp <= completedAt else { return nil }
            return (sample.timestamp, bpm, sample.provenance.sourceName)
        }
        .sorted { $0.0 < $1.0 }

    return zip(valid, valid.dropFirst()).compactMap { left, right in
        let seconds = right.0.timeIntervalSince(left.0)
        guard seconds > 0, seconds <= 15, left.2 == right.2 else { return nil }
        return (left.0, right.0, (left.1 + right.1) / 2, left.2)
    }
}
```

Classify HRR into `<30`, `30...39`, `40...59`, `60...89`, and `>=90%`; multiply zone minutes by `1...5` for `zoneLoadAU`.

- [ ] **Step 4: Implement per-set peak and exact recovery windows**

Use:

- Peak window: set start through set end +45 seconds.
- HRR60 window: peak +55 through +65 seconds.
- HRR120 window: peak +115 through +125 seconds.
- Median within the target window.
- No result after `nextSetStartedAt`.
- No result when the peak/recovery source changes.

Do not reuse `now`, arrival order, or a global 180-second maximum.

- [ ] **Step 5: Implement stable-workload drift**

Return drift only when:

- elapsed duration is at least 20 minutes;
- at least 80% of elapsed time has workload segments;
- speed, incline, and power remain within 5% between compared halves;
- heart-rate coverage is at least 60%.

Use:

```swift
driftPercent = (secondHalfBPM - firstHalfBPM) / firstHalfBPM * 100
```

- [ ] **Step 6: Add source files and verify GREEN**

Add `Engine/HeartRateAnalysisEngine.swift` to `Package.swift`.

Run:

```bash
swift test --filter HeartRateAnalysisEngineTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Package.swift FitTune/Engine/HeartRateAnalysisEngine.swift FitTuneTests/HeartRateAnalysisEngineTests.swift
git commit -m "feat: analyze time-weighted workout heart rate"
```

---

### Task 3: Activity-Specific Cardio Energy

**Files:**

- Create: `FitTune/Engine/CardioEnergyEstimator.swift`
- Create: `FitTuneTests/CardioEnergyEstimatorTests.swift`
- Modify: `FitTune/Engine/TrainingEngine.swift`
- Modify: `FitTune/Engine/EnergyEngine.swift`
- Modify: `Package.swift`

**Interfaces:**

- Produces: `CardioEnergyInput`.
- Produces: `CardioEnergyEstimator.estimate(_:) -> EnergyEstimate`.
- Preserves: `TrainingEngine.cardioEnergyEstimate(...)` and `makeCardioWorkout(...)` as wrappers.
- Sets: `EnergyEngine.algorithmVersion = "1.2.0-scientific-energy-1"`.

Define the input with this complete signature:

```swift
struct CardioEnergyInput {
    var modality: CardioModality
    var intensity: CardioIntensity
    var startedAt: Date
    var completedAt: Date
    var weightKg: Double
    var profile: UserProfile?
    var confirmedDistanceKm: Double?
    var sensorDistanceKm: Double?
    var workloadSegments: [CardioWorkloadSegment]
    var metricSamples: [WorkoutMetricSample]
    var deviceEstimateKcal: Double?
    var deviceEnergySource: MetricSource?
    var importedDeviceOnly: Bool
}
```

- [ ] **Step 1: Write failing ACSM segment and device-comparison tests**

Create `CardioEnergyEstimatorTests.swift`:

```swift
func testOneHourInclineWalkUsesACSMSegmentsForAbout427ActiveKcal() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let input = CardioEnergyInput(
        modality: .inclineWalking,
        intensity: .zone2,
        startedAt: start,
        completedAt: start.addingTimeInterval(3_600),
        weightKg: 70,
        profile: nil,
        confirmedDistanceKm: 5,
        sensorDistanceKm: nil,
        workloadSegments: [
            .init(
                startedAt: start,
                endedAt: start.addingTimeInterval(3_600),
                speedKph: 5,
                inclinePercent: 8,
                handrailSupport: .none,
                source: .userEntered
            )
        ],
        metricSamples: [],
        deviceEstimateKcal: 166,
        deviceEnergySource: .appleWatch,
        importedDeviceOnly: false
    )

    let estimate = CardioEnergyEstimator.estimate(input)

    XCTAssertEqual(estimate.kilocalories, 427, accuracy: 1)
    XCTAssertEqual(estimate.diagnostics?.comparisonEstimateKcal, 166)
    XCTAssertTrue(estimate.method.contains("ACSM"))
    XCTAssertGreaterThan(estimate.lowerBound, 300)
}

func testTwoInclineSegmentsIntegrateTheirOwnSpeedAndGrade() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let segments = [
        CardioWorkloadSegment(
            startedAt: start,
            endedAt: start.addingTimeInterval(1_800),
            speedKph: 4.5,
            inclinePercent: 6,
            source: .userEntered
        ),
        CardioWorkloadSegment(
            startedAt: start.addingTimeInterval(1_800),
            endedAt: start.addingTimeInterval(3_600),
            speedKph: 5.5,
            inclinePercent: 10,
            source: .userEntered
        )
    ]

    let estimate = CardioEnergyEstimator.estimate(CardioEnergyInput(
        modality: .inclineWalking,
        intensity: .zone2,
        startedAt: start,
        completedAt: start.addingTimeInterval(3_600),
        weightKg: 70,
        profile: nil,
        confirmedDistanceKm: nil,
        sensorDistanceKm: nil,
        workloadSegments: segments,
        metricSamples: [],
        deviceEstimateKcal: nil,
        deviceEnergySource: nil,
        importedDeviceOnly: false
    ))

    XCTAssertNotEqual(estimate.kilocalories, TrainingEngine.netActiveEnergy(
        met: 6.5,
        weightKg: 70,
        minutes: 60
    ))
}
```

Also add tests for:

- speed-distance mismatch greater than 15%;
- sustained handrail support demoting ACSM from the primary model;
- heart-rate gaps filled by modality MET without double counting;
- device-only imported records using at least a 25% interval;
- cycling power using an 18%...25% efficiency range;
- manual device estimates never claiming Apple Watch provenance.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter CardioEnergyEstimatorTests
```

Expected: compile failure because `CardioEnergyInput` and `CardioEnergyEstimator` are absent.

- [ ] **Step 3: Implement ACSM segment integration**

Use the exact active-energy equations:

```swift
private static func acsmActiveKcal(
    speedKph: Double,
    inclinePercent: Double,
    minutes: Double,
    weightKg: Double,
    running: Bool
) -> Double {
    let speed = speedKph * 1_000 / 60
    let grade = min(0.40, max(0, inclinePercent / 100))
    let netVO2 = running
        ? 0.2 * speed + 0.9 * speed * grade
        : 0.1 * speed + 1.8 * speed * grade
    return max(0, netVO2 * weightKg / 1_000 * 5 * minutes)
}
```

Finalize open segments at `completedAt`, clip overlapping/out-of-session ranges, and sum each valid segment once.

- [ ] **Step 4: Implement candidate selection and diagnostics**

Use this selection order:

1. ACSM for unsupported walking/running with valid workload coverage.
2. Cycling power range for stable power.
3. Time-weighted Keytel heart rate when demographics are complete and coverage is at least 60%.
4. Modality/intensity MET.
5. Device estimate only when the record has no other usable source.

When speed-integrated distance and confirmed distance differ by more than 15%, append a warning and widen the range to at least `+/-25%`. Sustained handrail support makes ACSM a comparison upper check; it must not remain `primaryModel`.

- [ ] **Step 5: Keep compatibility wrappers**

`TrainingEngine.cardioEnergyEstimate` should create one finalized workload segment from legacy `speedKph`, `inclinePercent`, and duration, then delegate:

```swift
return CardioEnergyEstimator.estimate(
    CardioEnergyInput(
        modality: modality,
        intensity: intensity,
        startedAt: startedAt ?? .now.addingTimeInterval(-Double(minutes) * 60),
        completedAt: (startedAt ?? .now.addingTimeInterval(-Double(minutes) * 60))
            .addingTimeInterval(Double(minutes) * 60),
        weightKg: weightKg,
        profile: profile,
        confirmedDistanceKm: distanceKm,
        sensorDistanceKm: nil,
        workloadSegments: legacySegments,
        metricSamples: metricSamples,
        deviceEstimateKcal: measuredActiveEnergy,
        deviceEnergySource: measuredActiveEnergy == nil ? nil : .unknown,
        importedDeviceOnly: false
    )
)
```

Do not retain the old branch that returns device energy first.

- [ ] **Step 6: Add the package source and verify GREEN**

Add `Engine/CardioEnergyEstimator.swift` to `Package.swift`.

Run:

```bash
swift test --filter CardioEnergyEstimatorTests
swift test --filter TrainingEngineTests
swift test --filter EnergyEngineTests
```

Expected: PASS after updating old watch-first assertions to comparison semantics.

- [ ] **Step 7: Commit**

```bash
git add Package.swift FitTune/Engine/CardioEnergyEstimator.swift FitTune/Engine/TrainingEngine.swift FitTune/Engine/EnergyEngine.swift FitTuneTests/CardioEnergyEstimatorTests.swift FitTuneTests/TrainingEngineTests.swift FitTuneTests/EnergyEngineTests.swift
git commit -m "feat: estimate cardio energy from activity-specific inputs"
```

---

### Task 4: Structure-Aware Strength Energy

**Files:**

- Create: `FitTune/Engine/StrengthEnergyEstimator.swift`
- Create: `FitTuneTests/StrengthEnergyEstimatorTests.swift`
- Modify: `FitTune/Engine/TrainingEngine.swift`
- Modify: `Package.swift`

**Interfaces:**

- Produces: `StrengthEnergyEstimator.estimate(record:weightKg:profile:)`.
- Preserves: `TrainingEngine.strengthEnergyEstimate(record:weightKg:profile:)`.
- Consumes: real session-RPE, set kinds/timestamps, pause intervals, movement patterns, and raw heart-rate samples.

- [ ] **Step 1: Write failing structure and device tests**

```swift
func testDenseCompoundSessionExceedsSparseIsolationAtSameWallTime() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let sparse = makeRecord(
        start: start,
        durationMinutes: 60,
        sessionRPE: 5,
        sets: makeTimedSets(count: 4, pattern: .arms, start: start, restSeconds: 600)
    )
    let dense = makeRecord(
        start: start,
        durationMinutes: 60,
        sessionRPE: 8,
        sets: makeTimedSets(count: 15, pattern: .squat, start: start, restSeconds: 180)
    )

    let sparseEstimate = StrengthEnergyEstimator.estimate(
        record: sparse,
        weightKg: 70,
        profile: nil
    )
    let denseEstimate = StrengthEnergyEstimator.estimate(
        record: dense,
        weightKg: 70,
        profile: nil
    )

    XCTAssertGreaterThan(denseEstimate.kilocalories, sparseEstimate.kilocalories * 1.5)
}

func testFiveKcalDeviceEstimateDoesNotOverrideOneHourStrengthModel() {
    var record = makeDenseRecord()
    record.deviceActiveEnergyEstimateKcal = 5

    let estimate = StrengthEnergyEstimator.estimate(
        record: record,
        weightKg: 70,
        profile: nil
    )

    XCTAssertGreaterThan(estimate.kilocalories, 100)
    XCTAssertEqual(estimate.diagnostics?.comparisonEstimateKcal, 5)
}

private func makeTimedSets(
    count: Int,
    pattern: MovementPattern,
    start: Date,
    restSeconds: TimeInterval
) -> [SetResult] {
    let exerciseID = UUID()
    return (0..<count).map { index in
        let setStart = start.addingTimeInterval(Double(index) * restSeconds)
        let setEnd = setStart.addingTimeInterval(30)
        let nextStart = index + 1 < count
            ? start.addingTimeInterval(Double(index + 1) * restSeconds)
            : nil
        return SetResult(
            exerciseID: exerciseID,
            exerciseName: pattern == .arms ? "弯举" : "杠铃深蹲",
            setNumber: index + 1,
            loadKg: pattern == .arms ? 12 : 100,
            reps: pattern == .arms ? 12 : 8,
            rir: pattern == .arms ? 3 : 1,
            completedAt: setEnd,
            movementPattern: pattern,
            techniqueQuality: 4,
            setKind: .working,
            startedAt: setStart,
            restEndedAt: nextStart,
            actualRestSeconds: nextStart.map { $0.timeIntervalSince(setEnd) }
        )
    }
}

private func makeRecord(
    start: Date,
    durationMinutes: Int,
    sessionRPE: Double,
    sets: [SetResult]
) -> WorkoutRecord {
    WorkoutRecord(
        sessionName: "测试力量训练",
        startedAt: start,
        completedAt: start.addingTimeInterval(Double(durationMinutes) * 60),
        readinessScore: 80,
        sets: sets,
        sessionRPE: sessionRPE,
        pauseIntervals: []
    )
}

private func makeDenseRecord() -> WorkoutRecord {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    return makeRecord(
        start: start,
        durationMinutes: 60,
        sessionRPE: 8,
        sets: makeTimedSets(
            count: 15,
            pattern: .squat,
            start: start,
            restSeconds: 180
        )
    )
}
```

Add tests for pause exclusion, no session-RPE, low heart rate, short heart-rate peaks, and EPOC not being added.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter StrengthEnergyEstimatorTests
```

Expected: compile failure because `StrengthEnergyEstimator` is absent.

- [ ] **Step 3: Implement effective duration and session classification**

Calculate:

```swift
effectiveSeconds = wallClockSeconds - completedPauseSeconds
density = workingSetCount / max(effectiveSeconds / 60, 1)
compoundShare = compoundWorkingSets / max(workingSetCount, 1)
```

Use transparent Compendium categories:

- `3.0 MET`: no more than 4 working sets or density below `0.08 sets/min`.
- `6.0 MET`: session-RPE at least 8, at least 10 working sets, density at least `0.15 sets/min`, and compound share at least 0.5.
- `3.5 MET`: all other traditional multiple-exercise sessions.

These are explicit engineering classification rules over published MET categories. Save the chosen category and inputs in diagnostics.

- [ ] **Step 4: Bound heart-rate influence**

If demographics are complete and valid heart-rate coverage exists, calculate a time-weighted Keytel comparison. Clamp its effect:

```swift
let lower = structuralKcal * 0.85
let upper = structuralKcal * 1.15
let center = min(upper, max(lower, heartRateKcal))
```

The final uncertainty remains at least `+/-25%`; missing session-RPE or missing timeline widens it to `+/-35%`. Add `"EPOC 未计入本次主动热量"` to warnings.

- [ ] **Step 5: Delegate from TrainingEngine and verify GREEN**

Add `Engine/StrengthEnergyEstimator.swift` to `Package.swift`, replace the old strength fallback/time-series implementation with:

```swift
static func strengthEnergyEstimate(
    record: WorkoutRecord,
    weightKg: Double,
    profile: UserProfile? = nil
) -> EnergyEstimate {
    StrengthEnergyEstimator.estimate(
        record: record,
        weightKg: weightKg,
        profile: profile
    )
}
```

Run:

```bash
swift test --filter StrengthEnergyEstimatorTests
swift test --filter TrainingEngineTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift FitTune/Engine/StrengthEnergyEstimator.swift FitTune/Engine/TrainingEngine.swift FitTuneTests/StrengthEnergyEstimatorTests.swift FitTuneTests/TrainingEngineTests.swift
git commit -m "feat: estimate strength energy from session structure"
```

---

### Task 5: Evidence-Based and Personally Calibrated Rest

**Files:**

- Modify: `FitTune/Engine/TrainingEngine.swift`
- Modify: `FitTune/Engine/LiveAdaptationEngine.swift`
- Modify: `FitTuneTests/TrainingEngineTests.swift`
- Modify: `FitTuneTests/LiveAdaptationEngineTests.swift`
- Modify: `FitTuneTests/Fixtures/RestRecommendationBenchmarks.json`

**Interfaces:**

- Produces: `StrengthRestContext`.
- Extends: `TrainingEngine.recommendRest(...context:)`.
- Replaces fixed `12/22 bpm` rules with `PersonalRecoveryComparison`.
- Keeps heart rate advisory-only.

Use these exact contracts:

```swift
struct StrengthRestContext: Equatable {
    var goal: StrengthTrainingGoal
    var isCompound: Bool
}

struct LiveHeartRateSignal: Equatable {
    var response: SetHeartRateResponse?
    var personalComparison: PersonalRecoveryComparison
    var sourceName: String
    var currentHeartRate: Double? = nil
}
```

- [ ] **Step 1: Write failing goal-floor and personal-recovery tests**

```swift
func testMaxStrengthCompoundRestStartsAtThreeToFiveMinutes() {
    let set = SetResult(
        exerciseID: UUID(),
        exerciseName: "杠铃深蹲",
        setNumber: 1,
        loadKg: 120,
        reps: 4,
        rir: 1,
        movementPattern: .squat
    )
    let rest = TrainingEngine.recommendRest(
        current: set,
        previous: nil,
        setKind: .working,
        pattern: .squat,
        historicalE1RM: 150,
        readiness: readyAssessment,
        context: .init(goal: .maxStrength, isCompound: true)
    )

    XCTAssertEqual(rest.lowerSeconds, 180)
    XCTAssertEqual(rest.upperSeconds, 300)
}

func testSlowerThanPersonalRecoveryExtendsButFasterRecoveryNeverShortensFloor() {
    let slow = LiveAdaptationEngine.adapt(
        baseRecommendation: baseRecommendation,
        baseRest: baseRest,
        currentLoadKg: 100,
        liveSignal: .init(
            response: setResponse,
            personalComparison: .slowerThanBaseline,
            sourceName: "FIT 3"
        ),
        calibrationPairs: 6,
        hasPain: false,
        painAlertThresholdReached: false,
        maximumHeartRateAlert: nil
    )
    let fast = LiveAdaptationEngine.adapt(
        baseRecommendation: baseRecommendation,
        baseRest: baseRest,
        currentLoadKg: 100,
        liveSignal: .init(
            response: setResponse,
            personalComparison: .withinBaseline,
            sourceName: "FIT 3"
        ),
        calibrationPairs: 6,
        hasPain: false,
        painAlertThresholdReached: false,
        maximumHeartRateAlert: nil
    )

    XCTAssertGreaterThan(slow.rest.recommendedSeconds, baseRest.recommendedSeconds)
    XCTAssertGreaterThanOrEqual(fast.rest.recommendedSeconds, baseRest.lowerSeconds)
    XCTAssertLessThanOrEqual(fast.nextLoadKg, 100)
}

private var setResponse: SetHeartRateResponse {
    .init(
        peakBPM: 170,
        peakDelaySeconds: 30,
        hrr60: 18,
        hrr120: 32,
        sourceName: "FIT 3",
        confidence: .derived
    )
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter TrainingEngineTests/testMaxStrengthCompoundRestStartsAtThreeToFiveMinutes
swift test --filter LiveAdaptationEngineTests
```

Expected: compile failure because the context and personal comparison interfaces do not exist.

- [ ] **Step 3: Implement evidence floors**

Implement exact floors:

- warmup `60...120`;
- endurance/light isolation `60...120`;
- hypertrophy isolation `90...180`;
- hypertrophy compound `120...240`;
- max-strength compound or low-rep/high-relative-load `180...300`.

RIR 0, RIR 1, low readiness, and comparable-set performance loss may extend the recommendation but not exceed 300 seconds before manual user extension.

Define one historical comparable pair as adjacent sets that satisfy every
condition: same canonical exercise, same `SetKind`, load difference no more
than `max(2.5 kg, 5%)`, repetition difference no more than `2`, RIR
difference no more than `1`, both sets have explicit timing, the first has
actual rest, neither set reports pain/technique breakdown, and no pause
overlaps that rest. Define next-set performance retention as the mean of
available, capped `0...1.2` ratios for e1RM and repetitions, plus technique
quality ratio when both values exist. Do not compare backoff/drop/AMRAP sets
to ordinary working sets.

At five or more comparable pairs, use the median actual rest among pairs with
retention at least `0.95` as the personal-rest candidate, rounded up to 15
seconds and clamped inside the evidence range. A personal candidate may
change the midpoint within the range; it never changes the lower evidence
floor.

- [ ] **Step 4: Remove universal strength HRR thresholds**

Change `LiveHeartRateSignal` to the exact contract above. Rename
`calibrationSessions` to `calibrationPairs`. Remove:

```swift
recovery < 12
recovery < 22
```

Only `.slowerThanBaseline` extends rest and blocks an increase.
`.insufficientHistory` displays the response without changing the base
result. Confidence becomes `.measured` only at five or more valid comparison
pairs.

For personal heart-rate comparison, use only historical responses from those
same comparable pairs. Mark `.slowerThanBaseline` when current HRR60 or
HRR120 is below its personal median by more than
`max(1.5 * medianAbsoluteDeviation, 5 bpm)` for HRR60 or
`max(1.5 * medianAbsoluteDeviation, 8 bpm)` for HRR120. Missing windows return
`.insufficientHistory`; never substitute a population threshold. A slower
comparison extends the midpoint by 60 seconds, capped at 300 seconds, and
never lowers the floor.

- [ ] **Step 5: Verify GREEN and fixture**

In `RestRecommendationBenchmarks.json`, change only the existing
`algorithmVersion` value to `1.2.0-strength-rest-1`; retain every other
fixture key and value.

Run:

```bash
swift test --filter TrainingEngineTests
swift test --filter LiveAdaptationEngineTests
swift test --filter BenchmarkFixtureTests/testRestAndE1RMBenchmarks
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add FitTune/Engine/TrainingEngine.swift FitTune/Engine/LiveAdaptationEngine.swift FitTuneTests/TrainingEngineTests.swift FitTuneTests/LiveAdaptationEngineTests.swift FitTuneTests/Fixtures/RestRecommendationBenchmarks.json
git commit -m "feat: predict strength rest from goals and personal recovery"
```

---

### Task 6: Cardio Workload Lifecycle

**Files:**

- Modify: `FitTune/Store/AppStore.swift`
- Modify: `FitTuneTests/CardioSessionTests.swift`
- Modify: `FitTuneTests/AppStoreTests.swift`

**Interfaces:**

- Changes: `startCardioSession(modality:intensity:speedKph:inclinePercent:powerWatts:handrailSupport:at:)`, where all workload values default to `nil`, handrail defaults to `.none`, and `at` defaults to `.now`.
- Produces: `updateCardioWorkload(speedKph:inclinePercent:powerWatts:handrailSupport:at:)`.
- Produces: `setConfirmedCardioDistance(meters:)`.
- Finalizes open segments before calling `CardioEnergyEstimator`.

Use these exact signatures:

```swift
func startCardioSession(
    modality: CardioModality,
    intensity: CardioIntensity,
    speedKph: Double? = nil,
    inclinePercent: Double? = nil,
    powerWatts: Double? = nil,
    handrailSupport: HandrailSupport = .none,
    at startedAt: Date = .now
)

func updateCardioWorkload(
    speedKph: Double?,
    inclinePercent: Double?,
    powerWatts: Double?,
    handrailSupport: HandrailSupport,
    at changedAt: Date = .now
)

func setConfirmedCardioDistance(meters: Double?)
```

- [ ] **Step 1: Write failing store lifecycle tests**

```swift
func testLiveCardioKeepsAndSegmentsInitialTreadmillWorkload() throws {
    let defaults = makeDefaults()
    let store = AppStore(defaults: defaults)
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.startCardioSession(
        modality: .inclineWalking,
        intensity: .zone2,
        speedKph: 5,
        inclinePercent: 8,
        powerWatts: nil,
        handrailSupport: .none,
        at: start
    )
    store.updateCardioWorkload(
        speedKph: 5.5,
        inclinePercent: 10,
        powerWatts: nil,
        handrailSupport: .occasional,
        at: start.addingTimeInterval(1_800)
    )

    let draft = try XCTUnwrap(store.activeCardioDraft)
    XCTAssertEqual(draft.workloadSegments.count, 2)
    XCTAssertEqual(draft.workloadSegments[0].endedAt, start.addingTimeInterval(1_800))
    XCTAssertEqual(draft.workloadSegments[1].speedKph, 5.5)
}

func testFinishedCardioUsesConfirmedDistanceAndKeepsDeviceEnergyAsComparison() throws {
    let store = configuredStore(weightKg: 70)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    store.startCardioSession(
        modality: .inclineWalking,
        intensity: .zone2,
        speedKph: 5,
        inclinePercent: 8,
        at: start
    )
    store.setConfirmedCardioDistance(meters: 5_000)
    store.appendCardioMetricSample(watchEnergySample(kcal: 166, at: start))

    let record = try XCTUnwrap(store.finishCardioSession(
        status: .completed,
        at: start.addingTimeInterval(3_600)
    ))

    XCTAssertEqual(record.activeEnergyKcal, 427, accuracy: 1)
    XCTAssertEqual(record.energyDiagnostics?.comparisonEstimateKcal, 166)
    XCTAssertEqual(record.distanceKm, 5)
}

private func configuredStore(weightKg: Double) -> AppStore {
    let store = AppStore(defaults: makeDefaults())
    store.weightHistory = [
        WeightEntry(
            date: Date(timeIntervalSince1970: 1_699_999_000),
            kilograms: weightKg,
            source: "测试"
        )
    ]
    return store
}

private func watchEnergySample(kcal: Double, at date: Date) -> WorkoutMetricSample {
    WorkoutMetricSample(
        timestamp: date,
        activeEnergyKcal: kcal,
        provenance: MetricProvenance(
            source: .appleWatch,
            sourceName: "Apple Watch",
            confidence: .estimated,
            coverage: 1
        )
    )
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter CardioSessionTests/testLiveCardioKeepsAndSegmentsInitialTreadmillWorkload
swift test --filter AppStoreTests/testFinishedCardioUsesConfirmedDistanceAndKeepsDeviceEnergyAsComparison
```

Expected: compile failure because the lifecycle methods do not accept workload inputs.

- [ ] **Step 3: Implement draft lifecycle**

On start, create one open workload segment only if speed, incline, power, or non-default handrail state exists. On update, close the prior open segment at the update time and append a new segment. Ignore a byte-for-byte identical update.

On finish:

- close the final segment at `completedAt`;
- use confirmed distance first, sensor distance second;
- call `CardioEnergyEstimator`;
- persist diagnostics and device comparison;
- generate the summary from the finalized record.

- [ ] **Step 4: Fix legacy current-record behavior**

`currentEnergyRecord(_ cardio:)` may recompute old records only when they contain valid legacy speed/incline or raw samples sufficient for the new estimator. Records with neither retain their saved center and receive a legacy warning; they must not be silently interpreted as a new workload.

- [ ] **Step 5: Verify GREEN**

Run:

```bash
swift test --filter CardioSessionTests
swift test --filter AppStoreTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add FitTune/Store/AppStore.swift FitTuneTests/CardioSessionTests.swift FitTuneTests/AppStoreTests.swift
git commit -m "feat: persist live cardio workload segments"
```

---

### Task 7: Strength Set Timeline, Recovery, Pauses, and Session-RPE

**Files:**

- Modify: `FitTune/Store/AppStore.swift`
- Modify: `FitTuneTests/AppStoreTests.swift`
- Modify: `FitTuneTests/WorkoutLifecycleTests.swift`

**Interfaces:**

- Produces: `startCurrentDraftSet(at: Date = .now)`.
- Changes: `completeCurrentDraftSet(at: Date = .now)`.
- Changes: `advanceDraftToNextSet(at: Date = .now)`.
- Produces: `pauseWorkout(at: Date = .now)`, `resumeWorkout(at: Date = .now)`.
- Produces: `setWorkoutSessionRPE(_:)`.
- Changes: `saveActiveWorkout(status:at:)`, with `at completedAt: Date = .now`.
- Uses `HeartRateAnalysisEngine.setResponse` and personal comparable-pair history.

- [ ] **Step 1: Write failing timeline tests**

```swift
func testExplicitSetStartAndNextSetPersistActualTimeline() throws {
    let store = makeStrengthStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.startCurrentDraftSet(at: start)
    store.completeCurrentDraftSet(at: start.addingTimeInterval(35))
    store.advanceDraftToNextSet(at: start.addingTimeInterval(215))

    let set = try XCTUnwrap(store.activeWorkoutDraft?.results.first)
    XCTAssertEqual(set.startedAt, start)
    XCTAssertEqual(set.completedAt, start.addingTimeInterval(35))
    XCTAssertEqual(set.restEndedAt, start.addingTimeInterval(215))
    XCTAssertEqual(set.actualRestSeconds, 180)
}

func testPauseTimeIsExcludedAndRealSessionRPEIsSaved() throws {
    let store = makeStrengthStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    store.startCurrentDraftSet(at: start)
    store.completeCurrentDraftSet(at: start.addingTimeInterval(30))
    store.pauseWorkout(at: start.addingTimeInterval(60))
    store.resumeWorkout(at: start.addingTimeInterval(660))
    store.setWorkoutSessionRPE(8)

    let record = try XCTUnwrap(store.saveActiveWorkout(
        status: .partial,
        at: start.addingTimeInterval(1_200)
    ))

    XCTAssertEqual(record.sessionRPE, 8)
    XCTAssertEqual(record.pauseIntervals?.first?.durationSeconds, 600)
}

private func makeStrengthStore() -> AppStore {
    let suite = "FitTuneTests.StrengthTimeline.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = AppStore(defaults: defaults)
    let exercise = ExercisePrescription(
        name: "杠铃深蹲",
        pattern: .squat,
        sets: 3,
        repLower: 5,
        repUpper: 8,
        targetRIR: 1,
        isPriority: true,
        workingSets: 3
    )
    store.startWorkout(
        TrainingSession(name: "腿", focus: "股四头", exercises: [exercise])
    )
    return store
}
```

Add a test that streams a peak 30 seconds after completion and verifies it is attached to the last `SetResult`, not a previous set.
Add the helper above independently to both test classes that use it; test
files do not share private helpers.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter WorkoutLifecycleTests/testExplicitSetStartAndNextSetPersistActualTimeline
swift test --filter AppStoreTests/testPauseTimeIsExcludedAndRealSessionRPEIsSaved
```

Expected: compile failure because explicit set and pause lifecycle APIs are absent.

- [ ] **Step 3: Implement lifecycle state**

`startCurrentDraftSet` changes `.training` to `.setActive` and records `currentSetStartedAt`. `completeCurrentDraftSet` accepts `.setActive`; legacy programmatic calls from old tests may still complete from `.training` but leave `startedAt` nil and therefore low-confidence.

`advanceDraftToNextSet` writes `restEndedAt` and `actualRestSeconds` into the just-completed result before clearing rest state.
When `completeCurrentDraftSet` creates the result, copy
`currentExercise.isCompound` (or the documented pattern fallback) into
`SetResult.isCompound`. After calculating rest, copy the exact
`RestRecommendation` into `restRecommendationSnapshot` on that result so the
later summary can audit whether actual rest and next-set performance agreed
with the recommendation.

Pausing closes no set automatically. A pause interval is appended and must be closed before another set starts or the workout is saved.

- [ ] **Step 4: Replace milestone heart-rate handling**

On each valid sample during rest:

1. identify the last completed set with `startedAt`;
2. recompute its response from all same-session samples using `HeartRateAnalysisEngine`;
3. store a changed response on that set;
4. compare only against historical same-exercise, same-kind, similar-load/RIR pairs;
5. require five valid pairs before returning anything except `.insufficientHistory`;
6. pass the comparison to `LiveAdaptationEngine`.

Remove `liveRecoveryMilestonesApplied` and the `restStartedAt - 180` global peak logic after migration compatibility is preserved.

- [ ] **Step 5: Stop deriving session-RPE from RIR**

Persist `draft.sessionRPE`. On save, pass it directly to `WorkoutRecord`. If absent, leave it nil and let the strength estimator widen its range.

Device energy should be saved to `deviceActiveEnergyEstimateKcal` and diagnostics, not `measuredActiveEnergyKcal`.

- [ ] **Step 6: Verify GREEN**

Run:

```bash
swift test --filter WorkoutLifecycleTests
swift test --filter AppStoreTests
swift test --filter LiveAdaptationEngineTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add FitTune/Store/AppStore.swift FitTuneTests/AppStoreTests.swift FitTuneTests/WorkoutLifecycleTests.swift
git commit -m "feat: record strength set and recovery timelines"
```

---

### Task 8: Scientific Cardio and Strength Summaries

**Files:**

- Modify: `FitTune/Engine/SummaryEngine.swift`
- Modify: `FitTune/Engine/TrainingEngine.swift`
- Modify: `FitTuneTests/SummaryEngineTests.swift`

**Interfaces:**

- Sets: `SummaryEngine.algorithmVersion = "1.2.0-workout-effect-1"`.
- Uses: `HeartRateAnalysisEngine.intensitySummary`, `.drift`, and stored `SetHeartRateResponse`.
- Produces: time-weighted cardio dose and explainable strength efficiency components.

- [ ] **Step 1: Write failing summary tests**

```swift
func testCardioSummaryReportsTimeWeightedHRRLoadAndFatOxidationOpportunity() throws {
    let record = makeSteadyInclineRecord(
        durationMinutes: 60,
        heartRateBPM: 125,
        restingHeartRate: 60,
        maximumHeartRate: 180
    )

    let summary = SummaryEngine.cardioSummary(
        for: record,
        restingHeartRate: 60,
        maximumHeartRate: 180
    )

    XCTAssertGreaterThan(summary.cardio?.aerobicBaseMinutes ?? 0, 50)
    XCTAssertGreaterThan(summary.cardio?.fatOxidationOpportunityMinutes ?? 0, 50)
    XCTAssertGreaterThan(summary.cardio?.zoneLoadAU ?? 0, 0)
    XCTAssertNil(summary.cardio?.vo2Max)
}

func testVariableWorkloadDoesNotInventHeartRateDrift() {
    let summary = SummaryEngine.cardioSummary(
        for: makeVariableIntervalRecord(),
        restingHeartRate: 60,
        maximumHeartRate: 180
    )

    XCTAssertNil(summary.cardio?.heartRateDriftPercent)
}

func testStrengthSummaryShowsActualRestAndPerformanceRetention() {
    let summary = SummaryEngine.strengthSummary(
        for: makeTimedStrengthRecord(),
        bodyWeightKg: 70,
        maximumHeartRate: 180
    )

    XCTAssertEqual(summary.strength?.averageActualRestSeconds, 180)
    XCTAssertNotNil(summary.strength?.performanceRetention)
    XCTAssertFalse(summary.strength?.heartRateResponses.isEmpty ?? true)
}

private func makeSteadyInclineRecord(
    durationMinutes: Int,
    heartRateBPM: Double,
    restingHeartRate: Double,
    maximumHeartRate: Double
) -> CardioWorkoutRecord {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(Double(durationMinutes) * 60)
    let provenance = MetricProvenance(
        source: .bluetooth,
        sourceName: "H10",
        confidence: .measured,
        coverage: 1
    )
    var record = CardioWorkoutRecord(
        date: start,
        modality: .inclineWalking,
        intensity: .zone2,
        durationMinutes: durationMinutes,
        distanceKm: 5,
        averageHeartRate: heartRateBPM,
        activeEnergyKcal: 427,
        source: "FitTune"
    )
    record.workloadSegments = [
        CardioWorkloadSegment(
            startedAt: start,
            endedAt: end,
            speedKph: 5,
            inclinePercent: 8,
            source: .userEntered
        )
    ]
    record.metricSamples = stride(
        from: 0.0,
        through: Double(durationMinutes) * 60,
        by: 10
    ).map {
        WorkoutMetricSample(
            timestamp: start.addingTimeInterval($0),
            heartRateBPM: heartRateBPM,
            provenance: provenance
        )
    }
    return record
}

private func makeVariableIntervalRecord() -> CardioWorkoutRecord {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let midpoint = start.addingTimeInterval(900)
    let end = start.addingTimeInterval(1_800)
    var record = makeSteadyInclineRecord(
        durationMinutes: 30,
        heartRateBPM: 140,
        restingHeartRate: 60,
        maximumHeartRate: 180
    )
    record.workloadSegments = [
        .init(
            startedAt: start,
            endedAt: midpoint,
            speedKph: 4,
            inclinePercent: 4,
            source: .userEntered
        ),
        .init(
            startedAt: midpoint,
            endedAt: end,
            speedKph: 8,
            inclinePercent: 10,
            source: .userEntered
        )
    ]
    return record
}

private func makeTimedStrengthRecord() -> WorkoutRecord {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let exerciseID = UUID()
    let response = SetHeartRateResponse(
        peakBPM: 165,
        peakDelaySeconds: 30,
        hrr60: 22,
        hrr120: 36,
        sourceName: "H10",
        confidence: .derived
    )
    let firstEnd = start.addingTimeInterval(30)
    let secondStart = firstEnd.addingTimeInterval(180)
    return WorkoutRecord(
        sessionName: "腿",
        startedAt: start,
        completedAt: start.addingTimeInterval(600),
        readinessScore: 80,
        sets: [
            SetResult(
                exerciseID: exerciseID,
                exerciseName: "杠铃深蹲",
                setNumber: 1,
                loadKg: 100,
                reps: 8,
                rir: 1,
                completedAt: firstEnd,
                movementPattern: .squat,
                techniqueQuality: 4,
                setKind: .working,
                startedAt: start,
                restEndedAt: secondStart,
                actualRestSeconds: 180,
                heartRateResponse: response
            ),
            SetResult(
                exerciseID: exerciseID,
                exerciseName: "杠铃深蹲",
                setNumber: 2,
                loadKg: 100,
                reps: 8,
                rir: 1,
                completedAt: secondStart.addingTimeInterval(30),
                movementPattern: .squat,
                techniqueQuality: 4,
                setKind: .working,
                startedAt: secondStart,
                heartRateResponse: response
            )
        ],
        sessionRPE: 8
    )
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter SummaryEngineTests
```

Expected: compile failures because the new summary fields and resting-heart-rate input are absent.

- [ ] **Step 3: Implement cardio dose summary**

Use time-weighted HRR when both resting and maximum heart rate exist. Fall back to `%HRmax` with `estimated` confidence. Populate:

- seconds and percentage by intensity;
- zone-load AU;
- `40...59% HRR` aerobic-base minutes;
- `>=60% HRR` vigorous minutes;
- `40...65% HRR` fat-oxidation-opportunity minutes;
- stable-workload drift;
- workload and heart-rate coverage.

Do not calculate fat grams, VO2max, or a long-term improvement percentage.

- [ ] **Step 4: Implement strength summary components**

Calculate:

- median/mean valid set duration;
- mean actual rest;
- work-to-rest time ratio;
- comparable-set performance retention from e1RM/reps/RIR;
- target-set completion;
- stored per-set heart-rate responses.

Do not emit one synthetic efficiency percentage.

- [ ] **Step 5: Verify GREEN**

Run:

```bash
swift test --filter SummaryEngineTests
swift test --filter AppStoreTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add FitTune/Engine/SummaryEngine.swift FitTune/Engine/TrainingEngine.swift FitTuneTests/SummaryEngineTests.swift
git commit -m "feat: summarize scientific workout dose and recovery"
```

---

### Task 9: Live Cardio Input and Feedback UI

**Files:**

- Modify: `FitTune/Views/TodayView.swift`
- Modify: `FitTune/Views/CardioSessionView.swift`
- Modify: `FitTune/Engine/WorkoutActivitySnapshot.swift`
- Modify: `FitTuneTests/CardioSessionTests.swift`

**Interfaces:**

- Consumes Task 6 store lifecycle.
- Displays current speed, incline, handrail state, sensor distance, confirmed treadmill distance, and data warnings.
- Keeps existing heart-rate reconnect alert.

- [ ] **Step 1: Re-run the store regression before UI wiring**

Task 6 already added the pure store-facing RED/GREEN coverage for preserving
these values. Add this second regression only if the exact case is not already
present:

```swift
func testCardioEntryConfigurationStartsLiveSessionWithoutDroppingInputs() {
    let store = AppStore(defaults: makeDefaults())
    store.startCardioSession(
        modality: .inclineWalking,
        intensity: .zone2,
        speedKph: 5.2,
        inclinePercent: 9,
        powerWatts: nil,
        handrailSupport: .occasional
    )

    XCTAssertEqual(store.activeCardioDraft?.currentWorkload?.speedKph, 5.2)
    XCTAssertEqual(store.activeCardioDraft?.currentWorkload?.inclinePercent, 9)
    XCTAssertEqual(store.activeCardioDraft?.currentWorkload?.handrailSupport, .occasional)
}
```

Run:

```bash
swift test --filter CardioSessionTests/testCardioEntryConfigurationStartsLiveSessionWithoutDroppingInputs
```

Expected: PASS before the view edit. This is intentionally not described as a
failing UI test: a store test cannot prove a SwiftUI button closure is wired.
The view wiring is verified by compilation and the visual acceptance in
Steps 4 and Task 13.

- [ ] **Step 2: Wire TodayView into the live draft**

Pass `cardioSpeedKph`, `cardioInclinePercent`, `cardioPowerWatts`, and handrail state to `startCardioSession`. Remove the statement that watch active energy is automatically preferred.

- [ ] **Step 3: Add compact live controls**

In `CardioSessionView`:

- use `NumericInputControl` for speed, incline, and treadmill distance;
- use a segmented `Picker` for handrail support;
- show current sensor distance separately;
- write changes through `updateCardioWorkload`;
- keep stable chip dimensions and allow labels to wrap without overlap.

Do not nest a new card inside `sessionMetrics`; place workload controls as an unframed full-width section below the primary metrics.

- [ ] **Step 4: Build and verify**

Run:

```bash
swift test --filter CardioSessionTests
xcodebuild -project FitTune.xcodeproj -scheme FitTune -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS and `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add FitTune/Views/TodayView.swift FitTune/Views/CardioSessionView.swift FitTune/Engine/WorkoutActivitySnapshot.swift FitTuneTests/CardioSessionTests.swift
git commit -m "feat: record live treadmill workload"
```

---

### Task 10: Strength Timing, Session-RPE, and Summary UI

**Files:**

- Modify: `FitTune/Views/WorkoutSessionView.swift`
- Modify: `FitTune/Views/WorkoutSummaryView.swift`
- Modify: `FitTune/Views/HistoryDetailView.swift`
- Modify: `FitTune/Views/AlgorithmInfoView.swift`

**Interfaces:**

- Consumes Task 7 explicit set lifecycle and Task 8 summary metrics.
- Adds start/finish set states, pause/resume icon, end-of-session RPE, delayed-peak status, and explainable summary rows.

- [ ] **Step 1: Wire explicit set state**

Use one stable primary action location:

```swift
switch draft.phase {
case .training:
    Button { store.startCurrentDraftSet() } label: {
        Label("开始本组", systemImage: "play.fill")
    }
case .setActive:
    Button { store.completeCurrentDraftSet() } label: {
        Label("完成本组", systemImage: "checkmark")
    }
case .resting, .exerciseComplete:
    EmptyView()
}
```

Show a monospaced set timer during `.setActive`. Do not let the label resize the surrounding layout.

- [ ] **Step 2: Add pause and session-RPE**

Add a top-bar pause/resume icon with an accessibility label. Before a completed or partial save, present a compact session-RPE `1...10` control; save only after the user confirms. Do not restore the old per-set-RIR-derived session-RPE.

- [ ] **Step 3: Show honest recovery status**

During rest, show one of:

- `正在确认组后心率峰值`;
- `峰值延后 N 秒`;
- `峰后 60 秒恢复 X bpm`;
- `样本不足，保持基础休息建议`;
- `个人校准中 N/5`;
- `已结合个人同动作恢复`.

No text may claim a universal heart-rate recovery threshold.

- [ ] **Step 4: Render scientific summaries**

Cardio:

- intensity minutes/percentages;
- zone-load AU;
- aerobic-base and vigorous minutes;
- fat-oxidation opportunity;
- drift only when present;
- active-energy model, range, warnings, device comparison.

Strength:

- real session-RPE;
- set/rest timing;
- work-to-rest ratio;
- performance retention;
- delayed peak/HRR per set;
- structural energy model, range, warnings, device comparison.

Update `AlgorithmInfoView` to state `专项机械模型 -> 心率 -> MET -> 仅设备降级`, and add links from the spec evidence list.

- [ ] **Step 5: Build and inspect at two text sizes**

Run:

```bash
xcodebuild -project FitTune.xcodeproj -scheme FitTune -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Then launch the simulator and inspect the cardio live page, strength preparation/set/rest states, and both summaries at default and accessibility-large text. Verify no overlap, clipped labels, nested cards, or shifting metric tiles.

- [ ] **Step 6: Commit**

```bash
git add FitTune/Views/WorkoutSessionView.swift FitTune/Views/WorkoutSummaryView.swift FitTune/Views/HistoryDetailView.swift FitTune/Views/AlgorithmInfoView.swift
git commit -m "feat: present scientific workout timing and effects"
```

---

### Task 11: Restore App Icon and Integrate New Sources in Xcode

**Files:**

- Create: `FitTune/Resources/Assets.xcassets/Contents.json`
- Create: `FitTune/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Copy: `FitTune/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- Modify: `FitTune.xcodeproj/project.pbxproj`

**Interfaces:**

- Adds all three new engines and all three new tests to Xcode.
- Adds `Assets.xcassets` to FitTune resources.
- Sets `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
- Bumps all app/watch/widget version settings to `1.2.0 (13)`.

- [ ] **Step 1: Verify the pre-change icon check fails**

Run:

```bash
test -f FitTune/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

Expected: non-zero because the current branch has no icon catalog.

- [ ] **Step 2: Restore the exact original asset**

Copy only this binary:

```bash
cp /Users/lindui017/Documents/fit/.worktrees/app-icon/FitTune/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png FitTune/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

Create the catalog JSON matching the original worktree. Verify:

```bash
sips -g pixelWidth -g pixelHeight -g hasAlpha -g space FitTune/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
shasum -a 256 FitTune/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

Expected: `1024`, `1024`, `no`, `RGB`, and `7c9f22ee4f28402e1fa6fe7c103b52be6febb70ff763c084f4ccc020f99b5fc7`.

- [ ] **Step 3: Add deterministic PBX entries**

Use unused IDs:

- `C...48/B...48`: `HeartRateAnalysisEngine.swift`
- `C...49/B...49`: `CardioEnergyEstimator.swift`
- `C...4A/B...4A`: `StrengthEnergyEstimator.swift`
- `C...4B/B...4B`: `HeartRateAnalysisEngineTests.swift`
- `C...4C/B...4C`: `CardioEnergyEstimatorTests.swift`
- `C...4D/B...4D`: `StrengthEnergyEstimatorTests.swift`
- `C...4E/B...4E`: `Assets.xcassets`

Add production files to the Engine group and app Sources, test files to FitTuneTests and test Sources, and the asset catalog to Resources and the app resource build phase.

- [ ] **Step 4: Set icon and release version**

Add to FitTune Debug and Release:

```text
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
```

Change every target's `CURRENT_PROJECT_VERSION` from `12` to `13` and `MARKETING_VERSION` from `1.1.1` to `1.2.0`.

- [ ] **Step 5: Validate Xcode integration**

Run:

```bash
plutil -lint FitTune.xcodeproj/project.pbxproj
xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: no duplicate PBX IDs, no missing source, no App Icon warning, both builds succeed.

- [ ] **Step 6: Commit**

```bash
git add FitTune.xcodeproj/project.pbxproj FitTune/Resources/Assets.xcassets
git commit -m "chore: restore FitTune icon and prepare 1.2.0"
```

---

### Task 12: Benchmarks, Export, and Scientific Documentation

**Files:**

- Modify: `FitTuneTests/Fixtures/EnergyBenchmarks.json`
- Modify: `FitTuneTests/BenchmarkFixtureTests.swift`
- Modify: `FitTune/Services/DataExportService.swift`
- Modify: `FitTuneTests/DataExportServiceTests.swift`
- Modify: `docs/scientific-basis.md`
- Modify: `SCIENTIFIC_BASIS.md`
- Modify: `README.md`
- Modify: `VALIDATION.md`

**Interfaces:**

- Locks the `427 kcal` ACSM benchmark and the new algorithm versions.
- Exports workload, diagnostics, set timing, actual rest, and device comparison.
- Documents formula scope and non-claims.

- [ ] **Step 1: Write failing benchmark and export tests**

Extend the existing single `EnergyBenchmarks.json` object; do not replace its
daily-energy keys. Its complete post-change shape is:

```json
{
  "algorithmVersion": "1.2.0-scientific-energy-1",
  "basis": "Workout-specific models own workout energy; device energy is comparison only. Daily measured active energy remains a separate daily aggregate.",
  "resting": 1700,
  "strength": 200,
  "cardio": 150,
  "walking": 100,
  "measuredActive": 600,
  "expectedTotal": 2300,
  "tolerance": 0.001,
  "inclineWeightKg": 70,
  "inclineMinutes": 60,
  "inclineSpeedKph": 5,
  "inclinePercent": 8,
  "expectedInclineActiveKcal": 427,
  "inclineTolerance": 1
}
```

Extend the private `EnergyFixture` decoder in
`BenchmarkFixtureTests.swift` with:

```swift
let inclineWeightKg: Double
let inclineMinutes: Double
let inclineSpeedKph: Double
let inclinePercent: Double
let expectedInclineActiveKcal: Double
let inclineTolerance: Double
```

Add an export assertion:

```swift
func testWorkoutExportsIncludeScientificEnergyAndTimelineFields() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let response = SetHeartRateResponse(
        peakBPM: 165,
        peakDelaySeconds: 30,
        hrr60: 20,
        hrr120: 34,
        sourceName: "H10",
        confidence: .derived
    )
    let set = SetResult(
        exerciseID: UUID(),
        exerciseName: "深蹲",
        setNumber: 1,
        loadKg: 100,
        reps: 8,
        rir: 1,
        completedAt: start.addingTimeInterval(30),
        movementPattern: .squat,
        setKind: .working,
        startedAt: start,
        restEndedAt: start.addingTimeInterval(210),
        actualRestSeconds: 180,
        heartRateResponse: response
    )
    var strength = WorkoutRecord(
        sessionName: "腿",
        startedAt: start,
        completedAt: start.addingTimeInterval(600),
        readinessScore: 80,
        sets: [set]
    )
    strength.energyDiagnostics = EnergyEstimateDiagnostics(
        primaryModel: "Compendium structural MET",
        inputsUsed: ["working_sets"],
        warnings: ["EPOC 未计入本次主动热量"],
        comparisonEstimateKcal: 166,
        dataCoverage: 1
    )
    var cardio = CardioWorkoutRecord(
        date: start,
        modality: .inclineWalking,
        intensity: .zone2,
        durationMinutes: 10,
        activeEnergyKcal: 71,
        source: "FitTune"
    )
    cardio.workloadSegments = [
        .init(
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            speedKph: 5,
            inclinePercent: 8,
            source: .userEntered
        )
    ]
    let csv = DataExportService.workoutsCSV(
        workouts: [strength],
        cardio: [cardio]
    )
    let setsCSV = DataExportService.setsCSV(workouts: [strength])

    XCTAssertTrue(csv.contains("energy_primary_model"))
    XCTAssertTrue(csv.contains("device_energy_comparison_kcal"))
    XCTAssertTrue(csv.contains("workload_segments"))
    XCTAssertTrue(setsCSV.contains("actual_rest_seconds"))
    XCTAssertTrue(setsCSV.contains("peak_delay_seconds"))
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter BenchmarkFixtureTests
swift test --filter DataExportServiceTests/testWorkoutExportsIncludeScientificEnergyAndTimelineFields
```

Expected: fixture decoding/export header failures.

- [ ] **Step 3: Update fixtures and export**

Keep JSON valid and export raw values without localized formatting. Add corresponding set CSV columns for:

- `started_at`
- `completed_at`
- `actual_rest_seconds`
- `peak_bpm`
- `peak_delay_seconds`
- `hrr60`
- `hrr120`

- [ ] **Step 4: Update scientific docs**

Document:

- ACSM net equations and validation-range uncertainty;
- HRR time weighting and zone-load weights;
- Keytel's group-level limitations;
- device energy as comparison;
- strength structural MET classification;
- delayed peak windows;
- PCr/rest evidence;
- fat-oxidation opportunity, no fat grams;
- no EPOC addition.

Append the actual `1.2.0` validation results to `VALIDATION.md` only after Task 13 commands finish; do not invent counts.

- [ ] **Step 5: Verify GREEN**

Run:

```bash
swift test --filter BenchmarkFixtureTests
swift test --filter DataExportServiceTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add FitTuneTests/Fixtures FitTuneTests/BenchmarkFixtureTests.swift FitTune/Services/DataExportService.swift FitTuneTests/DataExportServiceTests.swift docs/scientific-basis.md SCIENTIFIC_BASIS.md README.md VALIDATION.md
git commit -m "docs: document and export scientific workout estimates"
```

---

### Task 13: Full Verification, Review, and Install Readiness

**Files:**

- Modify only if verification finds an in-scope defect.
- Add simulator screenshots under `Screenshots/` only after visual verification.

**Interfaces:**

- Produces reviewed, tested, install-ready `1.2.0 (13)` source and an unsigned
  Release verification artifact.
- Does not install to the user's phone until the user is asked to connect it.

- [ ] **Step 1: Run package tests from a clean invocation**

Run:

```bash
swift test
```

Expected: all tests pass, zero failures, no unexpected warnings. Record the exact count.

- [ ] **Step 2: Validate project structure**

Run:

```bash
git diff --check
plutil -lint FitTune.xcodeproj/project.pbxproj
xcodebuild -list -project FitTune.xcodeproj
```

Expected: clean diff, valid project, FitTune shared scheme present.

- [ ] **Step 3: Run simulator tests**

Run:

```bash
xcodebuild -project FitTune.xcodeproj \
  -scheme FitTune \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Run Debug and Release builds**

Run:

```bash
xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO clean build
xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/FitTune-1.2.0-release CODE_SIGNING_ALLOWED=NO clean build
xcodebuild -project FitTune.xcodeproj -target FitTuneWatch -configuration Release CODE_SIGNING_ALLOWED=NO build
```

Expected: all requested targets build.

- [ ] **Step 5: Verify the built icon and bundle metadata**

Inspect the built app:

```bash
plutil -p /tmp/FitTune-1.2.0-release/Build/Products/Release-iphoneos/FitTune.app/Info.plist
find /tmp/FitTune-1.2.0-release/Build/Products/Release-iphoneos/FitTune.app \( -iname '*AppIcon*' -o -iname 'Assets.car' \)
```

Expected: bundle ID `com.codex.fittune`, version `1.2.0`, build `13`, compiled asset catalog present.

- [ ] **Step 6: Complete simulator visual acceptance**

Use a fresh simulator installation and verify:

- initial incline speed/grade survives live start;
- changing incline creates a new visible current value without resetting distance;
- 60-minute `70 kg / 5 km/h / 8%` fixture shows about `427 kcal` and a range;
- device `166 kcal` appears only as comparison;
- strength set start/finish timer is stable;
- delayed peak status does not announce 60-second recovery before the peak window;
- session-RPE is requested at save;
- cardio and strength summaries fit standard and accessibility-large text;
- restored app icon appears on the simulator home screen.

Save representative screenshots only after checking that no controls or text overlap.

- [ ] **Step 7: Update validation evidence**

Append exact test counts, build results, screenshots, version, and remaining hardware-only checks to `VALIDATION.md`. Commit only verified facts:

```bash
git add VALIDATION.md Screenshots
git commit -m "test: verify FitTune 1.2.0 scientific workout update"
```

After Task 13, the SDD controller performs the skill-mandated whole-branch
review. Confirmed findings receive one reviewed fix wave and Steps 1 through 5
are rerun when production code changes.

## Post-Plan Release Handoff

Only after the whole-branch review is clean:

1. synchronize the exact reviewed commit into `/Users/lindui017/Documents/fit`;
2. build a signed iPhone Release app from that exact source state;
3. verify the signed app still has Bundle ID `com.codex.fittune`, version
   `1.2.0`, and build `13`;
4. then ask the user to connect, unlock, and trust the iPhone;
5. install with the same Bundle ID without uninstalling or clearing data;
6. launch and confirm the installed version and restored icon.
