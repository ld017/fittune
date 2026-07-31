import Foundation

enum HeartRateAnalysisEngine {
    static func drift(
        samples: [WorkoutMetricSample],
        workloads: [CardioWorkloadSegment],
        startedAt: Date,
        completedAt: Date
    ) -> HeartRateDriftResult? {
        let duration = completedAt.timeIntervalSince(startedAt)
        guard duration >= 20 * 60 else { return nil }

        let workloadCoverage = workloadCoverage(
            workloads,
            startedAt: startedAt,
            completedAt: completedAt
        )
        guard workloadCoverage >= 0.8 else { return nil }

        let midpoint = startedAt.addingTimeInterval(duration / 2)
        guard workloadIsStable(workloads, metric: \.speedKph, startedAt: startedAt, midpoint: midpoint, completedAt: completedAt),
              workloadIsStable(workloads, metric: \.inclinePercent, startedAt: startedAt, midpoint: midpoint, completedAt: completedAt),
              workloadIsStable(workloads, metric: \.powerWatts, startedAt: startedAt, midpoint: midpoint, completedAt: completedAt) else {
            return nil
        }

        let intervals = dominantHeartRateIntervals(
            samples: samples,
            startedAt: startedAt,
            completedAt: completedAt
        )
        let heartRateCoverage = intervals.reduce(0.0) { $0 + $1.duration } / duration
        guard heartRateCoverage >= 0.6,
              let firstHalf = weightedHeartRate(intervals, startedAt: startedAt, completedAt: midpoint),
              let secondHalf = weightedHeartRate(intervals, startedAt: midpoint, completedAt: completedAt),
              firstHalf > 0 else { return nil }

        return HeartRateDriftResult(
            percent: (secondHalf - firstHalf) / firstHalf * 100,
            confidence: .derived,
            workloadCoverage: min(1, workloadCoverage),
            heartRateCoverage: min(1, heartRateCoverage)
        )
    }

    static func setResponse(
        samples: [WorkoutMetricSample],
        setStartedAt: Date,
        setCompletedAt: Date,
        nextSetStartedAt: Date?
    ) -> SetHeartRateResponse? {
        let delayedPeakWindowEnd = setCompletedAt.addingTimeInterval(45)
        let peakWindowEnd = min(delayedPeakWindowEnd, nextSetStartedAt ?? delayedPeakWindowEnd)
        let peaks = validHeartRateSamples(samples).filter {
            $0.timestamp >= setStartedAt && $0.timestamp <= peakWindowEnd
        }
        guard let peak = peaks.max(by: { $0.bpm < $1.bpm }) else { return nil }

        let recoveryWindow = validHeartRateSamples(samples).filter { sample in
            sample.timestamp > peak.timestamp
                && sample.timestamp <= peak.timestamp.addingTimeInterval(125)
                && (nextSetStartedAt.map { sample.timestamp < $0 } ?? true)
        }
        let sourceSwitched = recoveryWindow.contains { $0.sourceName != peak.sourceName }
        let recovery = sourceSwitched ? [] : recoveryWindow
        let hrr60 = medianHeartRate(in: recovery, from: peak.timestamp.addingTimeInterval(55), through: peak.timestamp.addingTimeInterval(65))
            .map { peak.bpm - $0 }
        let hrr120 = medianHeartRate(in: recovery, from: peak.timestamp.addingTimeInterval(115), through: peak.timestamp.addingTimeInterval(125))
            .map { peak.bpm - $0 }

        return SetHeartRateResponse(
            peakBPM: peak.bpm,
            peakDelaySeconds: Int(peak.timestamp.timeIntervalSince(setCompletedAt).rounded()),
            hrr60: hrr60,
            hrr120: hrr120,
            sourceName: peak.sourceName,
            confidence: peak.confidence
        )
    }

