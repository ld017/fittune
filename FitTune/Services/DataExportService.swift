import Foundation

enum DataExportService {
    static let formatVersion = "1.0"

    static func json(snapshot: AppSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func restoreJSON(_ data: Data) throws -> AppSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppSnapshot.self, from: data)
    }

    static func workoutsCSV(workouts: [WorkoutRecord], cardio: [CardioWorkoutRecord]) -> String {
        var rows = [["type", "id", "date", "name", "status", "duration_min", "energy_kcal", "energy_method"]]
        rows += workouts.map {
            ["strength", $0.id.uuidString, iso($0.completedAt), $0.sessionName, $0.resolvedCompletionStatus.rawValue, decimal($0.completedAt.timeIntervalSince($0.startedAt) / 60), decimal($0.activeEnergyKcal), $0.energyMethod ?? ""]
        }
        rows += cardio.map {
            ["cardio", $0.id.uuidString, iso($0.date), $0.modality.title, ($0.completionStatus ?? .completed).rawValue, String($0.durationMinutes), decimal($0.activeEnergyKcal), $0.energyMethod ?? $0.source]
        }
        return csv(rows)
    }

    static func setsCSV(workouts: [WorkoutRecord]) -> String {
        var rows = [["workout_id", "completed_at", "exercise", "set_number", "set_kind", "load_kg", "reps", "rir", "technique_quality"]]
        for workout in workouts {
            rows += workout.sets.map {
                [workout.id.uuidString, iso($0.completedAt), $0.exerciseName, String($0.setNumber), $0.resolvedSetKind.rawValue, decimal($0.loadKg), String($0.reps), String($0.rir), $0.techniqueQuality.map(String.init) ?? ""]
            }
        }
        return csv(rows)
    }

    static func metricsCSV(workouts: [WorkoutRecord], cardio: [CardioWorkoutRecord]) -> String {
        var rows = [["workout_id", "timestamp", "heart_rate_bpm", "cadence", "steps", "distance_m", "active_energy_kcal", "source", "confidence", "coverage"]]
        func append(_ id: UUID, samples: [WorkoutMetricSample]) {
            rows += samples.map {
                [id.uuidString, iso($0.timestamp), decimal($0.heartRateBPM), decimal($0.cadence), $0.steps.map(String.init) ?? "", decimal($0.distanceMeters), decimal($0.activeEnergyKcal), $0.provenance.sourceName, $0.provenance.confidence.rawValue, decimal($0.provenance.coverage)]
            }
        }
        workouts.forEach { append($0.id, samples: $0.metricSamples ?? []) }
        cardio.forEach { append($0.id, samples: $0.metricSamples ?? []) }
        return csv(rows)
    }

    static func recoveryCSV(entries: [RecoveryCheckIn]) -> String {
        var rows = [["date", "sleep", "soreness", "stress", "motivation", "sleep_source", "stress_source"]]
        rows += entries.map {
            [iso($0.date), decimal($0.sleep.resolvedValue), decimal($0.soreness.resolvedValue), decimal($0.stress.resolvedValue), decimal($0.motivation.resolvedValue), $0.sleep.provenance.rawValue, $0.stress.provenance.rawValue]
        }
        return csv(rows)
    }

    private static func csv(_ rows: [[String]]) -> String { rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n" }
    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func decimal(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}
