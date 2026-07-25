import XCTest
@testable import FitTune

final class StrengthEnergyEstimatorTests: XCTestCase {
    func testStructureUsesThreeCompendiumPriorsAndCompoundEvidence() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let sparse = record(
            start: start,
            minutes: 60,
            rpe: 5,
            sets: timedSets(count: 4, pattern: .arms, start: start, spacing: 600)
        )
        let moderate = record(
            start: start,
            minutes: 60,
            rpe: 7,
            sets: timedSets(count: 6, pattern: .arms, start: start, spacing: 300)
        )
        var denseSets = timedSets(count: 15, pattern: .squat, start: start, spacing: 180)
        denseSets[0].isCompound = true
        denseSets[0].movementPattern = .arms
        denseSets[1].isCompound = false
        denseSets[1].movementPattern = .squat
        denseSets.append(contentsOf: timedSets(count: 5, pattern: .squat, start: start, spacing: 30, kind: .warmup))
        var dense = record(start: start, minutes: 60, rpe: 8, sets: denseSets)
        dense.deviceActiveEnergyEstimateKcal = 5

        let sparseEstimate = StrengthEnergyEstimator.estimate(record: sparse, weightKg: 70, profile: nil)
        let moderateEstimate = StrengthEnergyEstimator.estimate(record: moderate, weightKg: 70, profile: nil)
        let denseEstimate = StrengthEnergyEstimator.estimate(record: dense, weightKg: 70, profile: nil)

