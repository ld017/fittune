import XCTest
@testable import FitTune

final class LiveSensorCoordinatorTests: XCTestCase {
    func testNewDiscoveryCannotReplaceActiveSourceWithoutConfirmation() {
        var coordinator = LiveSensorCoordinatorStateMachine()
        let watch = LiveSourceDescriptor(id: "watch", kind: .appleWatch, name: "Apple Watch")
        let belt = LiveSourceDescriptor(id: "belt", kind: .bluetooth, name: "Polar H10")

        XCTAssertTrue(coordinator.requestActivation(watch))
        coordinator.didConnect(watch)
        coordinator.discover(belt)
        XCTAssertFalse(coordinator.requestActivation(belt))
        XCTAssertEqual(coordinator.activeLiveSource, watch)
        XCTAssertEqual(coordinator.pendingSwitch, belt)

        coordinator.confirmPendingSwitch()
        XCTAssertEqual(coordinator.activeLiveSource, belt)
    }

    func testDisconnectReconnectsOnlyOriginalThenDegradesToEstimate() {
        var coordinator = LiveSensorCoordinatorStateMachine()
        let belt = LiveSourceDescriptor(id: "belt", kind: .bluetooth, name: "Polar H10")
        let other = LiveSourceDescriptor(id: "other", kind: .bluetooth, name: "Other")
        _ = coordinator.requestActivation(belt)
        coordinator.didConnect(belt)
        coordinator.discover(other)

        coordinator.didDisconnect()
        XCTAssertEqual(coordinator.state, .reconnecting)
        XCTAssertEqual(coordinator.reconnectTarget, belt)
        coordinator.reconnectTimedOut()

        XCTAssertEqual(coordinator.state, .estimated)
        XCTAssertNil(coordinator.activeLiveSource)
        XCTAssertNotEqual(coordinator.activeLiveSource, other)
    }

    func testStaleJumpAndPoorContactSamplesAreExcluded() {
        let now = Date(timeIntervalSince1970: 100)
        let provenance = MetricProvenance(source: .bluetooth, sourceName: "H10", confidence: .measured, coverage: 1)
        let previous = WorkoutMetricSample(timestamp: now.addingTimeInterval(-2), heartRateBPM: 100, provenance: provenance)

        XCTAssertEqual(LiveMetricValidator.validate(.init(timestamp: now.addingTimeInterval(-20), heartRateBPM: 100, provenance: provenance), previous: nil, contactDetected: true, now: now), .stale)
        XCTAssertEqual(LiveMetricValidator.validate(.init(timestamp: now, heartRateBPM: 180, provenance: provenance), previous: previous, contactDetected: true, now: now), .implausibleJump)
        XCTAssertEqual(LiveMetricValidator.validate(.init(timestamp: now, heartRateBPM: 100, provenance: provenance), previous: previous, contactDetected: false, now: now), .poorContact)
        XCTAssertEqual(LiveMetricValidator.validate(.init(timestamp: now, heartRateBPM: 104, provenance: provenance), previous: previous, contactDetected: true, now: now), .valid)
    }
}
