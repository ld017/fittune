import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FitTuneWorkoutAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.currentItem).font(.headline).lineLimit(1)
                    if let end = context.state.restEndsAt, end > .now {
                        Text(timerInterval: Date.now...end, countsDown: true)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    } else {
                        Text(context.state.progress).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let bpm = context.state.heartRate { Label("\(bpm)", systemImage: "heart.fill").foregroundStyle(.red).font(.headline.monospacedDigit()) }
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.88))
            .widgetURL(URL(string: "fittune://workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label(context.attributes.title, systemImage: "figure.strengthtraining.traditional") }
                DynamicIslandExpandedRegion(.trailing) { if let bpm = context.state.heartRate { Text("♥︎ \(bpm)").foregroundStyle(.red) } }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.currentItem)
                        Spacer()
                        if let end = context.state.restEndsAt, end > .now {
                            Text(timerInterval: Date.now...end, countsDown: true).monospacedDigit().foregroundStyle(.green)
                        } else {
                            Text(context.state.progress).foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: { Image(systemName: "figure.strengthtraining.traditional") }
              compactTrailing: { Text(context.state.heartRate.map { "♥︎\($0)" } ?? context.state.progress).font(.caption2) }
              minimal: { Image(systemName: "figure.strengthtraining.traditional") }
        }
    }
}
