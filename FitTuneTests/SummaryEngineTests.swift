import XCTest
@testable import FitTune

final class SummaryEngineTests: XCTestCase {
    func testStrengthSummaryContainsHeartRateVolumeFailureAndValidE1RM() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let provenance = MetricProvenance(source: .bluetooth, sourceName: "H10", confidence: .measured, coverage: 1)
        let warmup = SetResult(exerciseID: UUID(), exerciseName: "杠铃卧推", setNumber: 1, loadKg: 40, reps: 10, rir: 5, movementPattern: .horizontalPush, setKind: .warmup)
        let work1 = SetResult(exerciseID: UUID(), exerciseName: "杠铃卧推", setNumber: 2, loadKg: 80, reps: 8, rir: 0, movementPattern: .horizontalPush, setKind: .working)
        let work2 = SetResult(exerciseID: UUID(), exerciseName: "杠铃卧推", setNumber: 3, loadKg: 80, reps: 20, rir: 0, movementPattern: .horizontalPush, setKind: .working)
        var record = WorkoutRecord(sessionName: "胸", startedAt: start, completedAt: start.addingTimeInterval(600), readinessScore: 80, sets: [warmup, work1, work2])
        record.activeEnergyKcal = 120
        record.energyMethod = "FitTune 心率 + 力量模型估算"
        record.energyLowerBoundKcal = 100
        record.energyUpperBoundKcal = 140
        record.energyAlgorithmVersion = EnergyEngine.algorithmVersion
        record.metricSamples = [
            .init(timestamp: start, heartRateBPM: 100, provenance: provenance),
            .init(timestamp: start.addingTimeInterval(300), heartRateBPM: 150, provenance: provenance)
        ]

        let summary = SummaryEngine.strengthSummary(for: record, bodyWeightKg: 70)

