import SwiftUI

@main
struct FitTuneWatchApp: App {
    @State private var workout = WatchWorkoutSessionManager()

    var body: some Scene {
        WindowGroup { WatchWorkoutView().environment(workout) }
    }
}
