import SwiftUI

@main
struct FitTuneApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppStore()
    @State private var healthKit = HealthKitService()
    @State private var liveSensors: LiveSensorCoordinator

    init() {
        let watchBridge = WatchWorkoutBridge()
        _liveSensors = State(initialValue: LiveSensorCoordinator(watchSource: watchBridge))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(healthKit)
                .environment(liveSensors)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .inactive || phase == .background {
                        store.checkpointActiveWorkout()
                        store.checkpointActiveCardio()
                    }
                }
        }
    }
}
