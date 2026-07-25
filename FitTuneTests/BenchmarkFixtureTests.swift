import XCTest
@testable import FitTune

final class BenchmarkFixtureTests: XCTestCase {
    func testEnergyBenchmark() throws {
        let fixture: EnergyFixture = try load("EnergyBenchmarks")
        let report = EnergyEngine.dailyReport(
            resting: metric(fixture.resting),
            strength: [metric(fixture.strength)],
            cardio: [metric(fixture.cardio)],
            steps: 8_000,
            stepEstimate: metric(fixture.walking),
            measuredDailyActive: metric(fixture.measuredActive)
        )
        XCTAssertEqual(fixture.algorithmVersion, EnergyEngine.algorithmVersion)
        XCTAssertEqual(report.total.value, fixture.expectedTotal, accuracy: fixture.tolerance)
    }

    func testInclineWalkingEnergyBenchmark() throws {
        let fixture: EnergyFixture = try load("EnergyBenchmarks")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let estimate = CardioEnergyEstimator.estimate(
            CardioEnergyInput(
                modality: .inclineWalking,
                intensity: .zone2,
                startedAt: start,
                completedAt: start.addingTimeInterval(fixture.inclineMinutes * 60),
                weightKg: fixture.inclineWeightKg,
                profile: nil,
                confirmedDistanceKm: nil,
                sensorDistanceKm: nil,
                workloadSegments: [
                    .init(
                        startedAt: start,
                        endedAt: start.addingTimeInterval(fixture.inclineMinutes * 60),
                        speedKph: fixture.inclineSpeedKph,
                        inclinePercent: fixture.inclinePercent,
                        source: .userEntered
                    )
                ],
                metricSamples: [],
                deviceEstimateKcal: nil,
                deviceEnergySource: nil,
                importedDeviceOnly: false
            )
        )

        XCTAssertEqual(estimate.kilocalories, fixture.expectedInclineActiveKcal, accuracy: fixture.inclineTolerance)
    }

    func testRestAndE1RMBenchmarks() throws {
        let restFixture: RestFixture = try load("RestRecommendationBenchmarks")
        let set = SetResult(exerciseID: UUID(), exerciseName: "深蹲", setNumber: 1, loadKg: restFixture.loadKg, reps: restFixture.reps, rir: restFixture.rir)
        let rest = TrainingEngine.recommendRest(current: set, previous: nil, setKind: .working, pattern: .squat, historicalE1RM: restFixture.historicalE1RM, readiness: .init(score: 80, level: .ready, summary: "", loadMultiplier: 1, setReduction: 0))
        XCTAssertEqual(rest.recommendedSeconds, restFixture.expectedSeconds)

        let e1rmFixture: E1RMFixture = try load("E1RMBenchmarks")
        XCTAssertEqual(TrainingEngine.estimatedOneRepMax(loadKg: e1rmFixture.loadKg, reps: e1rmFixture.reps, rir: e1rmFixture.rir) ?? 0, e1rmFixture.expectedKg, accuracy: e1rmFixture.tolerance)
    }

    func testRecoveryAndHealthDeduplicationBenchmarks() throws {
        let fixture: RecoveryFixture = try load("RecoveryBenchmarks")
        let checkIn = RecoveryCheckIn(date: .now, sleep: .init(manualValue: fixture.sleep, provenance: .manual), soreness: .init(manualValue: fixture.soreness, provenance: .manual), stress: .init(manualValue: fixture.stress, provenance: .manual), motivation: .init(manualValue: fixture.motivation, provenance: .manual))
        XCTAssertEqual(RecoveryEngine.assess(checkIn: checkIn, restingHeartRates: []).score, fixture.expectedScore)

        let dedup: DedupFixture = try load("HealthDeduplicationBenchmarks")
        let now = Date(timeIntervalSince1970: 2_000_000)
        let existing = RestingHeartRateSample(date: now, bpm: 60, source: .appleHealth, sourceName: "健康", externalID: dedup.existingExternalID)
        let duplicate = RestingHeartRateSample(date: now, bpm: 61, source: .appleHealth, sourceName: "健康", externalID: dedup.duplicateExternalID)
        let new = RestingHeartRateSample(date: now.addingTimeInterval(60), bpm: 62, source: .appleHealth, sourceName: "健康", externalID: dedup.newExternalID)
        XCTAssertEqual(HealthImportMerger.mergeRestingHeartRates(existing: [existing], incoming: [duplicate, new]).count, dedup.expectedCount)
    }

    private func load<T: Decodable>(_ name: String) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private func metric(_ value: Double) -> MetricRange {
        MetricRange(value: value, lowerBound: value * 0.9, upperBound: value * 1.1, provenance: .init(source: .appleHealth, sourceName: "fixture", confidence: .measured, coverage: 1))
    }
}

private struct EnergyFixture: Decodable {
    let algorithmVersion, basis: String
    let resting, strength, cardio, walking, measuredActive, expectedTotal, tolerance: Double
    let inclineWeightKg: Double
    let inclineMinutes: Double
    let inclineSpeedKph: Double
    let inclinePercent: Double
    let expectedInclineActiveKcal: Double
    let inclineTolerance: Double
}
private struct RestFixture: Decodable { let algorithmVersion, basis: String; let loadKg: Double; let reps, rir: Int; let historicalE1RM: Double; let expectedSeconds: Int; let tolerance: Double }
private struct E1RMFixture: Decodable { let algorithmVersion, basis: String; let loadKg: Double; let reps, rir: Int; let expectedKg, tolerance: Double }
private struct RecoveryFixture: Decodable { let algorithmVersion, basis: String; let sleep, soreness, stress, motivation: Double; let expectedScore: Int; let tolerance: Double }
private struct DedupFixture: Decodable { let algorithmVersion, basis, existingExternalID, duplicateExternalID, newExternalID: String; let expectedCount: Int; let tolerance: Double }
