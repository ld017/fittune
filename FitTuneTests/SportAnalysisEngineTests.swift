import XCTest
@testable import FitTune

final class SportAnalysisEngineTests: XCTestCase {
    func testSevenSportsExposeStableTitlesSymbolsAndWatchActivityKeys() {
        let expected: [(SportKind, String, String, String)] = [
            (.badminton, "羽毛球", "figure.badminton", "badminton"),
            (.tableTennis, "乒乓球", "figure.table.tennis", "tableTennis"),
            (.soccer, "足球", "figure.soccer", "soccer"),
            (.climbing, "攀岩", "figure.climbing", "climbing"),
            (.hiking, "徒步", "figure.hiking", "hiking"),
            (.mountaineering, "登山", "mountain.2", "hiking"),
            (.trailRunning, "越野跑", "figure.run", "running")
        ]

        XCTAssertEqual(SportKind.allCases.map(\.rawValue), [
            "badminton", "tableTennis", "soccer", "climbing",
            "hiking", "mountaineering", "trailRunning"
        ])
        for (kind, title, symbol, activityKey) in expected {
            XCTAssertEqual(kind.title, title)
            XCTAssertEqual(kind.symbol, symbol)
            XCTAssertEqual(kind.watchActivityKey, activityKey)
        }
    }

    func testIndoorRacketSportsNeverClaimDistanceOrElevation() {
        for kind in [SportKind.badminton, .tableTennis] {
            let capabilities = SportAnalysisEngine.capabilities(
                kind: kind,
                environment: .indoor,
                hasHeartRate: true,
                hasLocation: true,
                hasPedometer: true,
                hasElevation: true
            )

            XCTAssertTrue(capabilities.contains(.duration))
            XCTAssertTrue(capabilities.contains(.heartRate))
            XCTAssertTrue(capabilities.contains(.steps))
            XCTAssertFalse(capabilities.contains(.distance))
            XCTAssertFalse(capabilities.contains(.pace))
            XCTAssertFalse(capabilities.contains(.speed))
            XCTAssertFalse(capabilities.contains(.altitude))
            XCTAssertFalse(capabilities.contains(.elevationGain))
        }
    }

    func testOutdoorTrailSportsExposeDistancePaceAndElevationOnlyWithEvidence() {
        for kind in [SportKind.hiking, .mountaineering, .trailRunning] {
            let unavailable = SportAnalysisEngine.capabilities(
                kind: kind,
                environment: .outdoor,
                hasHeartRate: false,
                hasLocation: false,
                hasPedometer: false,
                hasElevation: true
            )
            XCTAssertFalse(unavailable.contains(.distance))
            XCTAssertFalse(unavailable.contains(.pace))
            XCTAssertFalse(unavailable.contains(.altitude))
            XCTAssertFalse(unavailable.contains(.elevationGain))

            let available = SportAnalysisEngine.capabilities(
                kind: kind,
                environment: .outdoor,
                hasHeartRate: false,
                hasLocation: true,
                hasPedometer: true,
                hasElevation: true
            )
            XCTAssertTrue(available.contains(.distance))
            XCTAssertTrue(available.contains(.altitude))
            XCTAssertTrue(available.contains(.elevationGain))

            if kind == .mountaineering {
                XCTAssertTrue(available.contains(.movingTime))
            } else {
                XCTAssertTrue(available.contains(.pace))
            }
        }
    }

    func testPausedTimeIsExcludedFromEffectiveDurationAndSessionRPELoad() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var draft = SportSessionDraft(
            kind: .soccer,
            environment: .outdoor,
            intensity: .training,
            startedAt: start
        )
        draft.pauseIntervals = [
            SportPauseInterval(
                startedAt: start.addingTimeInterval(10 * 60),
                endedAt: start.addingTimeInterval(15 * 60)
            )
        ]

        let result = SportAnalysisEngine.analyze(
            draft: draft,
            completedAt: start.addingTimeInterval(45 * 60),
            sessionRPE: 7,
            weightKg: 70,
            restingHeartRate: nil,
            maximumHeartRate: nil
        )

