import XCTest
@testable import FitTune

final class HealthImportMergeTests: XCTestCase {
    func testOverlappingSleepSamplesAreMergedWithoutDoubleCounting() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            SleepImportSample(externalID: "1", start: start, end: start.addingTimeInterval(4 * 3600), stage: .asleep, source: .appleWatch),
            SleepImportSample(externalID: "2", start: start.addingTimeInterval(3 * 3600), end: start.addingTimeInterval(7 * 3600), stage: .asleep, source: .huaweiHealth),
            SleepImportSample(externalID: "awake", start: start.addingTimeInterval(5 * 3600), end: start.addingTimeInterval(5.5 * 3600), stage: .awake, source: .huaweiHealth)
        ]

        let summary = HealthImportMerger.mergeSleep(samples)

        XCTAssertEqual(summary.totalSleepMinutes, 390, accuracy: 0.01)
        XCTAssertEqual(summary.awakeMinutes, 30, accuracy: 0.01)
        XCTAssertEqual(summary.interruptionCount, 1)
        XCTAssertEqual(summary.sourceKinds, [.appleWatch, .huaweiHealth])
    }

    func testSourceRecognitionUsesMetadataRatherThanOneBundleIdentifier() {
        XCTAssertEqual(HealthSourceClassifier.classify(sourceName: "HUAWEI Health", bundleIdentifier: "com.vendor.changed", productType: nil), .huaweiHealth)
        XCTAssertEqual(HealthSourceClassifier.classify(sourceName: "健康", bundleIdentifier: "com.apple.health.123", productType: "Watch7,1"), .appleWatch)
        XCTAssertEqual(HealthSourceClassifier.classify(sourceName: "Polar H10", bundleIdentifier: "fi.polar.app", productType: nil), .other)
    }

    func testDuplicateHealthKitUUIDIsImportedOnlyOnce() {
        let date = Date(timeIntervalSince1970: 2_000_000)
        let old = RestingHeartRateSample(date: date, bpm: 60, source: .appleHealth, sourceName: "健康", externalID: "same-uuid")
        let duplicate = RestingHeartRateSample(date: date, bpm: 61, source: .appleHealth, sourceName: "健康", externalID: "same-uuid")
        let new = RestingHeartRateSample(date: date.addingTimeInterval(60), bpm: 62, source: .appleHealth, sourceName: "健康", externalID: "new-uuid")

        let merged = HealthImportMerger.mergeRestingHeartRates(existing: [old], incoming: [duplicate, new])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first(where: { $0.externalID == "same-uuid" })?.bpm, 60)
    }

    func testStressExplicitlyRequiresManualInput() {
        XCTAssertFalse(HealthImportCapabilities.supportsGenericStressScore)
        XCTAssertEqual(HealthImportCapabilities.stressFallback, .manual)
    }
}
