import XCTest
@testable import FitTune

final class WatchMetricMergeTests: XCTestCase {
    func testSameSessionSamplesAreDeduplicatedByMetricTimeAndPreferWatch() {
        let sessionID = UUID()
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let phone = envelope(sessionID: sessionID, date: date, bpm: 140, source: .phoneEstimate)
        let watch = envelope(sessionID: sessionID, date: date.addingTimeInterval(0.4), bpm: 142, source: .appleWatch)

        let merged = WatchMetricMerger.merge(existing: [phone], incoming: [watch])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.sample.heartRateBPM, 142)
        XCTAssertEqual(merged.first?.sample.provenance.source, .appleWatch)
    }

    func testDifferentSessionNeverMergesAndEndEventRemainsSingle() {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let first = envelope(sessionID: UUID(), date: date, bpm: 120, source: .appleWatch)
        let second = envelope(sessionID: UUID(), date: date, bpm: 120, source: .appleWatch)

        XCTAssertEqual(WatchMetricMerger.merge(existing: [first], incoming: [second]).count, 2)
        XCTAssertEqual(WatchMetricMerger.deduplicateEvents([.ended, .ended, .paused]), [.ended, .paused])
    }

    func testWatchEndMessageDecodesWithOwningSession() {
        let sessionID = UUID()

        let event = WatchMessageDecoder.event(from: [
            "type": "event",
            "event": "ended",
            "sessionID": sessionID.uuidString
        ])

        XCTAssertEqual(event, WatchWorkoutEventEnvelope(sessionID: sessionID, event: .ended))
        XCTAssertNil(WatchMessageDecoder.event(from: ["type": "event", "event": "ended", "sessionID": "bad-id"]))
    }

    func testAcknowledgementDecoderRequiresMatchingSessionPayload() {
        let sessionID = UUID()
        let acknowledgement = WatchMessageDecoder.acknowledgement(from: [
            "type": "acknowledgement",
            "sessionID": sessionID.uuidString,
            "accepted": true,
            "reason": "started"
        ])

        XCTAssertEqual(acknowledgement?.sessionID, sessionID)
        XCTAssertEqual(acknowledgement?.accepted, true)
        XCTAssertNil(WatchMessageDecoder.acknowledgement(from: ["type": "acknowledgement", "sessionID": "bad"]))
    }

    func testStreamRejectsWrongSessionDuplicateOutOfOrderStaleAndCumulativeRegression() {
        let sessionID = UUID()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var stream = WatchMetricStreamState(sessionID: sessionID)

        XCTAssertEqual(stream.ingest(sequenced(sessionID, 1, now, energy: 10), now: now), .accepted)
        XCTAssertEqual(stream.ingest(sequenced(sessionID, 1, now.addingTimeInterval(1), energy: 11), now: now.addingTimeInterval(1)), .duplicateOrOutOfOrder)
        XCTAssertEqual(stream.ingest(sequenced(UUID(), 2, now.addingTimeInterval(2), energy: 12), now: now.addingTimeInterval(2)), .wrongSession)
        XCTAssertEqual(stream.ingest(sequenced(sessionID, 2, now.addingTimeInterval(-30), energy: 12), now: now), .stale)
        XCTAssertEqual(stream.ingest(sequenced(sessionID, 2, now.addingTimeInterval(2), energy: 9), now: now.addingTimeInterval(2)), .cumulativeRegression)
        XCTAssertEqual(stream.ingest(sequenced(sessionID, 3, now.addingTimeInterval(3), energy: 13), now: now.addingTimeInterval(3)), .accepted)
    }

    func testFinalizedHealthKitEnergyRevisesRatherThanAddsToLiveCumulativeEnergy() {
        XCTAssertEqual(WatchMetricMerger.reconciledActiveEnergy(liveCumulativeKcal: 180, finalizedHealthKitKcal: 192), 192)
        XCTAssertEqual(WatchMetricMerger.reconciledActiveEnergy(liveCumulativeKcal: 180, finalizedHealthKitKcal: nil), 180)
        XCTAssertNotEqual(WatchMetricMerger.reconciledActiveEnergy(liveCumulativeKcal: 180, finalizedHealthKitKcal: 192), 372)
    }

    private func envelope(sessionID: UUID, date: Date, bpm: Double, source: MetricSource) -> WatchMetricEnvelope {
        WatchMetricEnvelope(sessionID: sessionID, sample: .init(timestamp: date, heartRateBPM: bpm, provenance: .init(source: source, sourceName: source.rawValue, confidence: source == .appleWatch ? .measured : .estimated, coverage: 1)))
    }

    private func sequenced(_ sessionID: UUID, _ sequence: Int, _ date: Date, energy: Double) -> WatchMetricEnvelope {
        WatchMetricEnvelope(
            sessionID: sessionID,
            sequence: sequence,
            sample: .init(
                timestamp: date,
                heartRateBPM: 130,
                activeEnergyKcal: energy,
                provenance: .init(source: .appleWatch, sourceName: "Apple Watch", confidence: .measured, coverage: 1)
            )
        )
    }
}