        XCTAssertEqual(result.effectiveDurationSeconds, 40 * 60, accuracy: 0.001)
        XCTAssertEqual(result.sessionRPELoadAU, 280, accuracy: 0.001)
    }

    func testBadmintonMETEstimateUsesNetActiveEnergyRange() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let draft = SportSessionDraft(
            kind: .badminton,
            environment: .indoor,
            intensity: .social,
            startedAt: start
        )

        let result = SportAnalysisEngine.analyze(
            draft: draft,
            completedAt: start.addingTimeInterval(60 * 60),
            sessionRPE: 5,
            weightKg: 70,
            restingHeartRate: nil,
            maximumHeartRate: nil
        )

        XCTAssertEqual(result.activeEnergyKcal.value, 330.75, accuracy: 0.001)
        XCTAssertEqual(result.activeEnergyKcal.lowerBound, 330.75, accuracy: 0.001)
        XCTAssertEqual(result.activeEnergyKcal.upperBound, 588, accuracy: 0.001)
        XCTAssertEqual(result.activeEnergyKcal.provenance.source, .phoneEstimate)
        XCTAssertEqual(result.algorithmVersion, "2.0.0-sport-analysis-1")
    }

    func testSportAnalysisRejectsHeartRateGapsLongerThanFifteenSeconds() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "H10",
            confidence: .measured,
            coverage: 1
        )
        var draft = SportSessionDraft(
            kind: .tableTennis,
            environment: .indoor,
            intensity: .training,
            startedAt: start
        )
        draft.metricSamples = [
            .init(timestamp: start, heartRateBPM: 120, provenance: source),
            .init(timestamp: start.addingTimeInterval(16), heartRateBPM: 140, provenance: source)
        ]

        let result = SportAnalysisEngine.analyze(
            draft: draft,
            completedAt: start.addingTimeInterval(16),
            sessionRPE: 4,
            weightKg: 70,
            restingHeartRate: 60,
            maximumHeartRate: 180
        )

        XCTAssertNil(result.heartRateIntensity)
        XCTAssertTrue(result.warnings.contains { $0.contains("15 秒") })
    }

    func testPercentMaxZonesDoNotReuseHeartRateReserveThresholds() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = MetricProvenance(
            source: .bluetooth,
            sourceName: "H10",
            confidence: .measured,
            coverage: 1
        )

        let percentMax = try XCTUnwrap(HeartRateAnalysisEngine.intensitySummary(
            samples: [
                .init(timestamp: start, heartRateBPM: 90, provenance: source),
                .init(timestamp: start.addingTimeInterval(10), heartRateBPM: 90, provenance: source)
            ],
            startedAt: start,
            completedAt: start.addingTimeInterval(10),
            restingHeartRate: nil,
            maximumHeartRate: 200
        ))
        XCTAssertFalse(percentMax.usedHeartRateReserve)
        XCTAssertEqual(percentMax.secondsByZone[.veryLight] ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(percentMax.secondsByZone[.moderate] ?? 0, 0, accuracy: 0.001)

        let heartRateReserve = try XCTUnwrap(HeartRateAnalysisEngine.intensitySummary(
            samples: [
                .init(timestamp: start, heartRateBPM: 114, provenance: source),
                .init(timestamp: start.addingTimeInterval(10), heartRateBPM: 114, provenance: source)
            ],
            startedAt: start,
            completedAt: start.addingTimeInterval(10),
            restingHeartRate: 60,
            maximumHeartRate: 180
        ))
        XCTAssertTrue(heartRateReserve.usedHeartRateReserve)
        XCTAssertEqual(heartRateReserve.secondsByZone[.moderate] ?? 0, 10, accuracy: 0.001)
    }

    func testLegacyWorkoutMetricSampleDecodesWithoutOutdoorFields() throws {
        let data = Data(#"""
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "timestamp":0,
          "heartRateBPM":142,
          "provenance":{
            "source":"bluetooth",
            "sourceName":"H10",
            "confidence":"measured",
            "coverage":1
          }
        }
        """#.utf8)

        let sample = try JSONDecoder().decode(WorkoutMetricSample.self, from: data)

        XCTAssertNil(sample.altitudeMeters)
        XCTAssertNil(sample.elevationGainMeters)
        XCTAssertNil(sample.speedMetersPerSecond)
    }

    func testAnalysisIncludesConservativeRecoveryRangeAndMetadata() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let draft = SportSessionDraft(
            kind: .mountaineering,
            environment: .outdoor,
            intensity: .training,
            startedAt: start
        )

        let result = SportAnalysisEngine.analyze(
            draft: draft,
            completedAt: start.addingTimeInterval(90 * 60),
            sessionRPE: 7,
            weightKg: 70,
            restingHeartRate: nil,
            maximumHeartRate: nil
        )

        XCTAssertLessThan(result.estimatedRecoveryHours.lowerBound, result.estimatedRecoveryHours.value)
        XCTAssertGreaterThan(result.estimatedRecoveryHours.upperBound, result.estimatedRecoveryHours.value)
        XCTAssertEqual(result.estimatedRecoveryHours.provenance.confidence, .estimated)
        XCTAssertFalse(result.provenance.isEmpty)
        XCTAssertGreaterThanOrEqual(result.dataCoverage, 0)
        XCTAssertLessThanOrEqual(result.dataCoverage, 1)
        XCTAssertFalse(result.warnings.isEmpty)
    }
}
