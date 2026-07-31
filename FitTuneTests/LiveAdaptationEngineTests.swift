import XCTest
@testable import FitTune

final class LiveAdaptationEngineTests: XCTestCase {
    func testSlowerThanPersonalRecoveryExtendsButFasterRecoveryNeverShortensFloor() {
        let slow = LiveAdaptationEngine.adapt(
            baseRecommendation: baseRecommendation,
            baseRest: baseRest,
            currentLoadKg: 100,
            liveSignal: .init(
                response: setResponse,
                personalComparison: .slowerThanBaseline,
                sourceName: "FIT 3"
            ),
            calibrationPairs: 6,
            hasPain: false,
            painAlertThresholdReached: false,
            maximumHeartRateAlert: nil
        )
        let fast = LiveAdaptationEngine.adapt(
            baseRecommendation: baseRecommendation,
            baseRest: baseRest,
            currentLoadKg: 100,
            liveSignal: .init(
                response: setResponse,
                personalComparison: .withinBaseline,
                sourceName: "FIT 3"
            ),
            calibrationPairs: 6,
            hasPain: false,
            painAlertThresholdReached: false,
            maximumHeartRateAlert: nil
        )

        XCTAssertGreaterThan(slow.rest.recommendedSeconds, baseRest.recommendedSeconds)
        XCTAssertGreaterThanOrEqual(fast.rest.recommendedSeconds, baseRest.lowerSeconds)
        XCTAssertLessThanOrEqual(fast.nextLoadKg, 100)
    }

    func testInsufficientHistoryDisplaysResponseWithoutChangingBaseResult() {
        let advice = LiveAdaptationEngine.adapt(
            baseRecommendation: baseRecommendation,
            baseRest: baseRest,
            currentLoadKg: 100,
            liveSignal: .init(response: setResponse, personalComparison: .insufficientHistory, sourceName: "FIT 3"),
            calibrationPairs: 4,
            hasPain: false,
            painAlertThresholdReached: false,
            maximumHeartRateAlert: nil
        )

        XCTAssertEqual(advice.nextLoadKg, 100)
        XCTAssertEqual(advice.rest, baseRest)
        XCTAssertEqual(advice.confidence, .calibrating)
        XCTAssertTrue(advice.usedLiveHeartRate)
    }

    func testRepeatedInsufficientHistoryAdaptationKeepsOneDynamicReason() {
        let first = LiveAdaptationEngine.adapt(
            baseRecommendation: baseRecommendation,
            baseRest: baseRest,
            currentLoadKg: 100,
            liveSignal: .init(response: setResponse, personalComparison: .insufficientHistory, sourceName: "FIT 3"),
            calibrationPairs: 1,
            hasPain: false,
            painAlertThresholdReached: false,
            maximumHeartRateAlert: nil
        )
        let repeated = LiveAdaptationEngine.adapt(
            baseRecommendation: .init(
                nextLoadKg: first.nextLoadKg,
                adjustment: first.adjustment,
                reason: first.reasons.joined(separator: "；"),
                confidence: "校准中",
                restSeconds: first.rest.recommendedSeconds,
                suggestedRemainingSets: 2,
                continuation: .continueTraining
            ),
            baseRest: first.rest,
            currentLoadKg: 100,
            liveSignal: .init(response: setResponse, personalComparison: .insufficientHistory, sourceName: "FIT 3"),
            calibrationPairs: 1,
            hasPain: false,
            painAlertThresholdReached: false,
            maximumHeartRateAlert: nil
        )

        XCTAssertEqual(
            repeated.reasons.filter { $0 == "个人心率恢复历史不足，显示当前响应但不改变建议" }.count,
            1
        )
        XCTAssertEqual(repeated.reasons, ["基础", "个人心率恢复历史不足，显示当前响应但不改变建议"])
    }

    private var baseRecommendation: SetRecommendation {
        .init(nextLoadKg: 100, adjustment: .hold, reason: "基础", confidence: "中", restSeconds: 180, suggestedRemainingSets: 2, continuation: .continueTraining)
    }

    private var baseRest: RestRecommendation {
        .init(lowerSeconds: 120, recommendedSeconds: 180, upperSeconds: 240, confidence: "中", reasons: ["基础"], inputsUsed: ["RIR"])
    }

    private var setResponse: SetHeartRateResponse {
        .init(
            peakBPM: 170,
            peakDelaySeconds: 30,
            hrr60: 18,
            hrr120: 32,
            sourceName: "FIT 3",
            confidence: .derived
        )
    }
}
