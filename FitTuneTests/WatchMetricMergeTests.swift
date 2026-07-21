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

    private func envelope(sessionID: UUID, date: Date, bpm: Double, source: MetricSource) -> WatchMetricEnvelope {
        WatchMetricEnvelope(sessionID: sessionID, sample: .init(timestamp: date, heartRateBPM: bpm, provenance: .init(source: source, sourceName: source.rawValue, confidence: source == .appleWatch ? .measured : .estimated, coverage: 1)))
    }
}
