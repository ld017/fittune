import XCTest
@testable import FitTune

final class LiveSensorCoordinatorTests: XCTestCase {
    @MainActor
    func testWatchActivationCallbackDoesNotRecursivelyActivateAgain() {
        let watch = ReentrantWatchSource()

        _ = LiveSensorCoordinator(watchSource: watch)

        XCTAssertEqual(watch.activateCount, 1)
    }

    @MainActor
    func testWatchStartAcknowledgementAndTimeoutFallbackAreSessionScoped() {
        let watch = ReentrantWatchSource()
        watch.isPairedAndInstalled = true
        watch.isReachable = true
        let coordinator = LiveSensorCoordinator(watchSource: watch)
        let descriptor = LiveSourceDescriptor(id: "apple-watch", kind: .appleWatch, name: "Apple Watch")
        coordinator.select(descriptor)
        let sessionID = UUID()

        coordinator.beginWorkout(sessionID: sessionID, activity: "strength")
        XCTAssertEqual(coordinator.watchStartState, .waitingForAcknowledgement)
        watch.onAcknowledgement?(WatchWorkoutAcknowledgement(sessionID: UUID(), accepted: true, reason: "wrong"))
        XCTAssertEqual(coordinator.watchStartState, .waitingForAcknowledgement)
        watch.onAcknowledgement?(WatchWorkoutAcknowledgement(sessionID: sessionID, accepted: true, reason: "started"))
        XCTAssertEqual(coordinator.watchStartState, .streaming)

        let secondSession = UUID()
        coordinator.beginWorkout(sessionID: secondSession, activity: "strength")
        coordinator.watchStartTimedOut(sessionID: secondSession)
        XCTAssertEqual(coordinator.watchStartState, .estimatedFallback)
        XCTAssertEqual(coordinator.state, .estimated)
    }

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

@MainActor
private final class ReentrantWatchSource: WatchLiveSource {
    var isPairedAndInstalled = false
    var isReachable = false
    var onEnvelope: ((WatchMetricEnvelope) -> Void)?
    var onEvent: ((WatchWorkoutEventEnvelope) -> Void)?
    var onAcknowledgement: ((WatchWorkoutAcknowledgement) -> Void)?
    var onStatusChange: (() -> Void)?
    var activateCount = 0

    func activate() {
        activateCount += 1
        if activateCount == 1 { onStatusChange?() }
    }

    func send(command: MirroredWorkoutEvent, sessionID: UUID, activity: String) {}
}
