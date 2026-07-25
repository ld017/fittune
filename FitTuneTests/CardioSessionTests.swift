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

    func testIdenticalCardioWorkloadUpdateDoesNotCreateAnotherSegment() throws {
        let store = AppStore(defaults: makeDefaults())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.startCardioSession(
            modality: .cycling,
            intensity: .zone2,
            powerWatts: 180,
            at: start
        )

        store.updateCardioWorkload(
            speedKph: nil,
            inclinePercent: nil,
            powerWatts: 180,
            handrailSupport: .none,
            at: start.addingTimeInterval(600)
        )

        let draft = try XCTUnwrap(store.activeCardioDraft)
        XCTAssertEqual(draft.workloadSegments.count, 1)
        XCTAssertNil(draft.workloadSegments[0].endedAt)
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
