import SwiftUI

@main
struct FitTuneApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppStore()
    @State private var healthKit = HealthKitService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(healthKit)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .inactive || phase == .background {
                        store.checkpointActiveWorkout()
                    }
                }
        }
    }
}