        XCTAssertEqual(summary.averageHeartRate, 125)
        XCTAssertEqual(summary.maximumHeartRate, 150)
        XCTAssertEqual(summary.heartRateSourceName, "H10")
        XCTAssertEqual(summary.heartRateConfidence, .measured)
        XCTAssertEqual(summary.strength?.workingSetCount, 2)
        XCTAssertEqual(summary.strength?.warmupSetCount, 1)
        XCTAssertEqual(summary.strength?.failureRate, 1)
        XCTAssertEqual(summary.strength?.volumeLoadKg, 80 * 8 + 80 * 20)
        XCTAssertEqual(summary.strength?.bestE1RMKg, TrainingEngine.estimatedOneRepMax(loadKg: 80, reps: 8, rir: 0))
        XCTAssertEqual(summary.activeEnergyKcal?.lowerBound, 100)
        XCTAssertEqual(summary.activeEnergyKcal?.upperBound, 140)
        XCTAssertEqual(summary.activeEnergyKcal?.provenance.sourceName, "FitTune 心率 + 力量模型估算")
        XCTAssertEqual(summary.activeEnergyKcal?.provenance.confidence, .derived)
        XCTAssertEqual(summary.activeEnergyKcal?.provenance.algorithmVersion, EnergyEngine.algorithmVersion)
    }

    func testCardioSummaryShowsVerifiableMetricsWithoutInventingVO2Max() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let provenance = MetricProvenance(source: .phoneSensor, sourceName: "iPhone", confidence: .measured, coverage: 0.8)
        var record = CardioWorkoutRecord(date: start, modality: .running, intensity: .zone2, durationMinutes: 30, distanceKm: 5, averageHeartRate: 145, activeEnergyKcal: 300, source: "手机估算")
        record.energyMethod = "FitTune 心率 + 有氧模型估算"
        record.energyLowerBoundKcal = 240
        record.energyUpperBoundKcal = 360
        record.energyAlgorithmVersion = EnergyEngine.algorithmVersion
        record.metricSamples = [
            .init(timestamp: start, heartRateBPM: 130, cadence: 165, distanceMeters: 0, provenance: provenance),
            .init(timestamp: start.addingTimeInterval(1800), heartRateBPM: 155, cadence: 175, distanceMeters: 5000, provenance: provenance)
        ]

        let summary = SummaryEngine.cardioSummary(for: record)

        XCTAssertEqual(summary.averageHeartRate, 142.5)
        XCTAssertEqual(summary.maximumHeartRate, 155)
        XCTAssertEqual(summary.cardio?.distanceKm, 5)
        XCTAssertEqual(summary.cardio?.averageCadence, 170)
        XCTAssertEqual(summary.cardio?.paceSecondsPerKm, 360)
        XCTAssertNil(summary.cardio?.vo2Max)
        XCTAssertEqual(summary.activeEnergyKcal?.lowerBound, 240)
        XCTAssertEqual(summary.activeEnergyKcal?.upperBound, 360)
        XCTAssertEqual(summary.activeEnergyKcal?.provenance.sourceName, "FitTune 心率 + 有氧模型估算")
        XCTAssertEqual(summary.activeEnergyKcal?.provenance.confidence, .derived)
    }

    func testStrengthSummaryDoesNotTreatZeroMeasuredEnergyAsDeviceMeasurement() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let record = WorkoutRecord(
            sessionName: "力量",
            startedAt: start,
            completedAt: start.addingTimeInterval(3_600),
            readinessScore: 80,
            sets: [],
            activeEnergyKcal: 220,
            measuredActiveEnergyKcal: 0,
            energyMethod: "2024 Adult Compendium MET + session-RPE"
        )

        let summary = SummaryEngine.strengthSummary(for: record, bodyWeightKg: 70)

        XCTAssertEqual(summary.activeEnergyKcal?.provenance.source, .historicalModel)
        XCTAssertEqual(summary.activeEnergyKcal?.provenance.confidence, .estimated)
    }

    func testHuaweiRevisionChangesSummaryOnlyNotOriginalRawRecord() {
        let record = WorkoutRecord(sessionName: "背", startedAt: .now, completedAt: .now, readinessScore: 80, sets: [])
        let original = record
        let summary = SummaryEngine.strengthSummary(for: record, bodyWeightKg: 70)
        let revision = SummaryRevision(reason: "华为健康事后同步", summary: summary)

        XCTAssertEqual(record, original)
        XCTAssertEqual(revision.reason, "华为健康事后同步")
        XCTAssertEqual(revision.summary.algorithmVersion, SummaryEngine.algorithmVersion)
    }

    func testCardioSummaryReportsTimeWeightedHRRLoadAndFatOxidationOpportunity() throws {
        let record = makeSteadyInclineRecord(
            durationMinutes: 60,
            heartRateBPM: 125
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
        XCTAssertFalse(summary.strength?.heartRateResponses?.isEmpty ?? true)
    }

    func testCardioSummaryPersistsHRRMethodAndFallbackConfidence() {
        let record = makeSteadyInclineRecord(durationMinutes: 30, heartRateBPM: 125)

        let hrrSummary = SummaryEngine.cardioSummary(
            for: record,
            restingHeartRate: 60,
            maximumHeartRate: 180
        )
        let fallbackSummary = SummaryEngine.cardioSummary(
            for: record,
            maximumHeartRate: 180
        )

        XCTAssertEqual(hrrSummary.cardio?.usedHeartRateReserve, true)
        XCTAssertEqual(hrrSummary.cardio?.intensityConfidence, .derived)
        XCTAssertEqual(fallbackSummary.cardio?.usedHeartRateReserve, false)
        XCTAssertEqual(fallbackSummary.cardio?.intensityConfidence, .estimated)
        XCTAssertNil(fallbackSummary.cardio?.fatOxidationOpportunityMinutes)
    }

    func testCardioSummaryUsesElapsedTimeForIntensityPercentages() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let provenance = MetricProvenance(source: .bluetooth, sourceName: "H10", confidence: .measured, coverage: 1)
        var record = CardioWorkoutRecord(
            date: start,
            modality: .cycling,
            intensity: .intervals,
            durationMinutes: 1,
            activeEnergyKcal: 1,
            source: "FitTune"
        )
        record.metricSamples = [
            .init(timestamp: start, heartRateBPM: 100, provenance: provenance),
            .init(timestamp: start.addingTimeInterval(5), heartRateBPM: 100, provenance: provenance),
            .init(timestamp: start.addingTimeInterval(10), heartRateBPM: 160, provenance: provenance),
            .init(timestamp: start.addingTimeInterval(25), heartRateBPM: 160, provenance: provenance),
            .init(timestamp: start.addingTimeInterval(30), heartRateBPM: 160, provenance: provenance)
        ]

        let summary = SummaryEngine.cardioSummary(
            for: record,
            restingHeartRate: 60,
            maximumHeartRate: 180
        )

        XCTAssertEqual(summary.cardio?.percentageByIntensityZone?[.light] ?? -1, 1.0 / 6.0, accuracy: 0.001)
        XCTAssertEqual(summary.cardio?.percentageByIntensityZone?[.moderate] ?? -1, 1.0 / 6.0, accuracy: 0.001)
        XCTAssertEqual(summary.cardio?.percentageByIntensityZone?[.vigorous] ?? -1, 2.0 / 3.0, accuracy: 0.001)
    }

    func testStrengthSummaryReportsCompleteTargetWorkingSetsFromPlanSnapshot() {
        let summary = SummaryEngine.strengthSummary(
            for: makePlanSnapshotStrengthRecord(completedWorkingSets: 2),
            bodyWeightKg: 70
        )

        XCTAssertEqual(summary.strength?.targetWorkingSetCount, 2)
        XCTAssertEqual(summary.strength?.targetSetCompletion, 1)
    }

    func testStrengthSummaryReportsPartialTargetWorkingSetsFromPlanSnapshot() {
        let summary = SummaryEngine.strengthSummary(
            for: makePlanSnapshotStrengthRecord(completedWorkingSets: 1),
            bodyWeightKg: 70
        )

        XCTAssertEqual(summary.strength?.targetWorkingSetCount, 2)
        XCTAssertEqual(summary.strength?.targetSetCompletion, 0.5)
    }

    func testStrengthSummaryLeavesTargetWorkingSetCompletionUnavailableWithoutPlanSnapshot() {
        let record = WorkoutRecord(
            sessionName: "腿",
            startedAt: .now,
            completedAt: .now.addingTimeInterval(60),
            readinessScore: 80,
            sets: []
        )

        let summary = SummaryEngine.strengthSummary(for: record, bodyWeightKg: 70)

        XCTAssertNil(summary.strength?.targetWorkingSetCount)
        XCTAssertNil(summary.strength?.targetSetCompletion)
    }

    private func makeSteadyInclineRecord(
        durationMinutes: Int,
        heartRateBPM: Double
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
            heartRateBPM: 140
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

    private func makePlanSnapshotStrengthRecord(completedWorkingSets: Int) -> WorkoutRecord {
        let exerciseID = UUID()
        let prescription = ExercisePrescription(
            id: exerciseID,
            name: "杠铃深蹲",
            pattern: .squat,
            sets: 2,
            repLower: 6,
            repUpper: 10,
            targetRIR: 1,
            isPriority: true,
            workingSets: 2
        )
        let snapshot = PlanSnapshot(
            sourcePlanRuleVersion: "test",
            sourceSessionID: UUID(),
            planTitle: "测试计划",
            sessionName: "腿",
            goal: .generalFitness,
            split: .fullBody,
            equipment: .fullGym,
            exercises: [prescription]
        )
        return WorkoutRecord(
            sessionName: "腿",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_600),
            readinessScore: 80,
            sets: (1...completedWorkingSets).map { number in
                SetResult(
                    exerciseID: exerciseID,
                    exerciseName: "杠铃深蹲",
                    setNumber: number,
                    loadKg: 100,
                    reps: 8,
                    rir: 1,
                    setKind: .working
                )
            },
            planSnapshot: snapshot
        )
    }
}
