import XCTest
@testable import FitTune

@MainActor
final class CardioSessionTests: XCTestCase {
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

    func testModalitiesExposeOnlySupportedMetrics() {
        XCTAssertTrue(CardioSessionCapabilities.metrics(for: .running, hasWatch: false).contains(.pace))
        XCTAssertTrue(CardioSessionCapabilities.metrics(for: .inclineWalking, hasWatch: false).contains(.incline))
        XCTAssertTrue(CardioSessionCapabilities.metrics(for: .stairClimber, hasWatch: false).contains(.floors))
        XCTAssertTrue(CardioSessionCapabilities.metrics(for: .cycling, hasWatch: false).contains(.power))
        XCTAssertFalse(CardioSessionCapabilities.metrics(for: .swimming, hasWatch: false).contains(.strokeCount))
        XCTAssertTrue(CardioSessionCapabilities.unavailableMetrics(for: .swimming, hasWatch: false).contains(.strokeCount))
    }

    func testCardioDraftRestoresWithoutDuplicatingSamples() throws {
        let defaults = makeDefaults()
        let store = AppStore(defaults: defaults)
        store.startCardioSession(modality: .running, intensity: .zone2)
        let sample = WorkoutMetricSample(
            id: UUID(),
            timestamp: .now,
            cadence: 170,
            distanceMeters: 100,
            provenance: .init(source: .phoneSensor, sourceName: "iPhone", confidence: .measured, coverage: 1)
        )
        store.appendCardioMetricSample(sample)
        store.appendCardioMetricSample(sample)
        store.checkpointActiveCardio()

        let restored = AppStore(defaults: defaults)

        XCTAssertEqual(restored.activeCardioDraft?.id, store.activeCardioDraft?.id)
        XCTAssertEqual(restored.activeCardioDraft?.metricSamples.count, 1)
        XCTAssertEqual(restored.activeCardioDraft?.distanceMeters, 100)
    }

    func testPermissionInterruptionCreatesPartialResultWithGapReason() throws {
        let store = AppStore(defaults: makeDefaults())
        store.startCardioSession(modality: .cycling, intensity: .zone2)
        store.markCardioDataGap("定位权限被撤回")

        let result = try XCTUnwrap(store.finishCardioSession(status: .partial))

        XCTAssertEqual(result.completionStatus, .partial)
        XCTAssertEqual(result.dataGapReason, "定位权限被撤回")
        XCTAssertTrue(result.metricSamples?.isEmpty ?? true)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "CardioSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
