import SwiftUI

struct SportSessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(LiveSensorCoordinator.self) private var liveSensors
    @Environment(\.dismiss) private var dismiss
    @State private var motion = MotionLocationSource()
    @State private var showExitDialog = false
    @State private var showFinishSheet = false
    @State private var showDiscardAlert = false
    @State private var sessionRPE = 6.0

    var body: some View {
        ZStack {
            FitBackground()
            if let draft = store.activeSportDraft {
                VStack(spacing: 0) {
                    topBar(draft)
                    ScrollView {
                        VStack(spacing: 16) {
                            hero(draft)
                            metricGrid(draft)
                            sourceCard(draft)
                        }
                        .padding(18)
                        .padding(.bottom, 100)
                    }
                }
                .safeAreaInset(edge: .bottom) { controlDock(draft) }
            }
        }
        .interactiveDismissDisabled()
        .onAppear { startSensorsIfNeeded(); updateLiveActivity() }
        .onChange(of: liveSensors.latestSample?.id) { _, _ in
            guard let sample = liveSensors.latestSample else { return }
            store.appendSportMetricSample(sample, validity: liveSensors.latestValidity)
            updateLiveActivity()
        }
        .onChange(of: store.activeSportDraft?.updatedAt) { _, _ in updateLiveActivity() }
        .onChange(of: liveSensors.latestWatchEvent) { _, event in
            guard event?.sessionID == store.activeSportDraft?.id, event?.event == .ended else { return }
            finish(status: .partial)
        }
        .confirmationDialog("离开当前运动？", isPresented: $showExitDialog, titleVisibility: .visible) {
            Button("继续未完成运动") {}
            Button("保存并结束") { showFinishSheet = true }
            Button("放弃运动", role: .destructive) { showDiscardAlert = true }
        } message: { Text("每 15 秒、暂停和进入后台时都会自动保存。") }
        .alert("确认放弃？", isPresented: $showDiscardAlert) {
            Button("取消", role: .cancel) {}
            Button("放弃", role: .destructive) { discard() }
        }
        .sheet(isPresented: $showFinishSheet) { finishSheet }
    }

    private func topBar(_ draft: SportSessionDraft) -> some View {
        HStack {
            Button { showExitDialog = true } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44).background(FitTheme.surface, in: Circle())
            }.buttonStyle(.plain)
            Spacer()
            VStack(spacing: 2) {
                Text(draft.kind.title).font(.headline)
                Text(draft.pausedAt == nil ? "实时记录中" : "已暂停")
                    .font(.caption2.bold()).foregroundStyle(draft.pausedAt == nil ? FitTheme.accent : FitTheme.warning)
            }
            Spacer()
            Image(systemName: draft.kind.symbol).foregroundStyle(FitTheme.accent).frame(width: 44)
        }
        .padding(.horizontal, 18)
    }

    private func hero(_ draft: SportSessionDraft) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 8) {
                Text(durationText(effectiveDuration(draft, at: context.date)))
                    .font(.system(size: 52, weight: .black, design: .rounded).monospacedDigit())
                Text("\(draft.environment.title) · \(draft.intensity.title)")
                    .font(.subheadline.bold()).foregroundStyle(FitTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .fitCard(padding: 24)
        }
    }

    private func metricGrid(_ draft: SportSessionDraft) -> some View {
        let samples = draft.metricSamples
        let heartRate = liveSensors.latestValidity == .valid ? liveSensors.latestSample?.heartRateBPM : samples.compactMap(\.heartRateBPM).last
        let distance = samples.compactMap(\.distanceMeters).max()
        let cadence = samples.compactMap(\.cadence).last
        let elevation = samples.compactMap(\.elevationGainMeters).max()
        let steps = samples.compactMap(\.steps).max()
        let capabilities = SportAnalysisEngine.capabilities(
            kind: draft.kind,
            environment: draft.environment,
            hasHeartRate: heartRate != nil,
            hasLocation: distance != nil,
            hasPedometer: steps != nil || cadence != nil,
            hasElevation: elevation != nil
        )
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            MetricChip(value: heartRate.map { "\(Int($0.rounded()))" } ?? "—", label: "实时心率 bpm", tint: FitTheme.danger)
            if capabilities.contains(.distance) { MetricChip(value: distance.map { String(format: "%.2f", $0 / 1_000) } ?? "—", label: "距离 km", tint: FitTheme.accentBlue) }
            if capabilities.contains(.steps) { MetricChip(value: steps.map(String.init) ?? "—", label: "运动步数") }
            if capabilities.contains(.cadence) { MetricChip(value: cadence.map { "\(Int($0.rounded()))" } ?? "—", label: "步频/踏频") }
            if capabilities.contains(.elevationGain) { MetricChip(value: elevation.map { "\(Int($0.rounded()))" } ?? "—", label: "累计爬升 m", tint: FitTheme.warning) }
        }
    }

    private func sourceCard(_ draft: SportSessionDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(motion.statusMessage, systemImage: "location.fill.viewfinder")
            Text(liveSensors.statusMessage).font(.caption).foregroundStyle(FitTheme.secondaryText)
            if !draft.dataGapReasons.isEmpty {
                ForEach(draft.dataGapReasons.suffix(2), id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(FitTheme.warning) }
            }
            Text("当前仅展示可验证数据，不推测击球、触球、冲刺或攀岩等级。")
                .font(.caption2).foregroundStyle(FitTheme.secondaryText)
        }
        .fitCard()
    }

    private func controlDock(_ draft: SportSessionDraft) -> some View {
        HStack(spacing: 12) {
            Button {
                if draft.pausedAt == nil {
                    store.pauseSportSession(); liveSensors.pauseWorkout(); motion.stop()
                } else {
                    store.resumeSportSession(); liveSensors.resumeWorkout(); motion.resume(sport: draft.kind, environment: draft.environment)
                }
                updateLiveActivity()
            } label: {
                Label(draft.pausedAt == nil ? "暂停" : "继续", systemImage: draft.pausedAt == nil ? "pause.fill" : "play.fill")
                    .frame(minWidth: 90, minHeight: 50)
            }
            .buttonStyle(.borderedProminent).tint(FitTheme.elevated)
            Button { showFinishSheet = true } label: {
                Label("结束并总结", systemImage: "flag.checkered")
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var finishSheet: some View {
        NavigationStack {
            VStack(spacing: 22) {
                SectionHeading(eyebrow: "SESSION RPE", title: "这次运动有多累？", detail: "0 为休息，10 为最大努力；用于计算可比较的训练负荷。")
                Text("\(Int(sessionRPE))").font(.system(size: 58, weight: .black, design: .rounded)).foregroundStyle(FitTheme.accent)
                Slider(value: $sessionRPE, in: 0...10, step: 1).tint(FitTheme.accent)
                Button { finish(status: .completed) } label: { Label("生成训练总结", systemImage: "chart.xyaxis.line") }
                    .buttonStyle(PrimaryActionButtonStyle())
                Spacer()
            }
            .padding(20)
            .navigationTitle("完成运动")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回") { showFinishSheet = false } } }
        }
        .presentationDetents([.medium])
    }

    private func startSensorsIfNeeded() {
        guard let draft = store.activeSportDraft else { return }
        liveSensors.beginWorkout(sessionID: draft.id, activity: "\(draft.kind.watchActivityKey)|\(draft.environment.rawValue)")
        motion.onSample = { store.appendSportMetricSample($0, validity: .valid) }
        motion.onDataGap = { store.markSportDataGap($0) }
        startMotion(for: draft)
    }

    private func startMotion(for draft: SportSessionDraft) {
        motion.start(sport: draft.kind, environment: draft.environment, from: .now)
    }

    private func finish(status: WorkoutCompletionStatus) {
        motion.stop(); liveSensors.endWorkoutCollectionKeepingPreference(); WorkoutActivityController.shared.end()
        _ = store.finishSportSession(status: status, sessionRPE: sessionRPE)
        dismiss()
    }

    private func discard() {
        motion.stop(); liveSensors.endWorkoutCollectionKeepingPreference(); WorkoutActivityController.shared.end()
        store.discardSportSession(); dismiss()
    }

    private func updateLiveActivity() {
        guard let draft = store.activeSportDraft else { return }
        WorkoutActivityController.shared.startOrUpdate(.sport(draft: draft, heartRate: liveSensors.latestValidity == .valid ? liveSensors.latestSample?.heartRateBPM : nil))
    }

    private func effectiveDuration(_ draft: SportSessionDraft, at date: Date) -> TimeInterval {
        let end = draft.pausedAt ?? date
        let paused = draft.pauseIntervals.reduce(0.0) { $0 + $1.endedAt.timeIntervalSince($1.startedAt) }
        return max(0, end.timeIntervalSince(draft.startedAt) - paused)
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}
