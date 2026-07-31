import SwiftUI

struct SportsHubView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedKind: SportKind?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            FitBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeading(
                        eyebrow: "SPORTS · REAL TIME",
                        title: "开始一场运动",
                        detail: "实时记录可用心率、距离、步数与爬升；缺少设备时仍可正常训练。"
                    )

                    if let recent = store.sportWorkouts.first {
                        Button { selectedKind = recent.kind } label: {
                            HStack(spacing: 14) {
                                Image(systemName: recent.kind.symbol)
                                    .font(.title2.bold())
                                    .frame(width: 50, height: 50)
                                    .foregroundStyle(FitTheme.background)
                                    .background(FitTheme.accent, in: RoundedRectangle(cornerRadius: 15))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("再次开始 \(recent.kind.title)").font(.headline)
                                    Text("上次 \(recent.completedAt.formatted(date: .abbreviated, time: .shortened)) · \(Int(recent.analysis.effectiveDurationSeconds / 60)) 分钟")
                                        .font(.caption).foregroundStyle(FitTheme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(FitTheme.accent)
                            }
                            .fitCard()
                        }
                        .buttonStyle(.plain)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(SportKind.allCases, id: \.self) { kind in
                            Button { selectedKind = kind } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    Image(systemName: kind.symbol)
                                        .font(.title2.bold())
                                        .foregroundStyle(FitTheme.accent)
                                        .frame(width: 44, height: 44)
                                        .background(FitTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                                    Text(kind.title).font(.headline)
                                    Text(capabilityHint(kind))
                                        .font(.caption2).foregroundStyle(FitTheme.secondaryText)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
                                .fitCard(padding: 14)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("开始\(kind.title)")
                        }
                    }

                    if !store.sportWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("最近运动").font(.title3.bold())
                            ForEach(store.sportWorkouts.prefix(4)) { record in
                                NavigationLink {
                                    SportHistoryDetailView(record: record)
                                } label: {
                                    SportHistoryRow(record: record)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 26)
            }
        }
        .navigationTitle("运动")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedKind) { kind in
            SportSetupSheet(kind: kind)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func capabilityHint(_ kind: SportKind) -> String {
        switch kind {
        case .badminton, .tableTennis: "时长 · 心率 · 步数"
        case .soccer: "心率 · 距离 · 速度"
        case .climbing: "时长 · 心率 · 户外爬升"
        case .hiking, .mountaineering, .trailRunning: "距离 · 配速 · 海拔爬升"
        }
    }
}

private struct SportSetupSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let kind: SportKind
    @State private var environment: SportEnvironment
    @State private var intensity: SportIntensity = .training

    init(kind: SportKind) {
        self.kind = kind
        _environment = State(initialValue: kind.defaultEnvironment)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(kind.title, systemImage: kind.symbol).font(.title2.bold())
                    if kind.availableEnvironments.count > 1 {
                        Picker("环境", selection: $environment) {
                            ForEach(kind.availableEnvironments, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Picker("强度", selection: $intensity) {
                        ForEach(SportIntensity.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button {
                        store.startSportSession(kind: kind, environment: environment, intensity: intensity)
                        dismiss()
                    } label: {
                        Label("开始实时记录", systemImage: "play.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                } footer: {
                    Text("传感器或权限缺失不会阻止开始；不可用指标会隐藏并降低可信度。")
                }
            }
            .navigationTitle("运动设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

struct SportHistoryRow: View {
    let record: SportSessionRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.kind.symbol)
                .foregroundStyle(FitTheme.accent)
                .frame(width: 42, height: 42)
                .background(FitTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(record.kind.title).font(.headline)
                Text("\(record.completedAt.formatted(date: .abbreviated, time: .shortened)) · \(Int(record.analysis.effectiveDurationSeconds / 60)) 分钟")
                    .font(.caption).foregroundStyle(FitTheme.secondaryText)
            }
            Spacer()
            Text("\(Int(record.analysis.sessionRPELoadAU.rounded())) AU")
                .font(.caption.bold().monospacedDigit()).foregroundStyle(FitTheme.accentBlue)
        }
        .fitCard(padding: 13)
    }
}
