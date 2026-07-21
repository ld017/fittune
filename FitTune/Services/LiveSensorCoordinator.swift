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
    private(set) var statusMessage = "未连接实时设备，训练仍可使用估算模式"
    private let bluetoothSource: BluetoothHeartRateSource

    init(bluetoothSource: BluetoothHeartRateSource = BluetoothHeartRateSource()) {
        self.bluetoothSource = bluetoothSource
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
    }

    var state: LiveConnectionState { machine.state }
    var activeLiveSource: LiveSourceDescriptor? { machine.activeLiveSource }
    var pendingSwitch: LiveSourceDescriptor? { machine.pendingSwitch }
    var discoveredSources: [LiveSourceDescriptor] { machine.discoveredSources }

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
            statusMessage = "Apple Watch 配套端就绪后可作为唯一实时来源"
            machine.markEstimated()
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
}