        XCTAssertTrue(sparseEstimate.diagnostics?.primaryModel.contains("3.0 MET") == true)
        XCTAssertTrue(moderateEstimate.diagnostics?.primaryModel.contains("3.5 MET") == true)
        XCTAssertTrue(denseEstimate.diagnostics?.primaryModel.contains("6.0 MET") == true)
        XCTAssertGreaterThan(denseEstimate.kilocalories, sparseEstimate.kilocalories * 1.5)
        XCTAssertEqual(denseEstimate.diagnostics?.comparisonEstimateKcal, 5)
        XCTAssertTrue(denseEstimate.diagnostics?.inputsUsed.contains { $0.contains("正式组数量") } == true)
    }

    func testCompletedPausesAreExcludedFromEffectiveDuration() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let sets = timedSets(count: 6, pattern: .arms, start: start, spacing: 240)
        let uninterrupted = record(start: start, minutes: 40, rpe: 6, sets: sets)
        let paused = record(
            start: start,
            minutes: 60,
            rpe: 6,
            sets: sets,
            pauses: [WorkoutPauseInterval(
                startedAt: start.addingTimeInterval(1_800),
                endedAt: start.addingTimeInterval(3_000)
            )]
        )

        let uninterruptedEstimate = StrengthEnergyEstimator.estimate(record: uninterrupted, weightKg: 70, profile: nil)
        let pausedEstimate = StrengthEnergyEstimator.estimate(record: paused, weightKg: 70, profile: nil)

        XCTAssertEqual(pausedEstimate.kilocalories, uninterruptedEstimate.kilocalories, accuracy: 0.001)
    }

    func testMissingSessionRPEUsesStructuralModelAndWiderRange() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var sets = timedSets(count: 6, pattern: .arms, start: start, spacing: 300)
        sets.indices.forEach { sets[$0].feeling = .maximal }
        let estimate = StrengthEnergyEstimator.estimate(
            record: record(start: start, minutes: 60, rpe: nil, sets: sets),
            weightKg: 70,
            profile: nil
        )

        XCTAssertTrue(estimate.diagnostics?.primaryModel.contains("3.5 MET") == true)
        XCTAssertEqual(estimate.lowerBound, estimate.kilocalories * 0.65, accuracy: 0.001)
        XCTAssertEqual(estimate.upperBound, estimate.kilocalories * 1.35, accuracy: 0.001)
    }

    func testValidLowHeartRateCanOnlyMoveStructuralCenterWithinFifteenPercent() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let baseRecord = record(
            start: start,
            minutes: 60,
            rpe: 8,
            sets: timedSets(count: 15, pattern: .squat, start: start, spacing: 180)
        )
        let source = MetricProvenance(source: .bluetooth, sourceName: "H10", confidence: .measured, coverage: 1)
        var heartRateRecord = baseRecord
        heartRateRecord.metricSamples = stride(from: 0.0, through: 3_600.0, by: 5.0).map {
            WorkoutMetricSample(timestamp: start.addingTimeInterval($0), heartRateBPM: 70, provenance: source)
        }

        let structural = StrengthEnergyEstimator.estimate(record: baseRecord, weightKg: 70, profile: nil)
        let adjusted = StrengthEnergyEstimator.estimate(record: heartRateRecord, weightKg: 70, profile: completeProfile())

        XCTAssertGreaterThan(adjusted.kilocalories, 100)
        XCTAssertGreaterThanOrEqual(adjusted.kilocalories, structural.kilocalories * 0.85 - 0.001)
        XCTAssertLessThanOrEqual(adjusted.kilocalories, structural.kilocalories * 1.15 + 0.001)
        XCTAssertGreaterThanOrEqual(adjusted.kilocalories - adjusted.lowerBound, adjusted.kilocalories * 0.25 - 0.001)
    }

    func testShortHeartRatePeakDoesNotReplaceStructureAndEPOCIsNotAdded() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let baseRecord = record(
            start: start,
            minutes: 60,
            rpe: 8,
            sets: timedSets(count: 15, pattern: .squat, start: start, spacing: 180)
        )
        let source = MetricProvenance(source: .bluetooth, sourceName: "H10", confidence: .measured, coverage: 1)
        var peakRecord = baseRecord
        peakRecord.metricSamples = [
            WorkoutMetricSample(timestamp: start, heartRateBPM: 80, provenance: source),
            WorkoutMetricSample(timestamp: start.addingTimeInterval(5), heartRateBPM: 190, provenance: source)
        ]

        let structural = StrengthEnergyEstimator.estimate(record: baseRecord, weightKg: 70, profile: nil)
        let peaked = StrengthEnergyEstimator.estimate(record: peakRecord, weightKg: 70, profile: completeProfile())

        XCTAssertEqual(peaked.kilocalories, structural.kilocalories, accuracy: 0.001)
        XCTAssertTrue(peaked.diagnostics?.warnings.contains("EPOC 未计入本次主动热量") == true)
    }

    private func record(
        start: Date,
        minutes: Int,
        rpe: Double?,
        sets: [SetResult],
        pauses: [WorkoutPauseInterval] = []
    ) -> WorkoutRecord {
        WorkoutRecord(
            sessionName: "测试力量训练",
            startedAt: start,
            completedAt: start.addingTimeInterval(Double(minutes) * 60),
            readinessScore: 80,
            sets: sets,
            sessionRPE: rpe,
            pauseIntervals: pauses
        )
    }

    private func timedSets(
        count: Int,
        pattern: MovementPattern,
        start: Date,
        spacing: TimeInterval,
        kind: SetKind = .working
    ) -> [SetResult] {
        let exerciseID = UUID()
        return (0..<count).map { index in
            let setStart = start.addingTimeInterval(Double(index) * spacing)
            let setEnd = setStart.addingTimeInterval(30)
            return SetResult(
                exerciseID: exerciseID,
                exerciseName: pattern == .arms ? "弯举" : "杠铃深蹲",
                setNumber: index + 1,
                loadKg: pattern == .arms ? 12 : 100,
                reps: pattern == .arms ? 12 : 8,
                rir: pattern == .arms ? 3 : 1,
                completedAt: setEnd,
                movementPattern: pattern,
                techniqueQuality: 4,
                setKind: kind,
                startedAt: setStart
            )
        }
    }

    private func completeProfile() -> UserProfile {
        UserProfile(
            nickname: "测试",
            goal: .generalFitness,
            secondaryGoal: .none,
            experience: .intermediate,
            weeklyDays: 3,
            sessionMinutes: 60,
            equipment: .fullGym,
            bodyWeightKg: 70,
            loadIncrementKg: 2.5,
            ageYears: 30,
            heightCm: 175,
            biologicalSex: .male
        )
    }
}
