import Foundation
import Observation

enum WatchWorkoutStartState: String, Codable, Equatable {
    case idle
    case waitingForAcknowledgement
    case streaming
    case estimatedFallback
    case rejected
}

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

struct HeartRateReconnectReminder: Identifiable, Equatable {
    let id = UUID()
    let sessionID: UUID
    let sourceName: String
}

enum HeartRateMonitoringAction: Equatable {
    case none
    case reconnect(LiveSourceDescriptor)
    case remind(HeartRateReconnectReminder)
}

struct HeartRateSilenceMonitor {
    private(set) var sessionID: UUID?
    private(set) var source: LiveSourceDescriptor?
    private(set) var lastValidSampleAt: Date?
    private var requestedReconnect = false
    private var showedReminder = false

    mutating func begin(
        sessionID: UUID,
        source: LiveSourceDescriptor,
        at date: Date
    ) {
        self.sessionID = sessionID
        self.source = source
        lastValidSampleAt = date
        requestedReconnect = false
        showedReminder = false
    }

    mutating func receiveValidSample(at date: Date) {
        guard sessionID != nil else { return }
        lastValidSampleAt = date
        requestedReconnect = false
        showedReminder = false
    }

    mutating func evaluate(at date: Date) -> HeartRateMonitoringAction {
        guard let sessionID, let source, let lastValidSampleAt else { return .none }
        let elapsed = date.timeIntervalSince(lastValidSampleAt)
        if elapsed >= 15, !showedReminder {
            showedReminder = true
            requestedReconnect = true
            return .remind(.init(sessionID: sessionID, sourceName: source.name))
        }
        if elapsed >= 5, !requestedReconnect {
            requestedReconnect = true
            return .reconnect(source)
        }
        return .none
    }

    mutating func end() {
        sessionID = nil
        source = nil
        lastValidSampleAt = nil
        requestedReconnect = false
        showedReminder = false
    }
}

@MainActor
@Observable
final class LiveSensorCoordinator {
    private static let preferredSourceKey = "FitTune.preferredLiveSource.v1"
    private(set) var machine = LiveSensorCoordinatorStateMachine()
    private(set) var latestSample: WorkoutMetricSample?
    private(set) var latestValidity: LiveMetricValidity = .missing
    private(set) var latestWatchEvent: WatchWorkoutEventEnvelope?
    private(set) var statusMessage = "未连接实时设备，训练仍可使用估算模式"
    private let bluetoothSource: any BluetoothHeartRateProviding
    private let watchSource: (any WatchLiveSource)?
    private let defaults: UserDefaults
    private(set) var preferredLiveSource: LiveSourceDescriptor?
    private(set) var activeSessionID: UUID?
    private(set) var watchStartState: WatchWorkoutStartState = .idle
    private(set) var reconnectReminder: HeartRateReconnectReminder?
    private var watchStreamState: WatchMetricStreamState?
    private var silenceMonitor = HeartRateSilenceMonitor()
    private var silenceTask: Task<Void, Never>?

