import ActivityKit
import Foundation

struct FitTuneWorkoutAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var currentItem: String
        var progress: String
        var heartRate: Int?
        var restEndsAt: Date?
        var isCardio: Bool
        var distanceMeters: Double?
        var cadence: Double?
    }

    var sessionID: UUID
    var title: String
    var startedAt: Date
}
