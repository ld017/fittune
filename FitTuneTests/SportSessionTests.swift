import XCTest
@testable import FitTune

@MainActor
final class SportSessionTests: XCTestCase {
    func testSportSessionPausesDeduplicatesAndPersistsAtCheckpoint() throws {
        let defaults = makeDefaults()
        let store = AppStore(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.startSportSession(kind: .hiking, environment: .outdoor, intensity: .training, at: start)
        let sample = metric(at: start.addingTimeInterval(1), distance: 100)

        store.appendSportMetricSample(sample, validity: .valid, now: start.addingTimeInterval(1))
        store.appendSportMetricSample(sample, validity: .valid, now: start.addingTimeInterval(2))
        XCTAssertEqual(store.activeSportDraft?.metricSamples.count, 1)
        XCTAssertEqual(AppStore(defaults: defaults).activeSportDraft?.metricSamples.count, 0)

        store.appendSportMetricSample(metric(at: start.addingTimeInterval(15), distance: 200), validity: .valid, now: start.addingTimeInterval(15))
        XCTAssertEqual(AppStore(defaults: defaults).activeSportDraft?.metricSamples.count, 2)

        store.pauseSportSession(at: start.addingTimeInterval(600))
        store.resumeSportSession(at: start.addingTimeInterval(900))
        let record = try XCTUnwrap(store.finishSportSession(status: .completed, sessionRPE: 7, at: start.addingTimeInterval(2_700)))

        XCTAssertEqual(record.analysis.effectiveDurationSeconds, 2_400, accuracy: 0.001)
        XCTAssertEqual(record.analysis.sessionRPELoadAU, 280, accuracy: 0.001)
        XCTAssertNil(store.activeSportDraft)
        XCTAssertEqual(store.sportWorkouts.first?.id, record.id)
    }

    func testMissingOrInvalidMetricsNeverBlockSportTraining() throws {
        let store = AppStore(defaults: makeDefaults())
        let start = Date(timeIntervalSince1970: 1_700_100_000)
        store.startSportSession(kind: .badminton, environment: .indoor, intensity: .social, at: start)

        store.appendSportMetricSample(metric(at: start, distance: 500), validity: .implausibleJump, now: start)
        let record = try XCTUnwrap(store.finishSportSession(status: .partial, sessionRPE: 4, at: start.addingTimeInterval(1_800)))

        XCTAssertTrue(record.metricSamples.isEmpty)
        XCTAssertFalse(record.analysis.warnings.isEmpty)
        XCTAssertEqual(record.completionStatus, .partial)
    }

    func testSportTrashRestoreAndPermanentDelete() throws {
        let store = AppStore(defaults: makeDefaults())
        let start = Date(timeIntervalSince1970: 1_700_200_000)
        store.startSportSession(kind: .soccer, environment: .outdoor, intensity: .competition, at: start)
        let record = try XCTUnwrap(store.finishSportSession(status: .completed, sessionRPE: 8, at: start.addingTimeInterval(3_600)))

        store.deleteSportWorkout(id: record.id)
        XCTAssertTrue(store.sportWorkouts.isEmpty)
        XCTAssertEqual(store.deletedSportWorkouts.map(\.id), [record.id])

        store.restoreSportWorkout(id: record.id)
        XCTAssertEqual(store.sportWorkouts.map(\.id), [record.id])

        store.deleteSportWorkout(id: record.id)
        store.permanentlyDeleteSportWorkout(id: record.id)
        XCTAssertTrue(store.deletedSportWorkouts.isEmpty)
    }

    func testSchemaFifteenWithoutSportsRestoresEmptySportCollections() throws {
        let defaults = makeDefaults()
        let snapshot = AppSnapshot(
            profile: nil,
            plan: nil,
            readiness: ReadinessInput(),
            workoutHistory: [],
            weightHistory: [],
            schemaVersion: 15
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode(snapshot), forKey: UserDefaultsSnapshotRepository.defaultKey)

        let store = AppStore(defaults: defaults)

        XCTAssertTrue(store.sportWorkouts.isEmpty)
        XCTAssertTrue(store.deletedSportWorkouts.isEmpty)
        XCTAssertNil(store.activeSportDraft)
        XCTAssertEqual(AppSnapshot.currentSchemaVersion, 16)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "SportSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func metric(at date: Date, distance: Double) -> WorkoutMetricSample {
        WorkoutMetricSample(
            timestamp: date,
            heartRateBPM: 140,
            distanceMeters: distance,
            provenance: .init(source: .phoneSensor, sourceName: "iPhone", confidence: .measured, coverage: 1)
        )
    }
}
