import SwiftUI

struct DeviceCenterView: View {
    @Environment(LiveSensorCoordinator.self) private var sensors

    var body: some View {
        List {
            Section("当前实时来源") {
                if let active = sensors.activeLiveSource {
                    Label(active.name, systemImage: active.kind == .appleWatch ? "applewatch" : "heart.circle.fill")
                    Text(sensors.statusMessage).font(.caption).foregroundStyle(.secondary)
                    Button("断开实时设备", role: .destructive) { sensors.disconnect() }
                } else {
                    Label("手机估算", systemImage: "iphone")
                    Text(sensors.statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Apple Watch") {
                HStack {
                    Label("Apple Watch 实时训练", systemImage: "applewatch")
                    Spacer()
                    Text("未检测").font(.caption).foregroundStyle(.secondary)
                }
                Text("购买并配对 Apple Watch 后，可在此选择为唯一实时来源。华为健康的事后同步不占用实时连接位。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("标准蓝牙心率设备") {
                Button { sensors.scanBluetooth() } label: {
                    Label(sensors.state == .scanning ? "正在扫描…" : "扫描心率带/广播设备", systemImage: "dot.radiowaves.left.and.right")
                }
                ForEach(sensors.discoveredSources.filter { $0.kind == .bluetooth }) { source in
                    Button { sensors.select(source) } label: {
                        HStack {
                            Text(source.name)
                            Spacer()
                            if sensors.activeLiveSource?.id == source.id { Image(systemName: "checkmark.circle.fill") }
                        }
                    }
                }
                Text("仅连接实现标准 Bluetooth Heart Rate Service 的设备。FIT 3 通常不会向第三方应用广播实时心率，因此不会虚假显示为可直连。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("数据质量") {
                LabeledContent("连接状态", value: sensors.state.rawValue)
                LabeledContent("最近样本", value: sensors.latestValidity.rawValue)
                Text("心率过期、突跳或接触不良时会被排除，训练继续运行并明确降级为估算。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设备与实时数据")
        .alert("切换实时设备？", isPresented: Binding(
            get: { sensors.pendingSwitch != nil },
            set: { if !$0 { sensors.cancelSwitch() } }
        )) {
            Button("取消", role: .cancel) { sensors.cancelSwitch() }
            Button("确认切换") { sensors.confirmSwitch() }
        } message: {
            Text("切换会断开当前实时来源。同一时间只能使用一个实时设备。")
        }
    }
}
