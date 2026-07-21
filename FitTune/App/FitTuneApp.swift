import SwiftUI

@main
struct FitTuneApp: App {
    @State private var store = AppStore()
    @State private var healthKit = HealthKitService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(healthKit)
                .preferredColorScheme(.dark)
        }
    }
}