    static func intensitySummary(
        samples: [WorkoutMetricSample],
        startedAt: Date,
        completedAt: Date,
        restingHeartRate: Double?,
        maximumHeartRate: Double?
    ) -> HeartRateIntensitySummary? {
        let duration = completedAt.timeIntervalSince(startedAt)
        guard duration > 0 else { return nil }

        let intervals = dominantHeartRateIntervals(
            samples: samples,
            startedAt: startedAt,
            completedAt: completedAt
        )
        guard !intervals.isEmpty else { return nil }

        let usesReserve = validHeartRateReserve(restingHeartRate: restingHeartRate, maximumHeartRate: maximumHeartRate)
        guard let maximumHeartRate, maximumHeartRate > 0 else { return nil }

        var secondsByZone = Dictionary(uniqueKeysWithValues: HeartRateIntensityZone.allCases.map { ($0, 0.0) })
        var fatOxidationOpportunitySeconds = 0.0
        for interval in intervals {
            let percent: Double
            if usesReserve, let restingHeartRate {
                percent = (interval.bpm - restingHeartRate) / (maximumHeartRate - restingHeartRate) * 100
            } else {
                percent = interval.bpm / maximumHeartRate * 100
            }
            secondsByZone[zone(for: percent, usesHeartRateReserve: usesReserve), default: 0] += interval.duration
            if usesReserve, (40...65).contains(percent) {
                fatOxidationOpportunitySeconds += interval.duration
            }
        }

        let multiplier: [HeartRateIntensityZone: Double] = [
            .veryLight: 1,
            .light: 2,
            .moderate: 3,
            .vigorous: 4,
            .nearMaximum: 5
        ]
        let zoneLoad = secondsByZone.reduce(0.0) { result, item in
            result + item.value / 60 * (multiplier[item.key] ?? 0)
        }
        let aerobicBase = (secondsByZone[.moderate] ?? 0) / 60
        let vigorous = ((secondsByZone[.vigorous] ?? 0) + (secondsByZone[.nearMaximum] ?? 0)) / 60
        let fatOxidation = fatOxidationOpportunitySeconds / 60
        let coverage = intervals.reduce(0.0) { $0 + $1.duration } / duration

        return HeartRateIntensitySummary(
            secondsByZone: secondsByZone,
            zoneLoadAU: zoneLoad,
            aerobicBaseMinutes: aerobicBase,
            vigorousMinutes: vigorous,
            fatOxidationOpportunityMinutes: fatOxidation,
            coverage: min(1, coverage),
            usedHeartRateReserve: usesReserve,
            confidence: !usesReserve || intervals.contains { $0.confidence == .estimated }
                ? .estimated
                : .derived
        )
    }

    private static func validHeartRateReserve(restingHeartRate: Double?, maximumHeartRate: Double?) -> Bool {
        guard let restingHeartRate, let maximumHeartRate else { return false }
        return restingHeartRate > 0 && restingHeartRate < maximumHeartRate
    }

    private static func zone(
        for percent: Double,
        usesHeartRateReserve: Bool
    ) -> HeartRateIntensityZone {
        if usesHeartRateReserve {
            return switch percent {
            case ..<30: .veryLight
            case ..<40: .light
            case ..<60: .moderate
            case ..<90: .vigorous
            default: .nearMaximum
            }
        }

        // ACSM %HRmax bands are distinct from heart-rate-reserve bands.
        return switch percent {
        case ..<57: .veryLight
        case ..<64: .light
        case ..<77: .moderate
        case ..<96: .vigorous
        default: .nearMaximum
        }
    }

    private static func dominantHeartRateIntervals(
        samples: [WorkoutMetricSample],
        startedAt: Date,
        completedAt: Date
    ) -> [HeartRateInterval] {
        let intervals = validHeartRateIntervals(
            samples: samples,
            startedAt: startedAt,
            completedAt: completedAt
        )
        guard let source = Dictionary(grouping: intervals, by: \.sourceName)
            .max(by: { left, right in
                let leftDuration = left.value.reduce(0.0) { $0 + $1.duration }
                let rightDuration = right.value.reduce(0.0) { $0 + $1.duration }
                return leftDuration < rightDuration
            })?
            .key else { return [] }
        return intervals.filter { $0.sourceName == source }
    }

    private static func validHeartRateIntervals(
        samples: [WorkoutMetricSample],
        startedAt: Date,
        completedAt: Date
    ) -> [HeartRateInterval] {
        let valid = samples.compactMap { sample -> (timestamp: Date, bpm: Double, sourceName: String, confidence: DataConfidence)? in
            guard let bpm = sample.heartRateBPM,
                  (40...220).contains(bpm),
                  sample.timestamp >= startedAt,
                  sample.timestamp <= completedAt else { return nil }
            return (sample.timestamp, bpm, sample.provenance.sourceName, sample.provenance.confidence)
        }

        return Dictionary(grouping: valid, by: \.sourceName).values.flatMap { sourceSamples in
            let sorted = sourceSamples.sorted { $0.timestamp < $1.timestamp }
            return zip(sorted, sorted.dropFirst()).compactMap { pair -> HeartRateInterval? in
                let (left, right) = pair
                let seconds = right.timestamp.timeIntervalSince(left.timestamp)
                guard seconds > 0, seconds <= 15 else { return nil }
                return HeartRateInterval(
                    start: left.timestamp,
                    end: right.timestamp,
                    bpm: (left.bpm + right.bpm) / 2,
                    sourceName: left.sourceName,
                    confidence: left.confidence
                )
            }
        }
    }

