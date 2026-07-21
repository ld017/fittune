import ActivityKit
import Foundation

@MainActor
final class WorkoutActivityController {
    static let shared = WorkoutActivityController()
    private var activity: Activity<FitTuneWorkoutAttributes>?

    func startOrUpdate(_ snapshot: WorkoutActivitySnapshot) {
        let state = contentState(snapshot)
        if let activity, activity.attributes.sessionID == snapshot.sessionID {
            Task { await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(90))) }
            return
        }
        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = FitTuneWorkoutAttributes(sessionID: snapshot.sessionID, title: snapshot.title, startedAt: snapshot.startedAt)
        activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(90)))
    }

    func end() {
        guard let activity else { return }
        let state = activity.content.state
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate) }
        self.activity = nil
    }

    private func contentState(_ snapshot: WorkoutActivitySnapshot) -> FitTuneWorkoutAttributes.ContentState {
        .init(currentItem: snapshot.currentItem, progress: snapshot.progress, heartRate: snapshot.heartRate, restEndsAt: snapshot.restEndsAt)
    }
}
