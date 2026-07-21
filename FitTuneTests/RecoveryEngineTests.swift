import XCTest
@testable import FitTune

final class RecoveryEngineTests: XCTestCase {
    func testManualValueOverridesAutomaticAndReportsEveryContribution() {
        let checkIn = RecoveryCheckIn(
            date: Date(timeIntervalSince1970: 2_000_000),
            sleep: .init(automaticValue: 4, manualValue: 3, provenance: .appleHealth),
            soreness: .init(manualValue: 2, provenance: .manual),
            stress: .init(manualValue: 2, provenance: .manual),
            motivation: .init(manualValue: 5, provenance: .manual)
        )

        let result = RecoveryEngine.assess(checkIn: checkIn, restingHeartRates: [])

        XCTAssertEqual(result.contributions.count, 4)
        XCTAssertEqual(result.contributions.first(where: { $0.dimension == .sleep })?.resolvedValue, 3)
        XCTAssertEqual(result.contributions.first(where: { $0.dimension == .sleep })?.provenance, .manual)
        XCTAssertNil(result.restingHeartRateBaseline)
        XCTAssertEqual(result.restingHeartRateAdjustment, 0)
    }

    func testMissingAutomaticValuesFallBackToManualWithoutTreatingMissingAsZero() {
        let complete = RecoveryCheckIn(
            date: .now,
            sleep: .init(manualValue: 4, provenance: .manual),
            soreness: .init(manualValue: 2, provenance: .manual),
            stress: .init(manualValue: 2, provenance: .manual),
            motivation: .init(manualValue: 4, provenance: .manual)
        )
        var missing = complete
        missing.stress = .init(provenance: .unavailable)

        let completeResult = RecoveryEngine.assess(checkIn: complete, restingHeartRates: [])
        let missingResult = RecoveryEngine.assess(checkIn: missing, restingHeartRates: [])

        XCTAssertEqual(missingResult.contributions.count, 3)
        XCTAssertGreaterThan(missingResult.score, 0)
        XCTAssertEqual(missingResult.score, completeResult.score)
    }

    func testRestingHeartRateNeedsSevenBaselineDays() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let samples = (1...6).map {
            RestingHeartRateSample(date: now.addingTimeInterval(Double(-$0 * 86_400)), bpm: 60, source: .appleHealth, sourceName: "健康")
        } + [RestingHeartRateSample(date: now, bpm: 72, source: .appleHealth, sourceName: "健康")]

        let result = RecoveryEngine.assess(checkIn: neutralCheckIn(at: now), restingHeartRates: samples)

        XCTAssertNil(result.restingHeartRateBaseline)
        XCTAssertEqual(result.restingHeartRateAdjustment, 0)
    }

    func testRestingHeartRateThresholdsUseTwentyOneDayMedian() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let baseline = (1...9).map {
            RestingHeartRateSample(date: now.addingTimeInterval(Double(-$0 * 86_400)), bpm: $0 == 1 ? 100 : 60, source: .appleHealth, sourceName: "健康")
        }
        let plusFive = baseline + [RestingHeartRateSample(date: now, bpm: 65, source: .appleHealth, sourceName: "健康")]
        let plusTen = baseline + [RestingHeartRateSample(date: now, bpm: 70, source: .appleHealth, sourceName: "健康")]

        let moderate = RecoveryEngine.assess(checkIn: neutralCheckIn(at: now), restingHeartRates: plusFive)
        let high = RecoveryEngine.assess(checkIn: neutralCheckIn(at: now), restingHeartRates: plusTen)

        XCTAssertEqual(moderate.restingHeartRateBaseline, 60)
        XCTAssertEqual(moderate.restingHeartRateAdjustment, -5)
        XCTAssertEqual(high.restingHeartRateAdjustment, -10)
        XCTAssertEqual(high.score, moderate.score - 5)
    }

    private func neutralCheckIn(at date: Date) -> RecoveryCheckIn {
        RecoveryCheckIn(
            date: date,
            sleep: .init(manualValue: 3, provenance: .manual),
            soreness: .init(manualValue: 3, provenance: .manual),
            stress: .init(manualValue: 3, provenance: .manual),
            motivation: .init(manualValue: 3, provenance: .manual)
        )
    }
}
