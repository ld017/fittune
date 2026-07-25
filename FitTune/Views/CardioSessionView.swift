import SwiftUI

struct CardioSessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(LiveSensorCoordinator.self) private var liveSensors
    @Environment(\.dismiss) private var dismiss
    @State private var motion = MotionLocationSource()
    @State private var showExitDialog = false
    @State private var showDiscardAlert = false
    @State private var liveSpeedKph = 0.0
    @State private var liveInclinePercent = 20.0
    @State private var liveInclineMode: TreadmillInclineInputMode = .percentGrade
    @State private var liveInclineLevel = 20.0
    @State private var liveMachineMaximumLevel = 20.0
    @State private var liveCalibrationRise = 0.0
    @State private var liveCalibrationRun = 0.0
    @State private var livePowerWatts = 0.0
    @State private var liveHandrailSupport: HandrailSupport = .none
    @State private var confirmedDistanceKm = 0.0

    var body: some View {
        ZStack {
            FitBackground()
            if let draft = store.activeCardioDraft {
                VStack(spacing: 0) {
                    topBar(draft)
                    ScrollView {
                        VStack(spacing: 18) {
                            sessionMetrics(draft)
                            workloadControls(draft)
                            sourceCard(draft)
                            Button { finish(.completed) } label: {
                                Label("完成有氧训练", systemImage: "flag.checkered")
                            }
                            .buttonStyle(PrimaryActionButtonStyle())
                        }
                        .padding(18)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            if let draft = store.activeCardioDraft { loadControls(from: draft) }
            startSensorsIfNeeded()
            updateLiveActivity()
        }
        .onChange(of: liveSensors.latestSample?.id) { _, _ in
            if let sample = liveSensors.latestSample, liveSensors.latestValidity == .valid {
                store.appendCardioMetricSample(sample)
                updateLiveActivity()
            }
        }
        .onChange(of: liveSensors.latestWatchEvent) { _, event in
            guard event?.sessionID == store.activeCardioDraft?.id, event?.event == .ended else { return }
            finish(.partial)
        }
        .onChange(of: store.activeCardioDraft?.updatedAt) { _, _ in updateLiveActivity() }
        .confirmationDialog("离开当前有氧训练？", isPresented: $showExitDialog, titleVisibility: .visible) {
            Button("继续未完成训练") {}
            Button("保存并结束") { finish(.partial) }
            Button("放弃训练", role: .destructive) { showDiscardAlert = true }
        } message: { Text("训练已在本机持续保存。") }
        .alert("确认放弃？", isPresented: $showDiscardAlert) {
            Button("取消", role: .cancel) {}
            Button("放弃", role: .destructive) {
                motion.stop()
                liveSensors.endWorkout()
                WorkoutActivityController.shared.end()
                store.discardCardioSession()
                dismiss()
            }
        }
        .alert(
            "心率连接已中断",
            isPresented: Binding(
                get: { liveSensors.reconnectReminder != nil },
                set: { if !$0 { liveSensors.dismissReconnectReminder() } }
            )
        ) {
            Button("立即重新扫描") { liveSensors.retryPreferredSource() }
            Button("继续估算", role: .cancel) {
                liveSensors.dismissReconnectReminder()
            }
        } message: {
            Text("已尝试自动重连 \(liveSensors.reconnectReminder?.sourceName ?? "心率设备")，暂未恢复心率。可以重新扫描，训练记录不会中断。")
        }
    }

    private func topBar(_ draft: CardioSessionDraft) -> some View {
        HStack {
            Button { showExitDialog = true } label: {
                Image(systemName: "xmark").frame(width: 42, height: 42).background(FitTheme.surface, in: Circle())
            }.buttonStyle(.plain)
            Spacer()
            VStack {
                Text(draft.modality.title).font(.headline)
                Text("后台自动保存").font(.caption2.bold()).foregroundStyle(FitTheme.accent)
            }
            Spacer()
            Image(systemName: "heart.fill").foregroundStyle(FitTheme.danger).frame(width: 42)
        }
        .padding(.horizontal, 18)
    }

    private func sessionMetrics(_ draft: CardioSessionDraft) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 18) {
                Text(durationText(context.date.timeIntervalSince(draft.startedAt)))
                    .font(.system(size: 48, weight: .black, design: .rounded).monospacedDigit())
                HStack(spacing: 10) {
                    MetricChip(value: liveSensors.latestSample?.heartRateBPM.map { "\(Int($0.rounded()))" } ?? "—", label: "实时 bpm", tint: FitTheme.danger)
                        .frame(height: 76)
                    MetricChip(value: String(format: "%.2f", draft.distanceMeters / 1000), label: "传感器距离 km", tint: FitTheme.accentBlue)
                        .frame(height: 76)
                    MetricChip(value: draft.metricSamples.compactMap(\.cadence).last.map { "\(Int($0.rounded()))" } ?? "—", label: "步频/踏频")
                        .frame(height: 76)
                }
            }
            .fitCard(padding: 22)
        }
    }

    @ViewBuilder
    private func workloadControls(_ draft: CardioSessionDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("实时负荷").font(.headline)
                Spacer()
                Text(workloadSummary(for: draft.modality)).font(.caption.bold()).foregroundStyle(FitTheme.accent)
                    .multilineTextAlignment(.trailing)
            }
            if [.running, .briskWalking, .inclineWalking].contains(draft.modality) {
                NumericInputControl(title: "当前速度", value: speedBinding, range: 0...30, step: 0.1, unit: "km/h")
            }
            if draft.modality == .inclineWalking {
                Picker("坡度输入", selection: inclineModeBinding) {
                    ForEach(TreadmillInclineInputMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if liveInclineMode == .percentGrade {
                    NumericInputControl(title: "当前坡度", value: inclineBinding, range: 0...40, step: 0.5, unit: "%")
                } else {
                    NumericInputControl(title: "当前档位", value: inclineLevelBinding, range: 0...100, step: 1, unit: "级")
                    NumericInputControl(title: "最高档位", value: maximumLevelBinding, range: 1...100, step: 1, unit: "级")
                    NumericInputControl(title: "最高档抬升", value: calibrationRiseBinding, range: 0...1000, step: 0.5, unit: "cm")
                    NumericInputControl(title: "水平长度", value: calibrationRunBinding, range: 0...1000, step: 0.5, unit: "cm")
                    if liveCalibration?.maximumGradePercent == nil {
                        Label("档位未校准：仅记录档位，耗能中心改用心率/MET。", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(FitTheme.warning)
                    }
                }
                Picker("扶把", selection: handrailBinding) {
                    ForEach(HandrailSupport.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if [.cycling, .rowing].contains(draft.modality) {
                NumericInputControl(title: "当前功率", value: powerBinding, range: 0...1000, step: 5, unit: "W")
            }
            if [.running, .briskWalking, .inclineWalking].contains(draft.modality) {
                NumericInputControl(title: "跑步机确认距离", value: distanceBinding, range: 0...300, step: 0.01, unit: "km")
                Text("传感器距离与跑步机确认距离分开保留；确认距离用于最终记录。")
                    .font(.caption2).foregroundStyle(FitTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceCard(_ draft: CardioSessionDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(motion.statusMessage, systemImage: "sensor.tag.radiowaves.forward.fill")
            Text(liveSensors.statusMessage).font(.caption).foregroundStyle(.secondary)
            if let gap = draft.dataGapReason {
                Label(gap, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(FitTheme.warning)
            }
            ForEach(draft.workloadWarnings, id: \.self) {
                Label($0, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(FitTheme.warning)
            }
            if draft.modality == .swimming && liveSensors.activeLiveSource?.kind != .appleWatch {
                Text("划水次数：不可用（无 Apple Watch 数据，不进行虚假估算）").font(.caption).foregroundStyle(FitTheme.warning)
            }
        }
        .fitCard()
    }

    private func startSensorsIfNeeded() {
        guard let draft = store.activeCardioDraft else { return }
        liveSensors.beginWorkout(sessionID: draft.id, activity: draft.modality.rawValue)
        motion.onSample = { store.appendCardioMetricSample($0) }
        motion.onDataGap = { store.markCardioDataGap($0) }
        motion.start(modality: draft.modality, from: draft.startedAt)
    }

    private func loadControls(from draft: CardioSessionDraft) {
        let workload = draft.currentWorkload
        liveSpeedKph = workload?.speedKph ?? 0
        liveInclineMode = workload?.resolvedInclineInputMode ?? .percentGrade
        liveInclinePercent = workload?.inclinePercent ?? 20
        liveInclineLevel = workload?.inclineLevel ?? 20
        liveMachineMaximumLevel = workload?.machineMaximumLevel ?? 20
        liveCalibrationRise = workload?.maximumGradeCalibration?.rise ?? 0
        liveCalibrationRun = workload?.maximumGradeCalibration?.horizontalRun ?? 0
        livePowerWatts = workload?.powerWatts ?? 0
        liveHandrailSupport = workload?.handrailSupport ?? .none
        confirmedDistanceKm = (draft.confirmedDistanceMeters ?? 0) / 1_000
    }

    private func persistWorkload() {
        guard let modality = store.activeCardioDraft?.modality else { return }
        let inclineWalking = modality == .inclineWalking
        store.updateCardioWorkload(
            speedKph: [.running, .briskWalking, .inclineWalking].contains(modality) && liveSpeedKph > 0 ? liveSpeedKph : nil,
            inclinePercent: inclineWalking && liveInclineMode == .percentGrade ? liveInclinePercent : nil,
            inclineInputMode: inclineWalking ? liveInclineMode : nil,
            inclineLevel: inclineWalking && liveInclineMode == .machineLevel ? liveInclineLevel : nil,
            machineMaximumLevel: inclineWalking && liveInclineMode == .machineLevel ? liveMachineMaximumLevel : nil,
            maximumGradeCalibration: inclineWalking && liveInclineMode == .machineLevel ? liveCalibration : nil,
            powerWatts: [.cycling, .rowing].contains(modality) && livePowerWatts > 0 ? livePowerWatts : nil,
            handrailSupport: inclineWalking ? liveHandrailSupport : .none
        )
    }

    private var liveCalibration: TreadmillGradeCalibration? {
        guard liveCalibrationRise > 0 || liveCalibrationRun > 0 else { return nil }
        return .init(rise: liveCalibrationRise, horizontalRun: liveCalibrationRun)
    }

    private func workloadSummary(for modality: CardioModality) -> String {
        if modality == .inclineWalking, liveInclineMode == .machineLevel {
            let grade = liveCalibration?.maximumGradePercent.map {
                $0 * min(1, max(0, liveInclineLevel / liveMachineMaximumLevel))
            }
            return grade.map { "档位 \(Int(liveInclineLevel))/\(Int(liveMachineMaximumLevel)) · \($0.formatted(.number.precision(.fractionLength(1))))%" }
                ?? "档位 \(Int(liveInclineLevel))/\(Int(liveMachineMaximumLevel)) · 未校准"
        }
        if modality == .inclineWalking {
            return "\(liveSpeedKph.formatted(.number.precision(.fractionLength(1)))) km/h · \(liveInclinePercent.formatted(.number.precision(.fractionLength(1))))%"
        }
        if [.cycling, .rowing].contains(modality) {
            return "\(Int(livePowerWatts.rounded())) W"
        }
        if [.running, .briskWalking].contains(modality) {
            return "\(liveSpeedKph.formatted(.number.precision(.fractionLength(1)))) km/h"
        }
        return "实时采集中"
    }

    private func workloadBinding(_ value: Binding<Double>) -> Binding<Double> {
        Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; persistWorkload() })
    }

    private var speedBinding: Binding<Double> { workloadBinding($liveSpeedKph) }
    private var inclineBinding: Binding<Double> { workloadBinding($liveInclinePercent) }
    private var inclineLevelBinding: Binding<Double> { workloadBinding($liveInclineLevel) }
    private var maximumLevelBinding: Binding<Double> { workloadBinding($liveMachineMaximumLevel) }
    private var calibrationRiseBinding: Binding<Double> { workloadBinding($liveCalibrationRise) }
    private var calibrationRunBinding: Binding<Double> { workloadBinding($liveCalibrationRun) }
    private var powerBinding: Binding<Double> { workloadBinding($livePowerWatts) }
    private var inclineModeBinding: Binding<TreadmillInclineInputMode> {
        Binding(get: { liveInclineMode }, set: { liveInclineMode = $0; persistWorkload() })
    }
    private var handrailBinding: Binding<HandrailSupport> {
        Binding(get: { liveHandrailSupport }, set: { liveHandrailSupport = $0; persistWorkload() })
    }
    private var distanceBinding: Binding<Double> {
        Binding(get: { confirmedDistanceKm }, set: {
            confirmedDistanceKm = $0
            store.setConfirmedCardioDistance(meters: $0 > 0 ? $0 * 1_000 : nil)
        })
    }

    private func finish(_ status: WorkoutCompletionStatus) {
        motion.stop()
        liveSensors.endWorkout()
        WorkoutActivityController.shared.end()
        _ = store.finishCardioSession(status: status)
        dismiss()
    }

    private func updateLiveActivity() {
        guard let draft = store.activeCardioDraft else { return }
        WorkoutActivityController.shared.startOrUpdate(.cardio(draft: draft, heartRate: liveSensors.latestValidity == .valid ? liveSensors.latestSample?.heartRateBPM : nil))
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}