    private static func validHeartRateSamples(_ samples: [WorkoutMetricSample]) -> [HeartRateSample] {
        samples.compactMap { sample in
            guard let bpm = sample.heartRateBPM, (40...220).contains(bpm) else { return nil }
            return HeartRateSample(
                timestamp: sample.timestamp,
                bpm: bpm,
                sourceName: sample.provenance.sourceName,
                confidence: sample.provenance.confidence
            )
        }
    }

    private static func medianHeartRate(in samples: [HeartRateSample], from start: Date, through end: Date) -> Double? {
        let values = samples
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .map(\.bpm)
            .sorted()
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2)
            ? (values[middle - 1] + values[middle]) / 2
            : values[middle]
    }

    private static func weightedHeartRate(
        _ intervals: [HeartRateInterval],
        startedAt: Date,
        completedAt: Date
    ) -> Double? {
        let contributions = intervals.compactMap { interval -> (duration: TimeInterval, bpm: Double)? in
            let start = max(interval.start, startedAt)
            let end = min(interval.end, completedAt)
            let duration = end.timeIntervalSince(start)
            return duration > 0 ? (duration, interval.bpm) : nil
        }
        let duration = contributions.reduce(0.0) { $0 + $1.duration }
        guard duration > 0 else { return nil }
        return contributions.reduce(0.0) { $0 + $1.duration * $1.bpm } / duration
    }

    private static func workloadCoverage(
        _ workloads: [CardioWorkloadSegment],
        startedAt: Date,
        completedAt: Date
    ) -> Double {
        let intervals = workloads.compactMap { workload -> (start: Date, end: Date)? in
            let start = max(workload.startedAt, startedAt)
            let end = min(workload.endedAt ?? completedAt, completedAt)
            return end > start ? (start, end) : nil
        }
        .sorted { $0.start < $1.start }

        var covered: TimeInterval = 0
        var current: (start: Date, end: Date)?
        for interval in intervals {
            guard let existing = current else {
                current = interval
                continue
            }
            if interval.start <= existing.end {
                current = (existing.start, max(existing.end, interval.end))
            } else {
                covered += existing.end.timeIntervalSince(existing.start)
                current = interval
            }
        }
        if let current { covered += current.end.timeIntervalSince(current.start) }
        return covered / completedAt.timeIntervalSince(startedAt)
    }

    private static func workloadIsStable(
        _ workloads: [CardioWorkloadSegment],
        metric: KeyPath<CardioWorkloadSegment, Double?>,
        startedAt: Date,
        midpoint: Date,
        completedAt: Date
    ) -> Bool {
        let firstHalf = weightedWorkloadValue(workloads, metric: metric, startedAt: startedAt, completedAt: midpoint)
        let secondHalf = weightedWorkloadValue(workloads, metric: metric, startedAt: midpoint, completedAt: completedAt)
        switch (firstHalf, secondHalf) {
        case (nil, nil): return true
        case let (.some(first), .some(second)) where first == 0:
            return abs(second) < 0.000_001
        case let (.some(first), .some(second)):
            return abs(second - first) / abs(first) <= 0.05
        default:
            return false
        }
    }

    private static func weightedWorkloadValue(
        _ workloads: [CardioWorkloadSegment],
        metric: KeyPath<CardioWorkloadSegment, Double?>,
        startedAt: Date,
        completedAt: Date
    ) -> Double? {
        let contributions = workloads.compactMap { workload -> (duration: TimeInterval, value: Double)? in
            guard let value = workload[keyPath: metric] else { return nil }
            let start = max(workload.startedAt, startedAt)
            let end = min(workload.endedAt ?? completedAt, completedAt)
            let duration = end.timeIntervalSince(start)
            return duration > 0 ? (duration, value) : nil
        }
        let duration = contributions.reduce(0.0) { $0 + $1.duration }
        guard duration > 0 else { return nil }
        return contributions.reduce(0.0) { $0 + $1.duration * $1.value } / duration
    }
}

private struct HeartRateInterval {
    let start: Date
    let end: Date
    let bpm: Double
    let sourceName: String
    let confidence: DataConfidence

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

private struct HeartRateSample {
    let timestamp: Date
    let bpm: Double
    let sourceName: String
    let confidence: DataConfidence
}
