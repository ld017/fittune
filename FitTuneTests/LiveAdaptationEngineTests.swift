import XCTest
@testable import FitTune

final class LiveAdaptationEngineTests: XCTestCase {
    func testPoorHeartRateRecoveryOnlyExtendsRestAndBlocksIncrease() {
        let advice = LiveAdaptationEngine.adapt(
            baseRecommendation: .init(nextLoadKg: 102.5, adjustment: .increase, reason: "表现允许加重", confidence: "中", restSeconds: 180, suggestedRemainingSets: 2, continuation: .continueTraining),
            baseRest: .init(lowerSeconds: 120, recommendedSeconds: 180, upperSeconds: 240, confidence: "中", reasons: ["基础"], inputsUsed: ["RIR"]),
            currentLoadKg: 100,
            liveSignal: .init(peakHeartRate: 170, currentHeartRate: 162, secondsAfterSet: 60, validity: .valid, sourceName: "Apple Watch"),
            calibrationSessions: 5,
            hasPain: false,
            painAlertThresholdReached: false,
            maximumHeartRateAlert: nil
        )

        XCTAssertLessThanOrEqual(advice.nextLoadKg, 100)
        XCTAssertNotEqual(advice.adjustment, .increase)
        XCTAssertGreaterThan(advice.rest.recommendedSeconds, 180)
        XCTAssertTrue(advice.canContinue)
    }

    func testHeartRateAloneNeverRaisesLoad() {
        let advice = makeAdvice(signal: .init(peakHeartRate: 170, currentHeartRate: 120, secondsAfterSet: 60, validity: .valid, sourceName: "H10"))
        XCTAssertEqual(advice.nextLoadKg, 100)
        XCTAssertEqual(advice.adjustment, .hold)
    }

    func testInvalidOrMissingHeartRateFallsBackWithoutBlockingTraining() {
        let advice = makeAdvice(signal: .init(peakHeartRate: nil, currentHeartRate: nil, secondsAfterSet: 60, validity: .poorContact, sourceName: "H10"))
        XCTAssertEqual(advice.nextLoadKg, 100)
        XCTAssertEqual(advice.rest.recommendedSeconds, 180)
        XCTAssertFalse(advice.usedLiveHeartRate)
        XCTAssertTrue(advice.canContinue)
        XCTAssertEqual(advice.confidence, .estimated)
    }

    func testCalibrationPeriodAndSafetyAlertsRemainAdvisory() {
        let advice = LiveAdaptationEngine.adapt(
            baseRecommendation: baseRecommendation,
            baseRest: baseRest,
            currentLoadKg: 100,
            liveSignal: .init(peakHeartRate: 190, currentHeartRate: 185, secondsAfterSet: 60, validity: .valid, sourceName: "Apple Watch"),
            calibrationSessions: 2,
            hasPain: true,
            painAlertThresholdReached: true,
            maximumHeartRateAlert: 180
        )
        XCTAssertEqual(advice.confidence, .calibrating)
        XCTAssertEqual(advice.safetyAlerts.count, 2)
        XCTAssertTrue(advice.canContinue)
        XCTAssertFalse(advice.automaticallyEndsExercise)
    }

    private var baseRecommendation: SetRecommendation {
        .init(nextLoadKg: 100, adjustment: .hold, reason: "基础", confidence: "中", restSeconds: 180, suggestedRemainingSets: 2, continuation: .continueTraining)
    }

    private var baseRest: RestRecommendation {
        .init(lowerSeconds: 120, recommendedSeconds: 180, upperSeconds: 240, confidence: "中", reasons: ["基础"], inputsUsed: ["RIR"])
    }

    private func makeAdvice(signal: LiveHeartRateSignal) -> LiveAdaptationAdvice {
        LiveAdaptationEngine.adapt(
            baseRecommendation: baseRecommendation,
            baseRest: baseRest,
            currentLoadKg: 100,
            liveSignal: signal,
            calibrationSessions: 5,
            hasPain: false,
            painAlertThresholdReached: false,
            maximumHeartRateAlert: nil
        )
    }
}
