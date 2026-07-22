import XCTest
@testable import FitTune

final class DomainModelTests: XCTestCase {
    func testTrainingPhasesHaveStableUserFacingTitles() {
        XCTAssertEqual(TrainingPhase.primary.title, "主项")
        XCTAssertEqual(TrainingPhase.accessory.title, "辅助项")
        XCTAssertEqual(TrainingPhase.finisher.title, "收尾")
    }

    func testLegacyPrescriptionResolvesPhaseWithoutRequiringStoredField() throws {
        let json = """
        {
          "id": "10000000-0000-0000-0000-000000000010",
          "name": "绳索侧平举",
          "pattern": "shoulderIsolation",
          "sets": 3,
          "repLower": 10,
          "repUpper": 15,
          "targetRIR": 0,
          "isPriority": false
        }
        """

        let decoded = try JSONDecoder().decode(ExercisePrescription.self, from: Data(json.utf8))

        XCTAssertNil(decoded.phase)
        XCTAssertEqual(decoded.resolvedPhase, .accessory)
    }

    func testExplicitTrainingPhaseRoundTrips() throws {
        let prescription = ExercisePrescription(
            name: "农夫行走",
            pattern: .conditioning,
            sets: 3,
            repLower: 30,
            repUpper: 60,
            targetRIR: 0,
            isPriority: false,
            phase: .finisher
        )

        XCTAssertEqual(try roundTrip(prescription).phase, .finisher)
    }

    func testCurrentSnapshotSchemaIsFourteen() {
        XCTAssertEqual(AppSnapshot.currentSchemaVersion, 14)
    }

    func testLegacySnapshotWithoutSchemaVersionResolvesVersionSix() throws {
        let json = """
        {
          "readiness": {
            "date": "2026-07-21T12:00:00Z",
            "sleepHours": 7.5,
            "soreness": 2,
            "stress": 2,
            "motivation": 4
          },
          "workoutHistory": [],
          "weightHistory": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(AppSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.resolvedSchemaVersion, 6)
    }

    func testV1MetricProvenanceRoundTripsWithConfidenceAndCoverage() throws {
        let provenance = MetricProvenance(
            source: .appleWatch,
            sourceName: "Apple Watch",
            confidence: .measured,
            coverage: 0.92,
            sampledAt: Date(timeIntervalSince1970: 1_721_563_200),
            algorithmVersion: "1.0.0"
        )

        let decoded = try roundTrip(provenance)

        XCTAssertEqual(decoded, provenance)
        XCTAssertEqual(decoded.confidence, .measured)
    }

    func testRecoveryCheckInKeepsAutomaticManualAndResolvedValuesSeparate() throws {
        let sleep = RecoveryDimensionValue(automaticValue: 82, manualValue: 70, resolvedValue: 70, provenance: .manual)
        let checkIn = RecoveryCheckIn(
            date: Date(timeIntervalSince1970: 1_721_563_200),
            sleep: sleep,
            soreness: RecoveryDimensionValue(manualValue: 25, resolvedValue: 25, provenance: .manual),
            stress: RecoveryDimensionValue(manualValue: 40, resolvedValue: 40, provenance: .manual),
            motivation: RecoveryDimensionValue(manualValue: 90, resolvedValue: 90, provenance: .manual)
        )

        let decoded = try roundTrip(checkIn)

        XCTAssertEqual(decoded.sleep.automaticValue, 82)
        XCTAssertEqual(decoded.sleep.manualValue, 70)
        XCTAssertEqual(decoded.sleep.resolvedValue, 70)
    }

    func testPlanSnapshotAndChangeEventAreImmutableHistoryPayloads() throws {
        let date = Date(timeIntervalSince1970: 1_721_563_200)
        let planSnapshot = PlanSnapshot(
            createdAt: date,
            sourcePlanRuleVersion: "0.6",
            sourceSessionID: UUID(),
            planTitle: "四分化",
            sessionName: "胸",
            goal: .hypertrophy,
            split: .chestBackShouldersLegs,
            equipment: .fullGym,
            exercises: []
        )
        let change = WorkoutChangeEvent(timestamp: date, kind: .exerciseAdded, exerciseName: "哑铃飞鸟", detail: "用户添加")
        let reorder = WorkoutChangeEvent(timestamp: date, kind: .exerciseReordered, exerciseName: "哑铃飞鸟", detail: "移至收尾")

        XCTAssertEqual(try roundTrip(planSnapshot), planSnapshot)
        XCTAssertEqual(try roundTrip(change), change)
        XCTAssertEqual(try roundTrip(reorder), reorder)
    }

    func testMetricSampleSummaryAndRevisionRoundTripWithoutLosingSource() throws {
        let date = Date(timeIntervalSince1970: 1_721_563_200)
        let provenance = MetricProvenance(source: .phoneEstimate, sourceName: "iPhone 估算", confidence: .estimated, coverage: 0.6)
        let sample = WorkoutMetricSample(timestamp: date, heartRateBPM: 142, cadence: 168, steps: 120, provenance: provenance)
        let summary = WorkoutSummary(
            generatedAt: date,
            algorithmVersion: "1.0.0",
            averageHeartRate: 138,
            maximumHeartRate: 171,
            activeEnergyKcal: MetricRange(value: 320, lowerBound: 270, upperBound: 370, provenance: provenance),
            estimatedRecoveryHours: MetricRange(value: 36, lowerBound: 24, upperBound: 48, provenance: provenance)
        )
        let revision = SummaryRevision(revisedAt: date, reason: "华为健康数据已同步", summary: summary)

        XCTAssertEqual(try roundTrip(sample), sample)
        XCTAssertEqual(try roundTrip(revision), revision)
        XCTAssertEqual(revision.summary.activeEnergyKcal?.provenance.source, .phoneEstimate)
    }

    func testPersonalSafetySettingsRoundTrip() throws {
        let settings = PersonalSafetySettings(
            avoidedRegions: [.shoulders],
            disabledExerciseIDs: ["dumbbell-front-raise"],
            painAlertThreshold: 2,
            maximumHeartRateAlert: 185
        )

        XCTAssertEqual(try roundTrip(settings), settings)
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: encoder.encode(value))
    }
}
