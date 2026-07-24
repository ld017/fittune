import XCTest
@testable import FitTune

final class LiveSensorCoordinatorTests: XCTestCase {
    @MainActor
    func testPreferredBluetoothHeartRateDevicePersistsAndIsReusedForWorkout() {
        let suite = "LiveSensorCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let fit3 = LiveSourceDescriptor(id: UUID().uuidString, kind: .bluetooth, name: "HUAWEI WATCH FIT 3")
        let first = LiveSensorCoordinator(defaults: defaults)
        first.select(fit3)

        let restored = LiveSensorCoordinator(defaults: defaults)
        restored.beginWorkout(sessionID: UUID(), activity: "running")

        XCTAssertEqual(restored.preferredLiveSource, fit3)
        XCTAssertEqual(restored.activeLiveSource, fit3)
        XCTAssertTrue(restored.statusMessage.contains("自动重连"))
    }
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

    func testSilenceMonitorReconnectsAtFiveSecondsAndRemindsAtFifteen() {
        let start = Date(timeIntervalSince1970: 100)
        let sessionID = UUID()
        let source = LiveSourceDescriptor(id: "fit3", kind: .bluetooth, name: "FIT 3")
        var monitor = HeartRateSilenceMonitor()

        monitor.begin(sessionID: sessionID, source: source, at: start)

        XCTAssertEqual(monitor.evaluate(at: start.addingTimeInterval(4)), .none)
        XCTAssertEqual(
            monitor.evaluate(at: start.addingTimeInterval(5)),
            .reconnect(source)
        )
        guard case let .remind(reminder) = monitor.evaluate(
            at: start.addingTimeInterval(15)
        ) else {
            return XCTFail("Expected reconnect reminder")
        }
        XCTAssertEqual(reminder.sourceName, "FIT 3")
        XCTAssertEqual(monitor.evaluate(at: start.addingTimeInterval(20)), .none)
    }

    func testValidSampleRearmsReminderForANewInterruption() {
        let start = Date(timeIntervalSince1970: 100)
        let source = LiveSourceDescriptor(id: "fit3", kind: .bluetooth, name: "FIT 3")
        var monitor = HeartRateSilenceMonitor()
        monitor.begin(sessionID: UUID(), source: source, at: start)
        _ = monitor.evaluate(at: start.addingTimeInterval(5))
        _ = monitor.evaluate(at: start.addingTimeInterval(15))

        monitor.receiveValidSample(at: start.addingTimeInterval(16))

        XCTAssertEqual(
            monitor.evaluate(at: start.addingTimeInterval(21)),
            .reconnect(source)
        )
        guard case .remind = monitor.evaluate(at: start.addingTimeInterval(31)) else {
            return XCTFail("Expected a reminder for the new interruption")
        }
    }

    func testEndedMonitorNeverReminds() {
        let start = Date(timeIntervalSince1970: 100)
        let source = LiveSourceDescriptor(id: "fit3", kind: .bluetooth, name: "FIT 3")
        var monitor = HeartRateSilenceMonitor()
        monitor.begin(sessionID: UUID(), source: source, at: start)
        monitor.end()

        XCTAssertEqual(monitor.evaluate(at: start.addingTimeInterval(30)), .none)
    }

    @MainActor
    func testEndingWorkoutClearsReconnectMonitoringState() {
        let coordinator = LiveSensorCoordinator()
        let source = LiveSourceDescriptor(
            id: "fit3",
            kind: .bluetooth,
            name: "FIT 3"
        )
        coordinator.select(source)
        coordinator.beginWorkout(sessionID: UUID(), activity: "strength")

        coordinator.endWorkout()

        XCTAssertNil(coordinator.reconnectReminder)
        XCTAssertNil(coordinator.activeSessionID)
    }

    @MainActor
    func testManualDisconnectClearsReconnectReminderAndSession() {
        let coordinator = LiveSensorCoordinator()
        let source = LiveSourceDescriptor(
            id: "fit3",
            kind: .bluetooth,
            name: "FIT 3"
        )
        coordinator.select(source)
        coordinator.beginWorkout(sessionID: UUID(), activity: "strength")

        coordinator.disconnect()

        XCTAssertNil(coordinator.reconnectReminder)
        XCTAssertNil(coordinator.activeSessionID)
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