    init(
        bluetoothSource: any BluetoothHeartRateProviding = BluetoothHeartRateSource(),
        watchSource: (any WatchLiveSource)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.bluetoothSource = bluetoothSource
        self.watchSource = watchSource
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.preferredSourceKey) {
            preferredLiveSource = try? JSONDecoder().decode(LiveSourceDescriptor.self, from: data)
        }
        bluetoothSource.onDiscovery = { [weak self] descriptor in
            Task { @MainActor in self?.handleDiscovery(descriptor) }
        }
        bluetoothSource.onConnected = { [weak self] descriptor in
            Task { @MainActor in
                self?.machine.didConnect(descriptor)
                self?.statusMessage = "已连接 \(descriptor.name)"
            }
        }
        bluetoothSource.onDisconnected = { [weak self] in
            Task { @MainActor in self?.handleBluetoothDisconnect() }
        }
        bluetoothSource.onMeasurement = { [weak self] measurement, date, sourceName in
            Task { @MainActor in self?.receive(measurement, at: date, sourceName: sourceName) }
        }
        watchSource?.onEnvelope = { [weak self] envelope in self?.receive(envelope) }
        watchSource?.onEvent = { [weak self] event in self?.receive(event) }
        watchSource?.onAcknowledgement = { [weak self] acknowledgement in self?.receive(acknowledgement) }
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
        watchStreamState = WatchMetricStreamState(sessionID: sessionID)
        if machine.activeLiveSource == nil, let preferredLiveSource {
            _ = machine.requestActivation(preferredLiveSource)
        }
        if activeLiveSource?.kind == .bluetooth {
            watchStartState = .estimatedFallback
            bluetoothSource.startScanning()
            statusMessage = "正在自动重连 \(activeLiveSource?.name ?? "蓝牙心率设备")；未收到心率前使用估算"
            if let source = activeLiveSource {
                startSilenceMonitoring(sessionID: sessionID, source: source)
            }
            return
        }
        guard activeLiveSource?.kind == .appleWatch,
              watchSource?.isPairedAndInstalled == true else {
            watchStartState = .estimatedFallback
            machine.markEstimated()
            statusMessage = "未使用实时手表，当前按训练记录估算"
            return
        }
        watchStartState = .waitingForAcknowledgement
        statusMessage = watchSource?.isReachable == true ? "正在让 Apple Watch 自动开始训练" : "手表暂不可达，已排队等待自动开始"
        watchSource?.send(command: .started, sessionID: sessionID, activity: activity)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.watchStartTimedOut(sessionID: sessionID)
        }
    }

    func endWorkout() {
        endWorkoutCollectionKeepingPreference()
    }

    func pauseWorkout() {
        guard let activeSessionID, activeLiveSource?.kind == .appleWatch else { return }
        watchSource?.send(command: .paused, sessionID: activeSessionID, activity: "")
    }

    func resumeWorkout() {
        guard let activeSessionID, activeLiveSource?.kind == .appleWatch else { return }
        watchSource?.send(command: .resumed, sessionID: activeSessionID, activity: "")
    }

    func endWorkoutCollectionKeepingPreference() {
        if let activeSessionID, activeLiveSource?.kind == .appleWatch { watchSource?.send(command: .ended, sessionID: activeSessionID, activity: "") }
        stopSilenceMonitoring()
        bluetoothSource.disconnect()
        activeSessionID = nil
        watchStreamState = nil
        watchStartState = .idle
        reconnectReminder = nil
        latestSample = nil
        latestValidity = .missing
        machine.stop()
        statusMessage = preferredLiveSource.map { "训练采集已结束；下次将自动连接 \($0.name)" } ?? "训练采集已结束"
    }

    func watchStartTimedOut(sessionID: UUID) {
        guard activeSessionID == sessionID, watchStartState == .waitingForAcknowledgement else { return }
        watchStartState = .estimatedFallback
        machine.markEstimated()
        statusMessage = "Apple Watch 未确认开始，训练继续使用估算；连接恢复后会自动接续"
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
        remember(source)
        connectSelectedSource()
    }

    func confirmSwitch() {
        bluetoothSource.disconnect()
        machine.confirmPendingSwitch()
        if let source = machine.activeLiveSource { remember(source) }
        connectSelectedSource()
    }

    func cancelSwitch() {
        machine.cancelPendingSwitch()
    }

    func disconnect() {
        stopSilenceMonitoring()
        activeSessionID = nil
        watchStreamState = nil
        watchStartState = .idle
        bluetoothSource.disconnect()
        machine.stop()
        latestSample = nil
        latestValidity = .missing
        preferredLiveSource = nil
        defaults.removeObject(forKey: Self.preferredSourceKey)
        statusMessage = "已断开；将使用手机或历史估算"
    }

    func retryPreferredSource() {
        reconnectReminder = nil
        guard let preferredLiveSource,
              preferredLiveSource.kind == .bluetooth else { return }
        statusMessage = "正在重新扫描 \(preferredLiveSource.name)"
        bluetoothSource.reconnect(identifier: preferredLiveSource.id)
    }

    func dismissReconnectReminder() {
        reconnectReminder = nil
    }

    private func handleDiscovery(_ descriptor: LiveSourceDescriptor) {
        machine.discover(descriptor)
        guard preferredLiveSource?.id == descriptor.id else { return }
        if machine.activeLiveSource == nil { _ = machine.requestActivation(descriptor) }
        guard machine.activeLiveSource?.id == descriptor.id else { return }
        bluetoothSource.connect(identifier: descriptor.id)
        statusMessage = "已找到 \(descriptor.name)，正在自动重连"
    }

    private func remember(_ source: LiveSourceDescriptor) {
        preferredLiveSource = source
        if let data = try? JSONEncoder().encode(source) {
            defaults.set(data, forKey: Self.preferredSourceKey)
        }
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
        silenceMonitor.receiveValidSample(at: date)
        reconnectReminder = nil
        if let source = machine.activeLiveSource { machine.didConnect(source) }
        statusMessage = "实时心率 \(measurement.bpm) bpm · \(sourceName)"
    }

    private func startSilenceMonitoring(
        sessionID: UUID,
        source: LiveSourceDescriptor
    ) {
        silenceTask?.cancel()
        silenceMonitor.begin(sessionID: sessionID, source: source, at: .now)
        reconnectReminder = nil
        silenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.evaluateHeartRateSilence(sessionID: sessionID)
            }
        }
    }

    private func stopSilenceMonitoring() {
        silenceTask?.cancel()
        silenceTask = nil
        silenceMonitor.end()
        reconnectReminder = nil
    }

    func evaluateHeartRateSilence(
        sessionID: UUID,
        at date: Date = .now
    ) {
        guard activeSessionID == sessionID else { return }
        switch silenceMonitor.evaluate(at: date) {
        case .none:
            break
        case let .reconnect(source):
            statusMessage = "心率广播暂时中断，正在自动重连 \(source.name)"
            bluetoothSource.reconnect(identifier: source.id)
        case let .remind(reminder):
            reconnectReminder = reminder
            statusMessage = "心率连接已中断；训练继续使用估算"
            if let source = silenceMonitor.source {
                bluetoothSource.reconnect(identifier: source.id)
            }
        }
    }

    private func handleBluetoothDisconnect() {
        machine.didDisconnect()
        guard activeSessionID != nil,
              activeLiveSource?.kind == .bluetooth else {
            statusMessage = "连接已断开"
            return
        }
        statusMessage = "连接中断，正在重连原设备"
    }

    private func receive(_ envelope: WatchMetricEnvelope) {
        guard activeLiveSource?.kind == .appleWatch,
              activeSessionID == nil || activeSessionID == envelope.sessionID else { return }
        if watchStreamState == nil { watchStreamState = WatchMetricStreamState(sessionID: envelope.sessionID) }
        guard watchStreamState?.ingest(envelope, now: .now) == .accepted else {
            statusMessage = "已忽略错误场次、重复、过期或累计值异常的 Watch 数据"
            return
        }
        let validity = LiveMetricValidator.validate(envelope.sample, previous: latestSample, contactDetected: nil, now: envelope.sample.timestamp)
        latestValidity = validity
        guard validity == .valid else {
            machine.markEstimated()
            statusMessage = "Watch 样本异常或中断，当前改用估算"
            return
        }
        activeSessionID = envelope.sessionID
        watchStartState = .streaming
        latestSample = envelope.sample
        if let source = machine.activeLiveSource { machine.didConnect(source) }
        statusMessage = envelope.sample.heartRateBPM.map { "实时心率 \(Int($0.rounded())) bpm · Apple Watch" } ?? "Apple Watch 实时运动数据"
    }

    private func receive(_ acknowledgement: WatchWorkoutAcknowledgement) {
        guard activeLiveSource?.kind == .appleWatch,
              activeSessionID == acknowledgement.sessionID else { return }
        if acknowledgement.accepted {
            watchStartState = .streaming
            if let source = machine.activeLiveSource { machine.didConnect(source) }
            statusMessage = "Apple Watch 已自动开始并确认实时采集"
        } else {
            watchStartState = .rejected
            machine.markEstimated()
            statusMessage = "Apple Watch 未开始：\(acknowledgement.reason)；本次继续使用估算"
        }
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
