import XCTest
@testable import FitTune

@MainActor
final class DailyHealthSnapshotReducerTests: XCTestCase {
    func testIncrementalSamplesAreAggregatedAndCorrectedExternalIDReplacesOldValue() {
        let day = date("2026-07-22T00:00:00+08:00")
        let samples = [
            sample("steps-a", .steps, 3_000, at: "2026-07-22T08:00:00+08:00"),
            sample("steps-b", .steps, 2_000, at: "2026-07-22T12:00:00+08:00", updatedAt: "2026-07-22T12:01:00+08:00"),
            sample("steps-b", .steps, 2_500, at: "2026-07-22T12:00:00+08:00", updatedAt: "2026-07-22T12:02:00+08:00")
        ]

        let snapshot = DailyHealthSnapshotReducer.reduce(
            samples: samples,
            day: day,
            timeZone: timeZone,
            now: date("2026-07-22T13:00:00+08:00")
        )

        XCTAssertEqual(snapshot.steps.value, 5_500)
        XCTAssertEqual(snapshot.steps.provenance.sourceName, "Apple 健康")
        XCTAssertEqual(snapshot.steps.syncState, .current)
    }

    func testDeletedCorrectionRemovesSampleWhenDayIsRebuilt() {
        let samples = [
            sample("energy", .activeEnergyKcal, 480, at: "2026-07-22T18:00:00+08:00"),
            sample("energy", .activeEnergyKcal, 480, at: "2026-07-22T18:00:00+08:00", updatedAt: "2026-07-22T19:00:00+08:00", isDeleted: true)
        ]

        let snapshot = DailyHealthSnapshotReducer.reduce(samples: samples, day: date("2026-07-22T00:00:00+08:00"), timeZone: timeZone)

        XCTAssertNil(snapshot.activeEnergyKcal.value)
    }

    func testIdenticalWatchAndPhoneSamplesAreDeduplicatedAndWatchWinsProvenance() {
        let timestamp = "2026-07-22T09:00:00+08:00"
        let samples = [
            sample("phone", .steps, 1_200, at: timestamp, source: .appleHealth, sourceName: "iPhone"),
            sample("watch", .steps, 1_200, at: timestamp, source: .appleWatch, sourceName: "Apple Watch")
        ]

        let snapshot = DailyHealthSnapshotReducer.reduce(samples: samples, day: date("2026-07-22T00:00:00+08:00"), timeZone: timeZone)

        XCTAssertEqual(snapshot.steps.value, 1_200)
        XCTAssertEqual(snapshot.steps.provenance.source, .appleWatch)
    }

    func testHuaweiOnlyImportIsMarkedDelayed() {
        let snapshot = DailyHealthSnapshotReducer.reduce(
            samples: [sample("huawei", .restingHeartRate, 58, at: "2026-07-22T07:00:00+08:00", source: .huaweiHealth, sourceName: "华为运动健康")],
            day: date("2026-07-22T00:00:00+08:00"),
            timeZone: timeZone
        )

        XCTAssertEqual(snapshot.restingHeartRate.value, 58)
        XCTAssertEqual(snapshot.restingHeartRate.syncState, .delayed)
        XCTAssertEqual(snapshot.restingHeartRate.provenance.confidence, .measured)
    }

    func testTimeZoneDayBoundaryAndMissingPermissionAreHandledPerMetric() {
        let sampleBeforeLocalMidnight = sample("old", .steps, 999, at: "2026-07-21T23:59:59+08:00")
        let sampleAfterLocalMidnight = sample("new", .steps, 100, at: "2026-07-22T00:00:01+08:00")
        let snapshot = DailyHealthSnapshotReducer.reduce(
            samples: [sampleBeforeLocalMidnight, sampleAfterLocalMidnight],
            day: date("2026-07-22T12:00:00+08:00"),
            timeZone: timeZone,
            permissions: [.restingHeartRate: false, .steps: true, .walkingDistanceKm: true, .activeEnergyKcal: true]
        )

        XCTAssertEqual(snapshot.steps.value, 100)
        XCTAssertNil(snapshot.restingHeartRate.value)
        XCTAssertEqual(snapshot.restingHeartRate.syncState, .permissionMissing)
    }

    func testAppStoreIngestsSnapshotAtomicallyAndPersistsIt() {
        let defaults = makeDefaults()
        let snapshot = DailyHealthSnapshotReducer.reduce(
            samples: [
                sample("rhr", .restingHeartRate, 57, at: "2026-07-22T07:00:00+08:00"),
                sample("steps", .steps, 8_000, at: "2026-07-22T20:00:00+08:00"),
                sample("distance", .walkingDistanceKm, 6.2, at: "2026-07-22T20:00:00+08:00"),
                sample("energy", .activeEnergyKcal, 610, at: "2026-07-22T20:00:00+08:00")
            ],
            day: date("2026-07-22T00:00:00+08:00"),
            timeZone: timeZone
        )
        let store = AppStore(defaults: defaults)

        store.ingestDailyHealthSnapshot(snapshot)
        let restored = AppStore(defaults: defaults)

        XCTAssertEqual(restored.dailyHealthSnapshots, [snapshot])
        XCTAssertEqual(restored.dailySteps.first?.steps, 8_000)
        XCTAssertEqual(restored.dailySteps.first?.distanceKm, 6.2)
        XCTAssertEqual(restored.dailyActiveEnergy.first?.kilocalories, 610)
        XCTAssertEqual(restored.restingHeartRateSamples.first?.bpm, 57)
    }

    private let timeZone = TimeZone(identifier: "Asia/Shanghai")!

    private func sample(
        _ id: String,
        _ metric: DailyHealthMetric,
        _ value: Double,
        at timestamp: String,
        updatedAt: String? = nil,
        source: MetricSource = .appleHealth,
        sourceName: String = "Apple 健康",
        isDeleted: Bool = false
    ) -> DailyHealthSample {
        DailyHealthSample(
            externalID: id,
            metric: metric,
            value: value,
            sampleDate: date(timestamp),
            updatedAt: date(updatedAt ?? timestamp),
            source: source,
            sourceName: sourceName,
            isDeleted: isDeleted
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func makeDefaults() -> UserDefaults {
        let name = "DailyHealthSnapshotReducerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
