import SwiftUI

struct SafetySettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var settings = PersonalSafetySettings()

    var body: some View {
        Form {
            Section("伤病与避用部位") {
                ForEach(BodyRegion.allCases) { region in
                    Toggle(region.title, isOn: binding(for: region))
                }
            }
            Section("提醒阈值") {
                Stepper("疼痛阈值：\(settings.painAlertThreshold)/5", value: $settings.painAlertThreshold, in: 1...5)
                Toggle("启用最大心率提醒", isOn: Binding(get: { settings.maximumHeartRateAlert != nil }, set: { settings.maximumHeartRateAlert = $0 ? 180 : nil }))
                if settings.maximumHeartRateAlert != nil {
                    Stepper("最大心率：\(settings.maximumHeartRateAlert ?? 180) bpm", value: Binding(get: { settings.maximumHeartRateAlert ?? 180 }, set: { settings.maximumHeartRateAlert = $0 }), in: 100...230)
                }
            }
            Section {
                Text("这些阈值只产生醒目建议和停止入口，不会自动结束动作或训练。临时手选禁用动作时仍允许继续，但会显示安全提示。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("个人安全阈值")
        .onAppear { settings = store.safetySettings }
        .onChange(of: settings) { _, value in store.updateSafetySettings(value) }
    }

    private func binding(for region: BodyRegion) -> Binding<Bool> {
        Binding(get: { settings.avoidedRegions.contains(region) }, set: { enabled in
            if enabled { settings.avoidedRegions.insert(region) } else { settings.avoidedRegions.remove(region) }
        })
    }
}
