import Foundation

enum DataExportService {
    static let formatVersion = "2.0"

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
        var rows = [[
            "type", "id", "date", "name", "status", "duration_min", "energy_kcal", "energy_method",
            "energy_primary_model", "energy_inputs_used", "energy_warnings", "energy_data_coverage",
            "device_energy_comparison_kcal", "device_energy_source", "workload_segments"
        ]]
        rows += workouts.map {
            workoutRow(
                type: "strength",
                id: $0.id,
                date: $0.completedAt,
                name: $0.sessionName,
                status: $0.resolvedCompletionStatus,
                durationMinutes: $0.completedAt.timeIntervalSince($0.startedAt) / 60,
                energyKcal: $0.activeEnergyKcal,
                energyMethod: $0.energyMethod,
                diagnostics: $0.energyDiagnostics,
                deviceEstimateKcal: $0.deviceActiveEnergyEstimateKcal,
                deviceSource: $0.deviceEnergySource,
                workloadSegments: nil
            )
        }
        rows += cardio.map {
            workoutRow(
                type: "cardio",
                id: $0.id,
                date: $0.date,
                name: $0.modality.title,
                status: $0.completionStatus ?? .completed,
                durationMinutes: Double($0.durationMinutes),
                energyKcal: $0.activeEnergyKcal,
                energyMethod: $0.energyMethod ?? $0.source,
                diagnostics: $0.energyDiagnostics,
                deviceEstimateKcal: $0.deviceActiveEnergyEstimateKcal,
                deviceSource: $0.deviceEnergySource,
                workloadSegments: $0.workloadSegments
            )
        }
        return csv(rows)
    }

    static func setsCSV(workouts: [WorkoutRecord]) -> String {
        var rows = [[
            "workout_id", "started_at", "completed_at", "exercise", "set_number", "set_kind", "load_kg", "reps", "rir", "technique_quality",
            "actual_rest_seconds", "peak_bpm", "peak_delay_seconds", "hrr60", "hrr120"
        ]]
        for workout in workouts {
            rows += workout.sets.map {
                [
                    workout.id.uuidString,
                    $0.startedAt.map(iso) ?? "",
                    iso($0.completedAt),
                    $0.exerciseName,
                    String($0.setNumber),
                    $0.resolvedSetKind.rawValue,
                    decimal($0.loadKg),
                    String($0.reps),
                    String($0.rir),
                    $0.techniqueQuality.map(String.init) ?? "",
                    decimal($0.actualRestSeconds),
                    decimal($0.heartRateResponse?.peakBPM),
                    $0.heartRateResponse.map { String($0.peakDelaySeconds) } ?? "",
                    decimal($0.heartRateResponse?.hrr60),
                    decimal($0.heartRateResponse?.hrr120)
                ]
            }
        }
        return csv(rows)
    }

    static func metricsCSV(workouts: [WorkoutRecord], cardio: [CardioWorkoutRecord], sports: [SportSessionRecord] = []) -> String {
        var rows = [["workout_id", "timestamp", "heart_rate_bpm", "cadence", "steps", "distance_m", "elevation_gain_m", "altitude_m", "speed_mps", "active_energy_kcal", "source", "confidence", "coverage"]]
        func append(_ id: UUID, samples: [WorkoutMetricSample]) {
            rows += samples.map {
                [id.uuidString, iso($0.timestamp), decimal($0.heartRateBPM), decimal($0.cadence), $0.steps.map(String.init) ?? "", decimal($0.distanceMeters), decimal($0.elevationGainMeters), decimal($0.altitudeMeters), decimal($0.speedMetersPerSecond), decimal($0.activeEnergyKcal), $0.provenance.sourceName, $0.provenance.confidence.rawValue, decimal($0.provenance.coverage)]
            }
        }
        workouts.forEach { append($0.id, samples: $0.metricSamples ?? []) }
        cardio.forEach { append($0.id, samples: $0.metricSamples ?? []) }
        sports.forEach { append($0.id, samples: $0.metricSamples) }
        return csv(rows)
    }

    static func sportsCSV(sports: [SportSessionRecord]) -> String {
        var rows = [[
            "id", "kind", "environment", "intensity", "started_at", "completed_at", "status",
            "effective_duration_min", "session_rpe", "training_load_au", "energy_kcal", "energy_lower_kcal",
            "energy_upper_kcal", "energy_source", "confidence", "coverage", "average_hr", "maximum_hr",
            "distance_m", "steps", "cadence", "elevation_gain_m", "recovery_hours", "algorithm_version", "warnings"
        ]]
        rows += sports.map { record in
            let analysis = record.analysis
            return [
                record.id.uuidString, record.kind.rawValue, record.environment.rawValue, record.intensity.rawValue,
                iso(record.startedAt), iso(record.completedAt), record.completionStatus.rawValue,
                decimal(analysis.effectiveDurationSeconds / 60), decimal(record.sessionRPE), decimal(analysis.sessionRPELoadAU),
                decimal(analysis.activeEnergyKcal.value), decimal(analysis.activeEnergyKcal.lowerBound), decimal(analysis.activeEnergyKcal.upperBound),
                analysis.activeEnergyKcal.provenance.sourceName, analysis.activeEnergyKcal.provenance.confidence.rawValue,
                decimal(analysis.dataCoverage), decimal(analysis.averageHeartRate), decimal(analysis.maximumHeartRate),
                decimal(analysis.distanceMeters), analysis.steps.map(String.init) ?? "", decimal(analysis.averageCadence),
                decimal(analysis.elevationGainMeters), decimal(analysis.estimatedRecoveryHours.value), analysis.algorithmVersion,
                encoded(analysis.warnings)
            ]
        }
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
    private static func workoutRow(
        type: String,
        id: UUID,
        date: Date,
        name: String,
        status: WorkoutCompletionStatus,
        durationMinutes: Double,
        energyKcal: Double?,
        energyMethod: String?,
        diagnostics: EnergyEstimateDiagnostics?,
        deviceEstimateKcal: Double?,
        deviceSource: MetricSource?,
        workloadSegments: [CardioWorkloadSegment]?
    ) -> [String] {
        [
            type,
            id.uuidString,
            iso(date),
            name,
            status.rawValue,
            decimal(durationMinutes),
            decimal(energyKcal),
            energyMethod ?? "",
            diagnostics?.primaryModel ?? "",
            encoded(diagnostics?.inputsUsed),
            encoded(diagnostics?.warnings),
            decimal(diagnostics?.dataCoverage),
            decimal(diagnostics?.comparisonEstimateKcal ?? deviceEstimateKcal),
            deviceSource?.rawValue ?? "",
            encoded(workloadSegments)
        ]
    }
    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func encoded<T: Encodable>(_ value: T?) -> String {
        guard let value else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return String(data: (try? encoder.encode(value)) ?? Data(), encoding: .utf8) ?? ""
    }
    private static func decimal(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}
