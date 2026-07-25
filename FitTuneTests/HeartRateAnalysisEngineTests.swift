import XCTest
@testable import FitTune

final class HeartRateAnalysisEngineTests: XCTestCase {
    func testIntensityUsesElapsedTimeInsteadOfSampleCount() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "H10",
            confidence: .measured,
            coverage: 1
        )
        let samples = [
            WorkoutMetricSample(timestamp: start, heartRateBPM: 100, provenance: source),
            WorkoutMetricSample(timestamp: start.addingTimeInterval(300), heartRateBPM: 100, provenance: source),
            WorkoutMetricSample(timestamp: start.addingTimeInterval(305), heartRateBPM: 160, provenance: source),
            WorkoutMetricSample(timestamp: start.addingTimeInterval(310), heartRateBPM: 160, provenance: source)
        ]

        let result = try XCTUnwrap(HeartRateAnalysisEngine.intensitySummary(
            samples: samples,
            startedAt: start,
            completedAt: start.addingTimeInterval(600),
            restingHeartRate: 60,
            maximumHeartRate: 180
        ))

        XCTAssertLessThan(result.coverage, 0.05)
        XCTAssertLessThan(result.secondsByZone[.vigorous] ?? 0, 10)
    }

    func testSetResponseFindsPeakThirtySecondsAfterSetThenMeasuresFromPeak() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(30)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "FIT 3",
            confidence: .measured,
            coverage: 1
        )
        let samples = [
            WorkoutMetricSample(timestamp: end, heartRateBPM: 145, provenance: source),
            WorkoutMetricSample(timestamp: end.addingTimeInterval(30), heartRateBPM: 170, provenance: source),
            WorkoutMetricSample(timestamp: end.addingTimeInterval(90), heartRateBPM: 142, provenance: source),
            WorkoutMetricSample(timestamp: end.addingTimeInterval(150), heartRateBPM: 126, provenance: source)
        ]

        let response = try XCTUnwrap(HeartRateAnalysisEngine.setResponse(
            samples: samples,
            setStartedAt: start,
            setCompletedAt: end,
            nextSetStartedAt: nil
        ))

        XCTAssertEqual(response.peakBPM, 170)
        XCTAssertEqual(response.peakDelaySeconds, 30)
        XCTAssertEqual(response.hrr60 ?? 0, 28, accuracy: 0.1)
        XCTAssertEqual(response.hrr120 ?? 0, 44, accuracy: 0.1)
    }

    func testSetResponseExcludesPeakBeforeCurrentSetStart() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(30)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "H10",
            confidence: .measured,
            coverage: 1
        )
        let response = try XCTUnwrap(HeartRateAnalysisEngine.setResponse(
            samples: [
                .init(
                    timestamp: start.addingTimeInterval(-10),
                    heartRateBPM: 190,
                    provenance: source
                ),
                .init(timestamp: end, heartRateBPM: 150, provenance: source),
                .init(
                    timestamp: end.addingTimeInterval(25),
                    heartRateBPM: 170,
                    provenance: source
                )
            ],
            setStartedAt: start,
            setCompletedAt: end,
            nextSetStartedAt: nil
        ))
        XCTAssertEqual(response.peakBPM, 170)
    }

    func testSampleAt119SecondsAfterPeakCannotBecomeHRR60() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(30)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "H10",
            confidence: .measured,
            coverage: 1
        )
        let peakAt = end.addingTimeInterval(30)
        let response = try XCTUnwrap(HeartRateAnalysisEngine.setResponse(
            samples: [
                .init(timestamp: peakAt, heartRateBPM: 170, provenance: source),
                .init(
                    timestamp: peakAt.addingTimeInterval(119),
                    heartRateBPM: 130,
                    provenance: source
                )
            ],
            setStartedAt: start,
            setCompletedAt: end,
            nextSetStartedAt: nil
        ))
        XCTAssertNil(response.hrr60)
        XCTAssertEqual(response.hrr120, 40)
    }

    func testRecoveryWindowRejectsSourceSwitchAndMissingSamples() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(30)
        let h10 = MetricProvenance(
            source: .bluetooth,
            sourceName: "H10",
            confidence: .measured,
            coverage: 1
        )
        let watch = MetricProvenance(
            source: .appleWatch,
            sourceName: "Apple Watch",
            confidence: .measured,
            coverage: 1
        )
        let peakAt = end.addingTimeInterval(30)
        let switched = try XCTUnwrap(HeartRateAnalysisEngine.setResponse(
            samples: [
                .init(timestamp: peakAt, heartRateBPM: 170, provenance: h10),
                .init(
                    timestamp: peakAt.addingTimeInterval(60),
                    heartRateBPM: 140,
                    provenance: watch
                )
            ],
            setStartedAt: start,
            setCompletedAt: end,
            nextSetStartedAt: nil
        ))
        XCTAssertNil(switched.hrr60)
        XCTAssertNil(switched.hrr120)
    }

    func testSetResponseExcludesRecoverySamplesAfterNextSetStarts() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(30)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "H10",
            confidence: .measured,
            coverage: 1
        )
        let peakAt = end.addingTimeInterval(30)
        let response = try XCTUnwrap(HeartRateAnalysisEngine.setResponse(
            samples: [
                .init(timestamp: peakAt, heartRateBPM: 170, provenance: source),
                .init(
                    timestamp: peakAt.addingTimeInterval(60),
                    heartRateBPM: 140,
                    provenance: source
                )
            ],
            setStartedAt: start,
            setCompletedAt: end,
            nextSetStartedAt: peakAt.addingTimeInterval(30)
        ))

        XCTAssertNil(response.hrr60)
    }

    func testDriftUsesTimeWeightedHalvesForStableTwentyMinuteWorkload() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let completedAt = start.addingTimeInterval(1_200)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "H10",
            confidence: .measured,
            coverage: 1
        )
        let samples = (0...120).map { offset in
            WorkoutMetricSample(
                timestamp: start.addingTimeInterval(Double(offset * 10)),
                heartRateBPM: offset < 60 ? 130 : 143,
                provenance: source
            )
        }
        let workloads = [
            CardioWorkloadSegment(
                startedAt: start,
                endedAt: completedAt,
                speedKph: 10,
                inclinePercent: 1,
                powerWatts: 200,
                source: .device
            )
        ]

        let result = try XCTUnwrap(HeartRateAnalysisEngine.drift(
            samples: samples,
            workloads: workloads,
            startedAt: start,
            completedAt: completedAt
        ))

        XCTAssertEqual(result.percent, 9.91, accuracy: 0.01)
        XCTAssertEqual(result.workloadCoverage, 1, accuracy: 0.001)
        XCTAssertEqual(result.heartRateCoverage, 1, accuracy: 0.001)
    }
}
