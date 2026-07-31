import XCTest
@testable import FitTune

final class DataExportServiceTests: XCTestCase {
    func testJSONExportRoundTripsSnapshotIncludingRawMetricsAndRevisions() throws {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let sample = WorkoutMetricSample(timestamp: date, heartRateBPM: 142, provenance: .init(source: .bluetooth, sourceName: "胸带", confidence: .measured, coverage: 1))
        let record = WorkoutRecord(sessionName: "胸,肩", startedAt: date.addingTimeInterval(-60), completedAt: date, readinessScore: 80, sets: [], metricSamples: [sample], summaryRevisions: [.init(reason: "华为同步", summary: WorkoutSummary(generatedAt: date, algorithmVersion: "1"))])
        let snapshot = AppSnapshot(profile: nil, plan: nil, readiness: ReadinessInput(), workoutHistory: [record], weightHistory: [])

        let data = try DataExportService.json(snapshot: snapshot)
        let decoded = try DataExportService.restoreJSON(data)

        XCTAssertEqual(decoded.workoutHistory.first?.sessionName, "胸,肩")
        XCTAssertEqual(decoded.workoutHistory.first?.metricSamples?.first?.heartRateBPM, 142)
        XCTAssertEqual(decoded.workoutHistory.first?.summaryRevisions?.count, 1)
    }

    func testCSVUsesStableDecimalAndEscapesCommaQuoteAndNewline() throws {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let set = SetResult(exerciseID: UUID(), exerciseName: "划船, \"窄握\"\n变式", setNumber: 1, loadKg: 42.5, reps: 8, rir: 1, completedAt: date, setKind: .working)
        let record = WorkoutRecord(sessionName: "背", startedAt: date.addingTimeInterval(-60), completedAt: date, readinessScore: 80, sets: [set])

        let csv = DataExportService.setsCSV(workouts: [record])

        XCTAssertTrue(csv.contains("42.5"))
        XCTAssertTrue(csv.contains("\"划船, \"\"窄握\"\"\n变式\""))
        XCTAssertTrue(csv.hasPrefix("workout_id,"))
    }

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

    func testSportsCSVIncludesAnalysisProvenanceAndRawMetrics() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let draft = SportSessionDraft(kind: .trailRunning, environment: .outdoor, intensity: .training, startedAt: start)
        let analysis = SportAnalysisEngine.analyze(
            draft: draft,
            completedAt: start.addingTimeInterval(3_600),
            sessionRPE: 7,
            weightKg: 70,
            restingHeartRate: nil,
            maximumHeartRate: nil
        )
        let record = SportSessionRecord(
            kind: .trailRunning,
            environment: .outdoor,
            intensity: .training,
            startedAt: start,
            completedAt: start.addingTimeInterval(3_600),
            completionStatus: .completed,
            sessionRPE: 7,
            analysis: analysis
        )

        let csv = DataExportService.sportsCSV(sports: [record])

        XCTAssertTrue(csv.hasPrefix("id,kind,environment"))
        XCTAssertTrue(csv.contains("trailRunning"))
        XCTAssertTrue(csv.contains("2.0.0-sport-analysis-1"))
        XCTAssertTrue(csv.contains("energy_lower_kcal"))
    }
}
