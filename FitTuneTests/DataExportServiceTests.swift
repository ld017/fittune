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
}
