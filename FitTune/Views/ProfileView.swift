import SwiftUI

private enum TrashRecord {
    case workout(UUID, String)
    case cardio(UUID, String)
    case weight(UUID, String)

    var title: String {
        switch self {
        case let .workout(_, title), let .cardio(_, title), let .weight(_, title): title
        }
    }
}

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(HealthDataSyncCoordinator.self) private var healthSync

    @State private var goal: TrainingGoal = .recomposition
    @State private var secondaryGoal: SecondaryGoal = .none
    @State private var experience: ExperienceLevel = .autoAssess
    @State private var splitPreference: TrainingSplit = .automatic
    @State private var strengthTrainingGoal: StrengthTrainingGoal = .balanced
    @State private var cardioTrainingGoal: CardioTrainingGoal = .fatLoss
    @State private var weeklyDays = 3
    @State private var sessionMinutes = 60
    @State private var equipment: EquipmentProfile = .fullGym
    @State private var ageYears = 30
    @State private var heightCm = 170
    @State private var biologicalSex: BiologicalSex = .notSet
    @State private var bodyWeightKg = 70.0
    @State private var bodyFatPercent = 0.0
    @State private var leanMassKg = 0.0
    @State private var waistCm = 0.0
    @State private var measuredRMRKcal = 0.0
    @State private var restingHeartRate = 0.0
    @State private var measuredMaxHeartRate = 0.0
    @State private var showRegenerateAlert = false
    @State private var showResetAlert = false
    @State private var didSave = false
    @State private var showRecords = false
    @State private var showClearRecordsAlert = false
    @State private var bodyDataSaved = false
    @State private var pendingPermanentDeletion: TrashRecord?
    @State private var showEmptyTrashAlert = false
    @State private var exportURLs: [URL] = []
    @State private var exportError: String?
    @State private var showClearImportedHealthAlert = false

    var body: some View {
        ZStack {
            FitBackground()
            ScrollView {
                VStack(spacing: 18) {
                    profileHeader
                    goalSettings
                    scheduleSettings
                    energyProfileSettings
                    NavigationLink {
                        DeviceCenterView()
                    } label: {
                        HStack {
                            Label("设备与实时数据", systemImage: "applewatch.radiowaves.left.and.right")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(FitTheme.secondaryText)
                        }
                        .fitCard()
                    }
                    .buttonStyle(.plain)
                    recordManagementCard
                    dataAndSafetyCard
                    algorithmInfo
                    resetButton
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("我的设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadDraft() }
        .alert("重新生成训练计划？", isPresented: $showRegenerateAlert) {
            Button("取消", role: .cancel) {}
            Button("确认生成") { saveAndRegenerate() }
        } message: {
            Text("新的目标和经验等级会改变之后的计划；已完成的训练记录会保留。")
        }
        .alert("清除全部本地数据？", isPresented: $showResetAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { store.resetAllData() }
        } message: {
            Text("这会删除个人资料、训练计划、力量/有氧记录、体重和恢复记录，无法撤销。")
        }
        .alert("将全部记录移入回收站？", isPresented: $showClearRecordsAlert) {
            Button("取消", role: .cancel) {}
            Button("移入回收站", role: .destructive) { store.clearRecordObjectsToTrash() }
        } message: { Text("训练、心肺、体重、身体组成与恢复记录会从趋势中移除，但仍可在回收站恢复。") }
        .alert("清除导入的健康数据？", isPresented: $showClearImportedHealthAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { store.clearImportedHealthData() }
        } message: {
            Text("将删除本机保存的静息心率和 Apple 健康/华为健康导入值；手动恢复评分与训练记录保留。")
        }
        .sheet(isPresented: $showRecords) { recordsSheet }
    }

    private var profileHeader: some View {
        HStack(spacing: 15) {
            Image(systemName: store.profile?.experience.symbol ?? "person.fill")
                .font(.title2)
                .foregroundStyle(FitTheme.background)
                .frame(width: 58, height: 58)
                .background(FitTheme.accent, in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 4) {
                Text(store.profile?.nickname.isEmpty == false ? store.profile?.nickname ?? "" : "FitTune 用户")
                    .font(.title2.bold())
                Text("\(store.profile?.goal.title ?? "—") · \(store.profile?.experience.title ?? "—")")
                    .font(.subheadline)
                    .foregroundStyle(FitTheme.secondaryText)
            }
            Spacer()
        }
        .padding(.top, 10)
    }

    private var goalSettings: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeading(eyebrow: "可随训练块调整", title: "目标与经验")
            settingPicker(title: "主目标", selection: $goal, options: TrainingGoal.allCases) { $0.title }
            settingPicker(title: "次目标", selection: $secondaryGoal, options: SecondaryGoal.allCases) { $0.title }
            settingPicker(title: "力量模块", selection: $strengthTrainingGoal, options: StrengthTrainingGoal.allCases) { $0.title }
            settingPicker(title: "有氧模块", selection: $cardioTrainingGoal, options: CardioTrainingGoal.allCases) { $0.title }
            settingPicker(title: "训练经验", selection: $experience, options: ExperienceLevel.allCases) { $0.title }

            Button {
                showRegenerateAlert = true
            } label: {
                Label(didSave ? "计划已更新" : "保存并重新生成计划", systemImage: didSave ? "checkmark" : "wand.and.stars")
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
        .fitCard(padding: 17)
    }

    private var scheduleSettings: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("训练条件").font(.headline)
            settingPicker(title: "训练分化", selection: $splitPreference, options: TrainingSplit.allCases) { $0.title }
            Text(splitPreference.subtitle)
                .font(.caption)
                .foregroundStyle(FitTheme.secondaryText)
            Stepper("每周力量训练 \(weeklyDays) 天", value: $weeklyDays, in: minimumTrainingDays...6)
            Stepper("每次 \(sessionMinutes) 分钟", value: $sessionMinutes, in: 30...90, step: 15)
            settingPicker(title: "器械", selection: $equipment, options: EquipmentProfile.allCases) { $0.title }
        }
        .fitCard()
        .onChange(of: splitPreference) { _, _ in
            weeklyDays = max(weeklyDays, minimumTrainingDays)
        }
    }

    private var algorithmInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("算法透明度", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(FitTheme.accent)
            Text("训练建议由透明规则生成。下组重量只依据完成次数、RIR、今日恢复和历史记录；动作质量与疼痛作为独立安全提示。组间休息显示范围、原因和置信度，但重量、组数与是否继续始终由用户决定。")
                .font(.subheadline)
                .foregroundStyle(FitTheme.secondaryText)
            HStack {
                Text("规则版本")
                Spacer()
                Text(store.plan?.ruleVersion ?? TrainingEngine.ruleVersion)
                    .font(.caption.monospaced())
                    .foregroundStyle(FitTheme.accentBlue)
            }
            NavigationLink("查看公式、版本、限制与论文依据") { AlgorithmInfoView() }
                .font(.subheadline.bold())
        }
        .fitCard()
    }

    private var dataAndSafetyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("数据、隐私与安全", systemImage: "lock.shield")
                .font(.headline).foregroundStyle(FitTheme.accent)
            Text("健康与训练数据默认保存在本机。JSON 是完整备份；CSV 用于表格分析，不等同于完整备份。")
                .font(.subheadline).foregroundStyle(FitTheme.secondaryText)
            NavigationLink("个人安全阈值与伤病部位") { SafetySettingsView() }
            VStack(alignment: .leading, spacing: 6) {
                Text("Apple 健康读取状态").font(.subheadline.bold())
                healthPermissionRow("静息心率", metric: .restingHeartRate, state: healthSync.snapshot.restingHeartRate.syncState)
                healthPermissionRow("步数", metric: .steps, state: healthSync.snapshot.steps.syncState)
                healthPermissionRow("步行/跑步距离", metric: .walkingDistanceKm, state: healthSync.snapshot.walkingDistanceKm.syncState)
                healthPermissionRow("全天主动热量", metric: .activeEnergyKcal, state: healthSync.snapshot.activeEnergyKcal.syncState)
                Button("立即刷新健康数据") {
                    Task { await healthSync.refreshToday(reason: .manual) }
                }
                .disabled(healthSync.isRefreshing)
            }
            Button("生成 JSON + CSV 导出文件") {
                do { exportURLs = try store.makeExportFiles(); exportError = nil }
                catch { exportError = error.localizedDescription }
            }
            .buttonStyle(PrimaryActionButtonStyle())
            if !exportURLs.isEmpty {
                ShareLink(items: exportURLs) {
                    Label("分享 5 个导出文件", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
            }
            if let exportError { Text(exportError).font(.caption).foregroundStyle(FitTheme.danger) }
            Button("清除已导入的健康数据", role: .destructive) { showClearImportedHealthAlert = true }
                .foregroundStyle(FitTheme.danger)
        }
        .fitCard()
    }

    private func healthPermissionRow(_ title: String, metric: DailyHealthMetric, state: HealthSyncState) -> some View {
        HStack {
            Text(title).font(.caption)
            Spacer()
            Text(healthSync.permissions[metric] == false ? "未授权" : syncStateTitle(state))
                .font(.caption.bold())
                .foregroundStyle(state == .current ? FitTheme.accent : FitTheme.warning)
        }
    }

    private func syncStateTitle(_ state: HealthSyncState) -> String {
        switch state {
        case .current: "已更新"
        case .delayed: "延迟"
        case .permissionMissing: "未授权"
        case .syncing: "同步中"
        case .estimated: "估算"
        case .failed: "失败"
        case .unavailable: "暂无数据"
        }
    }

    private var energyProfileSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("身体组成与代谢资料").font(.headline)
            IntegerInputControl(title: "年龄", value: $ageYears, range: 14...100, step: 1, unit: "岁")
            IntegerInputControl(title: "身高", value: $heightCm, range: 120...230, step: 1, unit: "cm")
            settingPicker(title: "生理性别", selection: $biologicalSex, options: BiologicalSex.allCases) { $0.title }
            NumericInputControl(title: "体重", value: $bodyWeightKg, range: 20...400, step: 0.1, unit: "kg")
            NumericInputControl(title: "体脂率（可选）", value: $bodyFatPercent, range: 0...65, step: 0.1, unit: "%")
            NumericInputControl(title: "去脂体重（可选）", value: $leanMassKg, range: 0...250, step: 0.1, unit: "kg")
            NumericInputControl(title: "腰围（可选）", value: $waistCm, range: 0...250, step: 0.1, unit: "cm")
            NumericInputControl(title: "实测静息代谢（可选）", value: $measuredRMRKcal, range: 0...5000, step: 10, unit: "kcal/日")
            NumericInputControl(title: "静息心率（可选）", value: $restingHeartRate, range: 0...220, step: 1, unit: "bpm")
            NumericInputControl(title: "实测最大心率（可选）", value: $measuredMaxHeartRate, range: 0...240, step: 1, unit: "bpm")
            if let estimate = draftRestingEstimate {
                VStack(alignment: .leading, spacing: 4) {
                    Text("静息消耗约 \(Int(estimate.kilocalories.rounded())) kcal/日").font(.headline).foregroundStyle(FitTheme.accent)
                    Text("\(Int(estimate.lowerBound.rounded()))–\(Int(estimate.upperBound.rounded())) kcal · \(estimate.method) · \(estimate.confidence)置信度")
                        .font(.caption).foregroundStyle(FitTheme.secondaryText)
                }
            }
            Button { saveBodyData() } label: {
                Label(bodyDataSaved ? "身体数据已保存" : "新增身体组成记录", systemImage: bodyDataSaved ? "checkmark" : "plus.circle.fill")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            Text("实测 RMR 优先；有去脂体重/体脂率时采用 Cunningham，否则使用 Mifflin–St Jeor。力量成绩不直接加入代谢公式，避免把技术进步误当成肌肉增长。")
                .font(.caption)
                .foregroundStyle(FitTheme.secondaryText)
        }
        .fitCard()
    }

    private var draftRestingEstimate: EnergyEstimate? {
        guard var profile = store.profile else { return nil }
        profile.ageYears = ageYears
        profile.heightCm = Double(heightCm)
        profile.biologicalSex = biologicalSex
        profile.bodyWeightKg = bodyWeightKg
        profile.bodyFatPercent = bodyFatPercent > 0 ? bodyFatPercent : nil
        profile.leanMassKg = leanMassKg > 0 ? leanMassKg : nil
        profile.measuredRMRKcal = measuredRMRKcal > 0 ? measuredRMRKcal : nil
        return TrainingEngine.restingEnergyEstimate(profile: profile, weightKg: bodyWeightKg)
    }

    private var recordManagementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("记录对象与回收站", systemImage: "externaldrive.badge.timemachine")
                .font(.headline).foregroundStyle(FitTheme.accent)
            Text("可单独删除误操作的力量、有氧或体重记录；删除后进入回收站，可随时恢复。")
                .font(.subheadline).foregroundStyle(FitTheme.secondaryText)
            HStack(spacing: 8) {
                MetricChip(value: "\(store.workoutHistory.count)", label: "力量")
                MetricChip(value: "\(store.cardioWorkouts.count)", label: "有氧", tint: FitTheme.accentBlue)
                MetricChip(value: "\(store.deletedRecordCount)", label: "回收站", tint: FitTheme.warning)
            }
            Button("管理与恢复记录") { showRecords = true }.buttonStyle(PrimaryActionButtonStyle())
            Button("全部记录移入回收站", role: .destructive) { showClearRecordsAlert = true }
                .font(.subheadline.bold()).foregroundStyle(FitTheme.danger).frame(maxWidth: .infinity)
        }
        .fitCard()
    }

    private var recordsSheet: some View {
        NavigationStack {
            List {
                Section("力量训练") {
                    if store.workoutHistory.isEmpty { Text("暂无记录").foregroundStyle(.secondary) }
                    ForEach(store.workoutHistory) { item in
                        recordRow(
                            title: item.sessionName,
                            detail: "\(item.completedAt.formatted(date: .abbreviated, time: .shortened)) · \(item.sets.count) 组",
                            clearMetrics: item.metricSamples?.isEmpty == false ? { store.clearWorkoutMetrics(id: item.id) } : nil,
                            delete: { store.deleteWorkout(id: item.id) }
                        )
                    }
                }
                Section("有氧训练") {
                    if store.cardioWorkouts.isEmpty { Text("暂无记录").foregroundStyle(.secondary) }
                    ForEach(store.cardioWorkouts) { item in
                        recordRow(
                            title: item.modality.title,
                            detail: "\(item.date.formatted(date: .abbreviated, time: .shortened)) · \(item.durationMinutes) 分钟",
                            clearMetrics: item.metricSamples?.isEmpty == false ? { store.clearCardioMetrics(id: item.id) } : nil,
                            delete: { store.deleteCardioWorkout(id: item.id) }
                        )
                    }
                }
                Section("体重") {
                    ForEach(store.weightHistory.reversed()) { item in
                        recordRow(title: "\(item.kilograms.formatted(.number.precision(.fractionLength(1)))) kg", detail: item.date.formatted(date: .abbreviated, time: .shortened)) {
                            store.deleteWeight(id: item.id)
                        }
                    }
                }
                Section("回收站 · \(store.deletedRecordCount)") {
                    if store.deletedRecordCount == 0 { Text("回收站为空").foregroundStyle(.secondary) }
                    ForEach(store.deletedWorkoutHistory) { item in
                        restoreRow(title: "力量 · \(item.sessionName)", restore: { store.restoreWorkout(id: item.id) }) {
                            pendingPermanentDeletion = .workout(item.id, item.sessionName)
                        }
                    }
                    ForEach(store.deletedCardioWorkouts) { item in
                        restoreRow(title: "有氧 · \(item.modality.title)", restore: { store.restoreCardioWorkout(id: item.id) }) {
                            pendingPermanentDeletion = .cardio(item.id, item.modality.title)
                        }
                    }
                    ForEach(store.deletedWeightHistory) { item in
                        let title = "\(item.kilograms.formatted(.number.precision(.fractionLength(1)))) kg"
                        restoreRow(title: "体重 · \(title)", restore: { store.restoreWeight(id: item.id) }) {
                            pendingPermanentDeletion = .weight(item.id, title)
                        }
                    }
                    if store.deletedRecordCount > 0 {
                        Button("恢复回收站全部记录") { store.restoreAllDeletedRecords() }
                        Button("清空回收站", role: .destructive) { showEmptyTrashAlert = true }
                    }
                }
            }
            .navigationTitle("记录管理")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showRecords = false } } }
            .alert("永久删除记录？", isPresented: permanentDeletionPresented) {
                Button("取消", role: .cancel) { pendingPermanentDeletion = nil }
                Button("永久删除", role: .destructive) { permanentlyDeletePendingRecord() }
            } message: {
                Text("“\(pendingPermanentDeletion?.title ?? "该记录")”将无法恢复。")
            }
            .alert("清空回收站？", isPresented: $showEmptyTrashAlert) {
                Button("取消", role: .cancel) {}
                Button("永久删除全部", role: .destructive) { store.emptyTrash() }
            } message: {
                Text("回收站中的 \(store.deletedRecordCount) 条记录将无法恢复。")
            }
        }
    }

    private func recordRow(title: String, detail: String, clearMetrics: (() -> Void)? = nil, delete: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) { Text(title); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if let clearMetrics {
                Button(role: .destructive, action: clearMetrics) { Image(systemName: "waveform.path.badge.minus") }
                    .accessibilityLabel("仅清除 \(title) 的心率与设备曲线")
            }
            Button(role: .destructive, action: delete) { Image(systemName: "trash") }
        }
    }

    private func restoreRow(title: String, restore: @escaping () -> Void, permanentlyDelete: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button("恢复", action: restore)
            Button(role: .destructive, action: permanentlyDelete) {
                Image(systemName: "trash.slash")
            }
            .accessibilityLabel("永久删除 \(title)")
        }
    }

    private var permanentDeletionPresented: Binding<Bool> {
        Binding(
            get: { pendingPermanentDeletion != nil },
            set: { if !$0 { pendingPermanentDeletion = nil } }
        )
    }

    private func permanentlyDeletePendingRecord() {
        guard let record = pendingPermanentDeletion else { return }
        switch record {
        case let .workout(id, _): store.permanentlyDeleteWorkout(id: id)
        case let .cardio(id, _): store.permanentlyDeleteCardioWorkout(id: id)
        case let .weight(id, _): store.permanentlyDeleteWeight(id: id)
        }
        pendingPermanentDeletion = nil
    }

    private var resetButton: some View {
        Button(role: .destructive) { showResetAlert = true } label: {
            Label("清除全部本地数据", systemImage: "trash")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(FitTheme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        }
        .foregroundStyle(FitTheme.danger)
    }

    private func settingPicker<T: Hashable>(title: String, selection: Binding<T>, options: [T], label: @escaping (T) -> String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .tint(FitTheme.accent)
        }
    }

    private func loadDraft() {
        guard let profile = store.profile else { return }
        goal = profile.goal
        secondaryGoal = profile.secondaryGoal
        experience = profile.experience
        splitPreference = profile.splitPreference ?? .automatic
        strengthTrainingGoal = profile.strengthTrainingGoal ?? defaultStrengthGoal(for: profile.goal)
        cardioTrainingGoal = profile.cardioTrainingGoal ?? defaultCardioGoal(for: profile.goal)
        weeklyDays = profile.weeklyDays
        sessionMinutes = profile.sessionMinutes
        equipment = profile.equipment
        ageYears = profile.ageYears ?? 30
        heightCm = Int((profile.heightCm ?? 170).rounded())
        biologicalSex = profile.biologicalSex ?? .notSet
        bodyWeightKg = store.latestWeight ?? profile.bodyWeightKg
        bodyFatPercent = profile.bodyFatPercent ?? 0
        leanMassKg = profile.leanMassKg ?? 0
        measuredRMRKcal = profile.measuredRMRKcal ?? 0
        restingHeartRate = profile.restingHeartRate ?? 0
        measuredMaxHeartRate = profile.measuredMaxHeartRate ?? 0
    }

    private func saveAndRegenerate() {
        guard var profile = store.profile else { return }
        profile.goal = goal
        profile.secondaryGoal = secondaryGoal
        profile.experience = experience
        profile.splitPreference = splitPreference
        profile.strengthTrainingGoal = strengthTrainingGoal
        profile.cardioTrainingGoal = cardioTrainingGoal
        profile.weeklyDays = weeklyDays
        profile.sessionMinutes = sessionMinutes
        profile.equipment = equipment
        profile.loadIncrementKg = equipment == .fullGym ? 2.5 : 1
        profile.ageYears = ageYears
        profile.heightCm = Double(heightCm)
        profile.biologicalSex = biologicalSex
        profile.bodyWeightKg = bodyWeightKg
        profile.bodyFatPercent = bodyFatPercent > 0 ? bodyFatPercent : nil
        profile.leanMassKg = leanMassKg > 0 ? leanMassKg : nil
        profile.measuredRMRKcal = measuredRMRKcal > 0 ? measuredRMRKcal : nil
        profile.restingHeartRate = restingHeartRate > 0 ? restingHeartRate : nil
        profile.measuredMaxHeartRate = measuredMaxHeartRate > 0 ? measuredMaxHeartRate : nil
        store.updateProfileAndRegenerate(profile)
        withAnimation { didSave = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { didSave = false }
        }
    }

    private func saveBodyData() {
        guard var profile = store.profile else { return }
        profile.ageYears = ageYears
        profile.heightCm = Double(heightCm)
        profile.biologicalSex = biologicalSex
        profile.bodyWeightKg = bodyWeightKg
        profile.bodyFatPercent = bodyFatPercent > 0 ? bodyFatPercent : nil
        profile.leanMassKg = leanMassKg > 0 ? leanMassKg : nil
        profile.measuredRMRKcal = measuredRMRKcal > 0 ? measuredRMRKcal : nil
        profile.restingHeartRate = restingHeartRate > 0 ? restingHeartRate : nil
        profile.measuredMaxHeartRate = measuredMaxHeartRate > 0 ? measuredMaxHeartRate : nil
        store.updateProfileAndRegenerate(profile)
        store.addBodyComposition(weightKg: bodyWeightKg, bodyFatPercent: profile.bodyFatPercent, leanMassKg: profile.leanMassKg, waistCm: waistCm > 0 ? waistCm : nil)
        withAnimation { bodyDataSaved = true }
    }

    private var minimumTrainingDays: Int {
        switch splitPreference {
        case .automatic, .fullBody: 2
        case .upperLower, .pushPullLegs: 3
        case .chestBackShouldersLegs: 4
        }
    }

    private func defaultStrengthGoal(for goal: TrainingGoal) -> StrengthTrainingGoal {
        switch goal {
        case .strength: .maxStrength
        case .hypertrophy: .hypertrophy
        default: .balanced
        }
    }

    private func defaultCardioGoal(for goal: TrainingGoal) -> CardioTrainingGoal {
        switch goal {
        case .fatLoss, .recomposition: .fatLoss
        case .generalFitness: .aerobicBase
        default: .none
        }
    }
}
