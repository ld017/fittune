import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.profile == nil {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.profile == nil)
        .fullScreenCover(
            isPresented: Binding(
                get: { store.activeWorkoutDraft != nil },
                set: { _ in }
            )
        ) {
            WorkoutSessionView()
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { store.activeCardioDraft != nil },
                set: { _ in }
            )
        ) {
            CardioSessionView()
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { store.activeSportDraft != nil },
                set: { _ in }
            )
        ) {
            SportSessionView()
        }
        .sheet(item: Binding(
            get: { store.presentedSummary },
            set: { store.presentedSummary = $0 }
        )) { summary in
            WorkoutSummaryView(presentation: summary)
        }
        .sheet(item: Binding(
            get: { store.presentedSportRecord },
            set: { store.presentedSportRecord = $0 }
        )) { record in
            NavigationStack { SportHistoryDetailView(record: record) }
        }
    }
}

struct MainTabView: View {
    private enum MainTab: Hashable { case today, plan, sports, records, profile }
    @State private var selectedTab: MainTab = ProcessInfo.processInfo.arguments.contains("-UITestProfile") ? .profile : .today

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { TodayView() }
                .tabItem { Label("今天", systemImage: "sparkles") }
                .tag(MainTab.today)

            NavigationStack { PlanView() }
                .tabItem { Label("计划", systemImage: "list.bullet.clipboard.fill") }
                .tag(MainTab.plan)

            NavigationStack { SportsHubView() }
                .tabItem { Label("运动", systemImage: "figure.run.circle.fill") }
                .tag(MainTab.sports)

            NavigationStack { TrainingHistoryView() }
                .tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }
                .tag(MainTab.records)

            NavigationStack { ProfileView() }
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
                .tag(MainTab.profile)
        }
        .tint(FitTheme.accent)
    }
}

private enum HistoryTypeFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case strength = "力量"
    case cardio = "有氧"
    case sport = "运动"
    var id: String { rawValue }
}

private enum HistoryDateFilter: String, CaseIterable, Identifiable {
    case all = "全部日期"
    case sevenDays = "近 7 天"
    case thirtyDays = "近 30 天"
    var id: String { rawValue }
    var days: Int? { self == .sevenDays ? 7 : self == .thirtyDays ? 30 : nil }
}

private enum UnifiedHistoryItem: Identifiable {
    case strength(WorkoutRecord)
    case cardio(CardioWorkoutRecord)
    case sport(SportSessionRecord)

    var id: String {
        switch self {
        case let .strength(record): "strength-\(record.id)"
        case let .cardio(record): "cardio-\(record.id)"
        case let .sport(record): "sport-\(record.id)"
        }
    }
    var date: Date {
        switch self {
        case let .strength(record): record.completedAt
        case let .cardio(record): record.date
        case let .sport(record): record.completedAt
        }
    }
}

struct TrainingHistoryView: View {
    @Environment(AppStore.self) private var store
    @State private var type: HistoryTypeFilter = .all
    @State private var date: HistoryDateFilter = .all
    @State private var query = ""

    var body: some View {
        List {
            Section {
                NavigationLink {
                    InsightsView()
                } label: {
                    Label("查看近 30 天力量、有氧与恢复趋势", systemImage: "chart.xyaxis.line")
                }
                Picker("类型", selection: $type) {
                    ForEach(HistoryTypeFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("日期", selection: $date) {
                    ForEach(HistoryDateFilter.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section("训练记录") {
                if filteredItems.isEmpty {
                    ContentUnavailableView("没有匹配记录", systemImage: "clock.badge.questionmark", description: Text("可搜索训练名称、动作或有氧方式。"))
                }
                ForEach(filteredItems) { item in
                    NavigationLink { destination(item) } label: { row(item) }
                }
            }
        }
        .navigationTitle("训练记录")
        .searchable(text: $query, prompt: "搜索动作或训练名称")
    }

    private var filteredItems: [UnifiedHistoryItem] {
        var items: [UnifiedHistoryItem] = []
        if type == .all || type == .strength { items += store.workoutHistory.map(UnifiedHistoryItem.strength) }
        if type == .all || type == .cardio { items += store.cardioWorkouts.map(UnifiedHistoryItem.cardio) }
        if type == .all || type == .sport { items += store.sportWorkouts.map(UnifiedHistoryItem.sport) }
        let cutoff = date.days.map { Calendar.current.date(byAdding: .day, value: -$0, to: .now) ?? .distantPast }
        return items.filter { item in
            guard cutoff.map({ item.date >= $0 }) ?? true else { return false }
            let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return true }
            switch item {
            case let .strength(record):
                return record.sessionName.localizedCaseInsensitiveContains(normalized)
                    || record.sets.contains { $0.exerciseName.localizedCaseInsensitiveContains(normalized) }
            case let .cardio(record):
                return record.modality.title.localizedCaseInsensitiveContains(normalized)
                    || record.intensity.title.localizedCaseInsensitiveContains(normalized)
            case let .sport(record):
                return record.kind.title.localizedCaseInsensitiveContains(normalized)
                    || record.environment.title.localizedCaseInsensitiveContains(normalized)
                    || record.intensity.title.localizedCaseInsensitiveContains(normalized)
            }
        }.sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private func row(_ item: UnifiedHistoryItem) -> some View {
        switch item {
        case let .strength(record):
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.sessionName)
                    Text("\(record.completedAt.formatted(date: .abbreviated, time: .shortened)) · \(record.sets.count) 组")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: "dumbbell.fill").foregroundStyle(FitTheme.accent) }
        case let .cardio(record):
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.modality.title)
                    Text("\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(record.durationMinutes) 分钟")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: record.modality.symbol).foregroundStyle(FitTheme.accentBlue) }
        case let .sport(record):
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.kind.title)
                    Text("\(record.completedAt.formatted(date: .abbreviated, time: .shortened)) · \(Int(record.analysis.effectiveDurationSeconds / 60)) 分钟")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: record.kind.symbol).foregroundStyle(FitTheme.accent) }
        }
    }

    @ViewBuilder
    private func destination(_ item: UnifiedHistoryItem) -> some View {
        switch item {
        case let .strength(record): StrengthHistoryDetailView(record: record, bodyWeightKg: store.latestWeight ?? 70)
        case let .cardio(record): CardioHistoryDetailView(record: record)
        case let .sport(record): SportHistoryDetailView(record: record)
        }
    }
}
