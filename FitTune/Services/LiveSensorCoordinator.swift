import Foundation
import Observation

struct LiveSensorCoordinatorStateMachine: Equatable {
    private(set) var state: LiveConnectionState = .none
    private(set) var activeLiveSource: LiveSourceDescriptor?
    private(set) var reconnectTarget: LiveSourceDescriptor?
    private(set) var pendingSwitch: LiveSourceDescriptor?
    private(set) var discoveredSources: [LiveSourceDescriptor] = []

    mutating func discover(_ source: LiveSourceDescriptor) {
        guard !discoveredSources.contains(where: { $0.id == source.id }) else { return }
        discoveredSources.append(source)
    }

    mutating func beginScanning() {
        guard activeLiveSource == nil else { return }
        state = .scanning
    }

    mutating func markEstimated() {
        state = .estimated
    }

    @discardableResult
    mutating func requestActivation(_ source: LiveSourceDescriptor) -> Bool {
        if let activeLiveSource, activeLiveSource.id != source.id {
            pendingSwitch = source
            return false
        }
        activeLiveSource = source
        reconnectTarget = source
        pendingSwitch = nil
        state = .connecting
        return true
    }

    mutating func confirmPendingSwitch() {
        guard let pendingSwitch else { return }
        activeLiveSource = pendingSwitch
        reconnectTarget = pendingSwitch
        self.pendingSwitch = nil
        state = .connecting
    }

    mutating func cancelPendingSwitch() {
        pendingSwitch = nil
    }

    mutating func didConnect(_ source: LiveSourceDescriptor) {
        guard activeLiveSource?.id == source.id else { return }
        reconnectTarget = source
        state = .connected
    }

    mutating func didDisconnect() {
        guard let activeLiveSource else {
            state = .estimated
            return
        }
        reconnectTarget = activeLiveSource
        state = .reconnecting
    }

    mutating func reconnectTimedOut() {
        activeLiveSource = nil
        pendingSwitch = nil
        state = .estimated
    }

    mutating func stop() {
        activeLiveSource = nil
        reconnectTarget = nil
        pendingSwitch = nil
        state = .none
    }
}

@MainActor
@Observable
final class LiveSensorCoordinator {
    private(set) var machine = LiveSensorCoordinatorStateMachine()
    private(set) var latestSample: WorkoutMetricSample?
    private(set) var latestValidity: LiveMetricValidity = .missing
    private(set) var latestWatchEvent: WatchWorkoutEventEnvelope?
    private(set) var statusMessage = "未连接实时设备，训练仍可使用估算模式"
    private let bluetoothSource: BluetoothHeartRateSource
    private let watchSource: (any WatchLiveSource)?
    private(set) var activeSessionID: UUID?

    init(bluetoothSource: BluetoothHeartRateSource = BluetoothHeartRateSource(), watchSource: (any WatchLiveSource)? = nil) {
        self.bluetoothSource = bluetoothSource
        self.watchSource = watchSource
        bluetoothSource.onDiscovery = { [weak self] descriptor in
            Task { @MainActor in self?.machine.discover(descriptor) }
        }
        bluetoothSource.onConnected = { [weak self] descriptor in
            Task { @MainActor in
                self?.machine.didConnect(descriptor)
                self?.statusMessage = "已连接 \(descriptor.name)"
            }
        }
        bluetoothSource.onDisconnected = { [weak self] in
            Task { @MainActor in
                self?.machine.didDisconnect()
                self?.statusMessage = "连接中断，正在重连原设备"
            }
        }
        bluetoothSource.onMeasurement = { [weak self] measurement, date, sourceName in
            Task { @MainActor in self?.receive(measurement, at: date, sourceName: sourceName) }
        }
        watchSource?.onEnvelope = { [weak self] envelope in self?.receive(envelope) }
        watchSource?.onEvent = { [weak self] event in self?.receive(event) }
        watchSource?.onStatusChange = { [weak self] in self?.refreshWatchAvailability() }
        watchSource?.activate()
        refreshWatchAvailability()
    }

    var state: LiveConnectionState { machine.state }
    var activeLiveSource: LiveSourceDescriptor? { machine.activeLiveSource }
    var pendingSwitch: LiveSourceDescriptor? { machine.pendingSwitch }
    var discoveredSources: [LiveSourceDescriptor] { machine.discoveredSources }
    var watchIsPaired: Bool { watchSource?.isPairedAndInstalled == true }
    var watchIsReachable: Bool { watchSource?.isReachable == true }

