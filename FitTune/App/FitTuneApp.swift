import SwiftUI

@main
struct FitTuneApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppStore()
    @State private var healthKit = HealthKitService()
    @State private var healthSync: HealthDataSyncCoordinator
    @State private var liveSensors: LiveSensorCoordinator

    init() {
        let watchBridge = WatchWorkoutBridge()
        _liveSensors = State(initialValue: LiveSensorCoordinator(watchSource: watchBridge))
        let healthService = HealthKitService()
        _healthKit = State(initialValue: healthService)
        _healthSync = State(initialValue: HealthDataSyncCoordinator(service: healthService))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(healthKit)
                .environment(healthSync)
                .environment(liveSensors)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .inactive || phase == .background {
                        store.checkpointActiveWorkout()
                        store.checkpointActiveCardio()
                    }
                    Task { await healthSync.handleScenePhase(phase) }
                }
                .onChange(of: healthSync.snapshot) { _, snapshot in
                    store.ingestDailyHealthSnapshot(snapshot)
                }
                .task {
                    await healthSync.requestAuthorizationAndStart()
                    store.ingestDailyHealthSnapshot(healthSync.snapshot)
                }
        }
    }
}
