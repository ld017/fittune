import Foundation

enum TrendDirection: String, Codable, Equatable {
    case improving
    case stable
    case declining
    case unavailable
}

struct MetricTrend: Equatable {
    var points: [(date: Date, value: Double)]
    var latestValue: Double?
    var relativeValue: Double?
    var sampleCount: Int
    var direction: TrendDirection
    var sourceDescription: String

    static func == (lhs: MetricTrend, rhs: MetricTrend) -> Bool {
        lhs.points.map(\.date) == rhs.points.map(\.date)
            && lhs.points.map(\.value) == rhs.points.map(\.value)
            && lhs.latestValue == rhs.latestValue
            && lhs.relativeValue == rhs.relativeValue
            && lhs.sampleCount == rhs.sampleCount
            && lhs.direction == rhs.direction
            && lhs.sourceDescription == rhs.sourceDescription
    }
}

struct DeloadSuggestion: Equatable {
    var reason: String
    var isAdvisoryOnly: Bool = true
}

enum TrendEngine {
    static let algorithmVersion = "1.0-trend-1"

    static func strength(records: [WorkoutRecord], bodyWeightKg: Double?, now: Date = .now) -> MetricTrend {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86_400)
        let recent = records.filter { $0.completedAt >= cutoff && $0.completedAt <= now }.sorted { $0.completedAt < $1.completedAt }
        let exercise = Dictionary(grouping: recent.flatMap(\.sets).filter { $0.resolvedSetKind == .working }, by: \.exerciseName)
            .max { $0.value.count < $1.value.count }?.key
        let points: [(Date, Double)] = recent.compactMap { record in
            let candidates = record.sets.filter { $0.resolvedSetKind == .working && (exercise == nil || $0.exerciseName == exercise) }
                .compactMap { TrainingEngine.estimatedOneRepMax(loadKg: $0.loadKg, reps: $0.reps, rir: $0.rir) }
            return candidates.max().map { (record.completedAt, $0) }
        }
        let latest = points.last?.1
        return MetricTrend(
            points: points,
            latestValue: latest,
            relativeValue: bodyWeightKg.flatMap { weight in guard weight > 0, let latest else { return nil }; return latest / weight },
            sampleCount: points.count,
            direction: direction(points.map { $0.1 }),
            sourceDescription: exercise.map { "近 30 天正式组 · \($0) · \(algorithmVersion)" } ?? "近 30 天正式组 · 数据不足"
        )
    }

    static func cardio(records: [CardioWorkoutRecord], now: Date = .now) -> MetricTrend {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86_400)
        let points = records.filter { $0.date >= cutoff && $0.date <= now }
            .compactMap { record -> (Date, Double)? in
                guard let distance = record.distanceKm, distance > 0, record.durationMinutes > 0 else { return nil }
                return (record.date, Double(record.durationMinutes) * 60 / distance)
            }.sorted { $0.0 < $1.0 }
        let rawDirection = direction(points.map { $0.1 })
        let reversed: TrendDirection = rawDirection == .improving ? .declining : (rawDirection == .declining ? .improving : rawDirection)
        return MetricTrend(points: points, latestValue: points.last?.1, relativeValue: nil, sampleCount: points.count, direction: reversed, sourceDescription: "近 30 天可验证距离与时长 · 配速")
    }

    static func recovery(entries: [RecoveryEntry], now: Date = .now) -> MetricTrend {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86_400)
        let points = entries.filter { $0.date >= cutoff && $0.date <= now }.sorted { $0.date < $1.date }.map { ($0.date, Double($0.readinessScore)) }
        return MetricTrend(points: points, latestValue: points.last?.1, relativeValue: nil, sampleCount: points.count, direction: direction(points.map { $0.1 }), sourceDescription: "近 30 天主观恢复量表")
    }

    static func deloadSuggestion(workouts: [WorkoutRecord], recovery: [RecoveryEntry], now: Date = .now) -> DeloadSuggestion? {
        let strengthTrend = strength(records: workouts, bodyWeightKg: nil, now: now)
        let recentRecovery = recovery.sorted { $0.date > $1.date }.prefix(3)
        guard strengthTrend.direction == .declining,
              recentRecovery.count == 3,
              recentRecovery.allSatisfy({ $0.readinessScore < 60 }) else { return nil }
        return DeloadSuggestion(reason: "最近多次力量表现下降且恢复评分持续偏低，可考虑减量 5–7 天；是否采用由你决定。")
    }

    private static func direction(_ values: [Double]) -> TrendDirection {
        guard values.count >= 2, let first = values.first, let last = values.last, first != 0 else { return .unavailable }
        let change = (last - first) / abs(first)
        if change > 0.02 { return .improving }
        if change < -0.02 { return .declining }
        return .stable
    }
}
