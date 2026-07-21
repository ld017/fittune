import SwiftUI

struct WatchWorkoutView: View {
    @Environment(WatchWorkoutSessionManager.self) private var workout

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: workout.isRunning ? "heart.fill" : "applewatch")
                    .font(.title).foregroundStyle(.red)
                Text(workout.heartRate.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                Text("bpm").font(.caption).foregroundStyle(.secondary)
                Text(workout.status).font(.caption).multilineTextAlignment(.center)
                if workout.isRunning {
                    Button(workout.isPaused ? "继续" : "暂停") {
                        workout.isPaused ? workout.resume() : workout.pause()
                    }
                    Button("结束", role: .destructive) { workout.end() }
                } else {
                    Text("请从 iPhone FitTune 开始训练")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 6)
        }
    }
}
