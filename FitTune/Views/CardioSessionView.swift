import SwiftUI

struct CardioSessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(LiveSensorCoordinator.self) private var liveSensors
    @Environment(\.dismiss) private var dismiss
    @State private var motion = MotionLocationSource()
    @State private var showExitDialog = false
    @State private var showDiscardAlert = false

    var body: some View {
        ZStack {
            FitBackground()
            if let draft = store.activeCardioDraft {
                VStack(spacing: 0) {
                    topBar(draft)
                    ScrollView {
                        VStack(spacing: 18) {
                            sessionMetrics(draft)
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
        .onAppear { startSensorsIfNeeded(); updateLiveActivity() }
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
                    MetricChip(value: String(format: "%.2f", draft.distanceMeters / 1000), label: "距离 km", tint: FitTheme.accentBlue)
                    MetricChip(value: draft.metricSamples.compactMap(\.cadence).last.map { "\(Int($0.rounded()))" } ?? "—", label: "步频/踏频")
                }
            }
            .fitCard(padding: 22)
        }
    }

    private func sourceCard(_ draft: CardioSessionDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(motion.statusMessage, systemImage: "sensor.tag.radiowaves.forward.fill")
            Text(liveSensors.statusMessage).font(.caption).foregroundStyle(.secondary)
            if let gap = draft.dataGapReason {
                Label(gap, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(FitTheme.warning)
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