    func refreshWatchAvailability() {
        if watchSource?.isPairedAndInstalled == true {
            machine.discover(LiveSourceDescriptor(id: "apple-watch", kind: .appleWatch, name: "Apple Watch"))
        }
    }

    func beginWorkout(sessionID: UUID, activity: String) {
        activeSessionID = sessionID
        if activeLiveSource?.kind == .appleWatch { watchSource?.send(command: .started, sessionID: sessionID, activity: activity) }
    }

    func endWorkout() {
        if let activeSessionID, activeLiveSource?.kind == .appleWatch { watchSource?.send(command: .ended, sessionID: activeSessionID, activity: "") }
        activeSessionID = nil
    }

    func scanBluetooth() {
        machine.beginScanning()
        statusMessage = "正在查找标准蓝牙心率设备"
        bluetoothSource.startScanning()
    }

    func select(_ source: LiveSourceDescriptor) {
        guard machine.requestActivation(source) else {
            statusMessage = "需要确认后才能切换实时设备"
            return
        }
        connectSelectedSource()
    }

    func confirmSwitch() {
        bluetoothSource.disconnect()
        machine.confirmPendingSwitch()
        connectSelectedSource()
    }

    func cancelSwitch() {
        machine.cancelPendingSwitch()
    }

    func disconnect() {
        bluetoothSource.disconnect()
        machine.stop()
        latestSample = nil
        latestValidity = .missing
        statusMessage = "已断开；将使用手机或历史估算"
    }

    private func connectSelectedSource() {
        guard let source = machine.activeLiveSource else { return }
        switch source.kind {
        case .bluetooth:
            bluetoothSource.connect(identifier: source.id)
            statusMessage = "正在连接 \(source.name)"
        case .appleWatch:
            watchSource?.activate()
            if watchSource?.isPairedAndInstalled == true {
                machine.didConnect(source)
                statusMessage = watchSource?.isReachable == true ? "Apple Watch 已作为唯一实时来源" : "Apple Watch 已选择，等待手表连接"
            } else {
                machine.markEstimated()
                statusMessage = "未检测到已安装 FitTune 的 Apple Watch"
            }
        }
    }

    private func receive(_ measurement: BluetoothHeartRateMeasurement, at date: Date, sourceName: String) {
        let sample = WorkoutMetricSample(
            timestamp: date,
            heartRateBPM: Double(measurement.bpm),
            provenance: MetricProvenance(source: .bluetooth, sourceName: sourceName, confidence: .measured, coverage: 1, sampledAt: date)
        )
        let validity = LiveMetricValidator.validate(sample, previous: latestSample, contactDetected: measurement.contactDetected, now: date)
        latestValidity = validity
        guard validity == .valid else {
            machine.markEstimated()
            statusMessage = validity == .poorContact ? "传感器接触不良，当前改用估算" : "心率数据异常，当前改用估算"
            return
        }
        latestSample = sample
        if let source = machine.activeLiveSource { machine.didConnect(source) }
        statusMessage = "实时心率 \(measurement.bpm) bpm · \(sourceName)"
    }

    private func receive(_ envelope: WatchMetricEnvelope) {
        guard activeLiveSource?.kind == .appleWatch,
              activeSessionID == nil || activeSessionID == envelope.sessionID else { return }
        let validity = LiveMetricValidator.validate(envelope.sample, previous: latestSample, contactDetected: nil, now: envelope.sample.timestamp)
        latestValidity = validity
        guard validity == .valid else {
            machine.markEstimated()
            statusMessage = "Watch 样本异常或中断，当前改用估算"
            return
        }
        activeSessionID = envelope.sessionID
        latestSample = envelope.sample
        if let source = machine.activeLiveSource { machine.didConnect(source) }
        statusMessage = envelope.sample.heartRateBPM.map { "实时心率 \(Int($0.rounded())) bpm · Apple Watch" } ?? "Apple Watch 实时运动数据"
    }

    private func receive(_ envelope: WatchWorkoutEventEnvelope) {
        guard activeLiveSource?.kind == .appleWatch,
              activeSessionID == envelope.sessionID else { return }
        latestWatchEvent = envelope
        switch envelope.event {
        case .paused: statusMessage = "Apple Watch 已暂停训练"
        case .resumed: statusMessage = "Apple Watch 已继续训练"
        case .ended: statusMessage = "Apple Watch 请求保存并结束"
        case .started: statusMessage = "Apple Watch 已开始同步"
        }
    }
}
