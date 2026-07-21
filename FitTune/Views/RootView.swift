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
        .sheet(item: Binding(
            get: { store.presentedSummary },
            set: { store.presentedSummary = $0 }
        )) { summary in
            WorkoutSummaryView(presentation: summary)
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab = ProcessInfo.processInfo.arguments.contains("-UITestProfile") ? 3 : 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { TodayView() }
                .tabItem { Label("今天", systemImage: "sparkles") }
                .tag(0)

            NavigationStack { PlanView() }
                .tabItem { Label("计划", systemImage: "list.bullet.clipboard.fill") }
                .tag(1)

            NavigationStack { InsightsView() }
                .tabItem { Label("进展", systemImage: "chart.xyaxis.line") }
                .tag(2)

            NavigationStack { ProfileView() }
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
                .tag(3)
        }
        .tint(FitTheme.accent)
    }
}
