import ActivityKit
import Foundation

@MainActor
final class WorkoutActivityController {
    static let shared = WorkoutActivityController()
    private var updateGate = LiveActivityUpdateGate(minimumInterval: 1)

    func startOrUpdate(_ snapshot: WorkoutActivitySnapshot) {
        guard updateGate.shouldUpdate(snapshot) else { return }
        let state = contentState(snapshot)
        if let activity = Activity<FitTuneWorkoutAttributes>.activities.first(where: { $0.attributes.sessionID == snapshot.sessionID }) {
            Task { await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(90))) }
            return
        }
        end(excluding: snapshot.sessionID)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = FitTuneWorkoutAttributes(sessionID: snapshot.sessionID, title: snapshot.title, startedAt: snapshot.startedAt)
        _ = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(90)))
    }

    func end() {
        end(excluding: nil)
        updateGate = LiveActivityUpdateGate(minimumInterval: 1)
    }

    func reconcile(validSessionIDs: Set<UUID>) {
        for activity in Activity<FitTuneWorkoutAttributes>.activities where !validSessionIDs.contains(activity.attributes.sessionID) {
            end(activity)
        }
    }

    private func end(excluding sessionID: UUID?) {
        for activity in Activity<FitTuneWorkoutAttributes>.activities where activity.attributes.sessionID != sessionID {
            end(activity)
        }
    }

    private func end(_ activity: Activity<FitTuneWorkoutAttributes>) {
        let state = activity.content.state
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate) }
    }

    private func contentState(_ snapshot: WorkoutActivitySnapshot) -> FitTuneWorkoutAttributes.ContentState {
        .init(
            currentItem: snapshot.currentItem,
            progress: snapshot.progress,
            heartRate: snapshot.heartRate,
            restEndsAt: snapshot.restEndsAt,
            isCardio: snapshot.isCardio,
            distanceMeters: snapshot.distanceMeters,
            cadence: snapshot.cadence,
            symbol: snapshot.symbol,
            elevationGainMeters: snapshot.elevationGainMeters
        )
    }
}
