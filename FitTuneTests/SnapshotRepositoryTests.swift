import Foundation
import XCTest
@testable import FitTune

final class SnapshotRepositoryTests: XCTestCase {
    func testFileRepositoryKeepsLastKnownGoodBackup() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileSnapshotRepository(directory: directory)
        let first = Data("first".utf8)
        let second = Data("second".utf8)

        try repository.save(first)
        try repository.save(second)

        XCTAssertEqual(repository.loadCandidates(), [second, first])
    }

    func testFileRepositoryLoadsBackupWhenPrimaryIsCorrupt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileSnapshotRepository(directory: directory)
        let backup = try snapshotData(nickname: "backup")
        let primary = try snapshotData(nickname: "primary")

        try repository.save(backup)
        try repository.save(primary)
        try Data("corrupt".utf8).write(
            to: directory.appendingPathComponent("snapshot.json"),
            options: .atomic
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = repository.loadCandidates().lazy.compactMap {
            try? decoder.decode(AppSnapshot.self, from: $0)
        }.first

        XCTAssertEqual(restored?.profile?.nickname, "backup")
    }

    func testUserDefaultsRepositoryKeepsExistingSynchronousRoundTrip() throws {
        let suite = "SnapshotRepositoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UserDefaultsSnapshotRepository(defaults: defaults)
        let expected = Data("snapshot".utf8)

        try first.save(expected)
        let restored = UserDefaultsSnapshotRepository(defaults: defaults)

        XCTAssertEqual(restored.loadCandidates(), [expected])
    }

    @MainActor
    func testCardioLiveSamplesUseFifteenSecondCheckpointPolicy() throws {
        let suite = "SnapshotRepositoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.startCardioSession(modality: .running, intensity: .zone2, at: start)

        store.appendCardioMetricSample(sample(at: start.addingTimeInterval(14)), now: start.addingTimeInterval(14))

        XCTAssertEqual(AppStore(defaults: defaults).activeCardioDraft?.metricSamples.count, 0)

        store.appendCardioMetricSample(sample(at: start.addingTimeInterval(15)), now: start.addingTimeInterval(15))

        XCTAssertEqual(AppStore(defaults: defaults).activeCardioDraft?.metricSamples.count, 2)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapshotRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func snapshotData(nickname: String) throws -> Data {
        let profile = UserProfile(
            nickname: nickname,
            goal: .generalFitness,
            secondaryGoal: .none,
            experience: .beginner,
            weeklyDays: 3,
            sessionMinutes: 45,
            equipment: .fullGym,
            bodyWeightKg: 70,
            loadIncrementKg: 2.5
        )
        let snapshot = AppSnapshot(
            profile: profile,
            plan: nil,
            readiness: ReadinessInput(),
            workoutHistory: [],
            weightHistory: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    private func sample(at date: Date) -> WorkoutMetricSample {
        WorkoutMetricSample(
            timestamp: date,
            heartRateBPM: 140,
            cadence: 170,
            distanceMeters: date.timeIntervalSince1970,
            provenance: .init(
                source: .appleWatch,
                sourceName: "Apple Watch",
                confidence: .measured,
                coverage: 1
            )
        )
    }
}
