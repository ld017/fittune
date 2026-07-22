import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FitTuneWorkoutAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.isCardio ? "figure.run" : "figure.strengthtraining.traditional").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.currentItem).font(.headline).lineLimit(1)
                    if context.state.isCardio {
                        Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    } else if let end = context.state.restEndsAt, end > .now {
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
                DynamicIslandExpandedRegion(.leading) { Label(context.attributes.title, systemImage: context.state.isCardio ? "figure.run" : "figure.strengthtraining.traditional") }
                DynamicIslandExpandedRegion(.trailing) { if let bpm = context.state.heartRate { Text("♥︎ \(bpm)").foregroundStyle(.red) } }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack {
                            if context.state.isCardio {
                                Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                                    .monospacedDigit().foregroundStyle(.green)
                            } else {
                                Text(context.state.currentItem)
                            }
                            Spacer()
                            if let distance = context.state.distanceMeters {
                                Text(String(format: "%.2f km", distance / 1000)).foregroundStyle(.secondary)
                            } else if let cadence = context.state.cadence {
                                Text("\(Int(cadence.rounded())) spm").foregroundStyle(.secondary)
                            } else {
                                Text(context.state.progress).foregroundStyle(.secondary)
                            }
                        }
                        if !context.state.isCardio, let end = context.state.restEndsAt, end > .now {
                            HStack {
                                Text(timerInterval: Date.now...end, countsDown: true).monospacedDigit().foregroundStyle(.green)
                                Spacer()
                                Link(destination: URL(string: "fittune://workout?action=nextSet&session=\(context.attributes.sessionID.uuidString)")!) {
                                    Label("开始下一组", systemImage: "play.fill")
                                        .font(.caption.bold())
                                }
                            }
                        }
                    }
                }
            } compactLeading: { Image(systemName: context.state.isCardio ? "figure.run" : "figure.strengthtraining.traditional") }
              compactTrailing: {
                  if context.state.isCardio {
                      Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false).font(.caption2.monospacedDigit())
                  } else if let end = context.state.restEndsAt, end > .now {
                      Text(timerInterval: Date.now...end, countsDown: true).font(.caption2.monospacedDigit()).foregroundStyle(.green)
                  } else {
                      Text(context.state.heartRate.map { "♥︎\($0)" } ?? context.state.progress).font(.caption2)
                  }
              }
              minimal: { Image(systemName: context.state.isCardio ? "figure.run" : "figure.strengthtraining.traditional") }
        }
    }
}
