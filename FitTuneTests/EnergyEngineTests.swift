import XCTest
@testable import FitTune

final class EnergyEngineTests: XCTestCase {
    func testMeasuredDailyActiveEnergyPreventsWorkoutAndStepDoubleCounting() {
        let report = EnergyEngine.dailyReport(
            resting: estimate(1_700, source: "Cunningham"),
            strength: [estimate(200, source: "心率")],
            cardio: [estimate(150, source: "速度坡度")],
            steps: 8_000,
            stepEstimate: estimate(100, source: "步数估算"),
            measuredDailyActive: estimate(600, source: "Apple 健康")
        )

        XCTAssertEqual(report.active.value, 600, accuracy: 0.001)
        XCTAssertEqual(report.otherActive.value, 150, accuracy: 0.001)
        XCTAssertEqual(report.total.value, 2_300, accuracy: 0.001)
        XCTAssertEqual(report.active.provenance.confidence, .measured)
        XCTAssertFalse(report.totalIncludesWorkoutAndStepsTwice)
    }

    func testMissingWearableAddsNonOverlappingEstimatesAndShowsWideRange() {
        let report = EnergyEngine.dailyReport(
            resting: estimate(1_600, source: "Mifflin", confidence: .derived),
            strength: [estimate(180, source: "MET", confidence: .estimated)],
            cardio: [estimate(220, source: "MET", confidence: .estimated)],
            steps: 6_000,
            stepEstimate: estimate(90, source: "步数估算", confidence: .estimated),
            measuredDailyActive: nil
        )

        XCTAssertEqual(report.active.value, 490, accuracy: 0.001)
        XCTAssertGreaterThan(report.total.upperBound - report.total.lowerBound, 100)
        XCTAssertEqual(report.active.provenance.source, .phoneEstimate)
    }

    func testFallbackWalkingEnergySubtractsCardioSessionStepsWithoutChangingDailyTotal() {
        let report = EnergyEngine.dailyReport(
            resting: estimate(1_600, source: "Mifflin", confidence: .derived),
            strength: [],
            cardio: [estimate(250, source: "跑步", confidence: .estimated)],
            steps: 10_000,
            cardioWorkoutSteps: 4_000,
            stepEstimate: estimate(300, source: "全天步数", confidence: .estimated),
            measuredDailyActive: nil
        )

        XCTAssertEqual(report.steps, 10_000)
        XCTAssertEqual(report.walking.value, 180, accuracy: 0.001)
        XCTAssertEqual(report.active.value, 430, accuracy: 0.001)
    }

    private func estimate(_ value: Double, source: String, confidence: DataConfidence = .measured) -> MetricRange {
        MetricRange(value: value, lowerBound: value * 0.9, upperBound: value * 1.1, provenance: .init(source: confidence == .measured ? .appleHealth : .phoneEstimate, sourceName: source, confidence: confidence, coverage: 1))
    }
}
