import Foundation

struct WorkoutActivitySnapshot: Codable, Hashable {
    var sessionID: UUID
    var startedAt: Date
    var title: String
    var currentItem: String
    var progress: String
    var heartRate: Int?
    var restEndsAt: Date?
    var isCardio: Bool = false
    var distanceMeters: Double? = nil
    var cadence: Double? = nil
    var symbol: String? = nil
    var elevationGainMeters: Double? = nil

    var nextSetURL: URL {
        URL(string: "fittune://workout?action=nextSet&session=\(sessionID.uuidString)")!
    }

    static func parseActionURL(_ url: URL) -> WorkoutActivityDeepLink? {
        guard url.scheme == "fittune", url.host == "workout",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let actionValue = components.queryItems?.first(where: { $0.name == "action" })?.value,
              let action = WorkoutActivityAction(rawValue: actionValue),
              let sessionValue = components.queryItems?.first(where: { $0.name == "session" })?.value,
              let sessionID = UUID(uuidString: sessionValue) else { return nil }
        return WorkoutActivityDeepLink(action: action, sessionID: sessionID)
    }

    static func strength(draft: WorkoutDraft, heartRate: Double?) -> WorkoutActivitySnapshot {
        let exercise = draft.currentExercise
        return WorkoutActivitySnapshot(
            sessionID: draft.id,
            startedAt: draft.startedAt,
            title: draft.session.name,
            currentItem: exercise.name,
            progress: "\(draft.currentSetKind.title) \(draft.currentPhaseOrdinal) / \(draft.currentPhaseTotal)",
            heartRate: heartRate.map { Int($0.rounded()) },
            restEndsAt: draft.restStartedAt.map { $0.addingTimeInterval(TimeInterval(draft.restRecommendation?.recommendedSeconds ?? draft.recommendation?.restSeconds ?? 0)) },
            isCardio: false
        )
    }

    static func cardio(draft: CardioSessionDraft, heartRate: Double?) -> WorkoutActivitySnapshot {
        let workload = draft.currentWorkload
        return WorkoutActivitySnapshot(
            sessionID: draft.id,
            startedAt: draft.startedAt,
            title: draft.modality.title,
            currentItem: cardioWorkloadText(workload),
            progress: draft.modality == .inclineWalking
                ? workload.map { "\(draft.intensity.title) · 扶把：\($0.handrailSupport.title)" } ?? draft.intensity.title
                : draft.intensity.title,
            heartRate: heartRate.map { Int($0.rounded()) },
            restEndsAt: nil,
            isCardio: true,
            distanceMeters: draft.distanceMeters > 0 ? draft.distanceMeters : nil,
            cadence: draft.metricSamples.compactMap(\.cadence).last
        )
    }

    static func sport(draft: SportSessionDraft, heartRate: Double?) -> WorkoutActivitySnapshot {
        let latestDistance = draft.metricSamples.compactMap(\.distanceMeters).max()
        let latestCadence = draft.metricSamples.compactMap(\.cadence).last
        let elevationGain = draft.metricSamples.compactMap(\.elevationGainMeters).max()
        return WorkoutActivitySnapshot(
            sessionID: draft.id,
            startedAt: draft.startedAt,
            title: draft.kind.title,
            currentItem: draft.pausedAt == nil ? "实时记录中" : "已暂停",
            progress: "\(draft.environment.title) · \(draft.intensity.title)",
            heartRate: heartRate.map { Int($0.rounded()) },
            restEndsAt: nil,
            isCardio: true,
            distanceMeters: latestDistance,
            cadence: latestCadence,
            symbol: draft.kind.symbol,
            elevationGainMeters: elevationGain
        )
    }

    private static func cardioWorkloadText(_ workload: CardioWorkloadSegment?) -> String {
        guard let workload else { return "有氧训练" }
        var values: [String] = []
        if let speed = workload.speedKph {
            values.append("\(speed.formatted(.number.precision(.fractionLength(1)))) km/h")
        }
        if workload.resolvedInclineInputMode == .machineLevel, let level = workload.inclineLevel {
            values.append("档位 \(Int(level.rounded()))")
        } else if let grade = workload.resolvedInclinePercent {
            values.append("\(grade.formatted(.number.precision(.fractionLength(1))))%")
        }
        if let power = workload.powerWatts {
            values.append("\(Int(power.rounded())) W")
        }
        return values.isEmpty ? "有氧训练" : values.joined(separator: " · ")
    }
}

struct LiveActivityUpdateGate: Equatable {
    let minimumInterval: TimeInterval
    private var lastSnapshot: WorkoutActivitySnapshot?
    private var lastUpdatedAt: Date?

    init(minimumInterval: TimeInterval = 1) {
        self.minimumInterval = minimumInterval
    }

    mutating func shouldUpdate(_ snapshot: WorkoutActivitySnapshot, at date: Date = .now) -> Bool {
        if lastSnapshot?.sessionID != snapshot.sessionID {
            lastSnapshot = snapshot
            lastUpdatedAt = date
            return true
        }
        guard lastSnapshot != snapshot else { return false }
        guard lastUpdatedAt.map({ date.timeIntervalSince($0) >= minimumInterval }) ?? true else { return false }
        lastSnapshot = snapshot
        lastUpdatedAt = date
        return true
    }
}

enum WorkoutActivityAction: String, Codable, Hashable {
    case nextSet
}

struct WorkoutActivityDeepLink: Codable, Hashable {
    var action: WorkoutActivityAction
    var sessionID: UUID
}
