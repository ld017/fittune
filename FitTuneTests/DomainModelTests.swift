import XCTest
@testable import FitTune

final class DomainModelTests: XCTestCase {
    func testNumericInputAllowsTemporaryEmptyAndClampsOnlyWhenCommitted() {
        XCTAssertEqual(NumericInputPolicy.commit("", previous: 80, range: 0...400), 80)
        XCTAssertEqual(NumericInputPolicy.commit("82.5", previous: 80, range: 0...400), 82.5)
        XCTAssertEqual(NumericInputPolicy.commit("999", previous: 80, range: 0...400), 400)
    }
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

    func testCurrentSnapshotSchemaIsSixteen() {
        XCTAssertEqual(AppSnapshot.currentSchemaVersion, 16)
    }

    func testScientificWorkoutFieldsRoundTripAndLegacyFieldsRemainOptional() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let segment = CardioWorkloadSegment(
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            speedKph: 5,
            inclinePercent: 8,
            handrailSupport: .none,
            source: .userEntered
        )
        let response = SetHeartRateResponse(
            peakBPM: 168,
            peakDelaySeconds: 30,
            hrr60: 24,
            hrr120: 38,
            sourceName: "HUAWEI WATCH FIT 3",
            confidence: .derived
        )
        let set = SetResult(
            exerciseID: UUID(),
            exerciseName: "杠铃深蹲",
            setNumber: 1,
            loadKg: 100,
            reps: 5,
            rir: 1,
            completedAt: start.addingTimeInterval(40),
            startedAt: start,
            restEndedAt: start.addingTimeInterval(220),
            actualRestSeconds: 180,
            heartRateResponse: response
        )

        let data = try JSONEncoder().encode(set)
        XCTAssertEqual(try JSONDecoder().decode(SetResult.self, from: data), set)
        XCTAssertEqual(segment.durationSeconds, 600)
        XCTAssertEqual(AppSnapshot.currentSchemaVersion, 16)
    }

    func testLegacySummaryMetricsDecodeWithoutScientificSummaryFields() throws {
        let strength = StrengthSummaryMetrics(
            volumeLoadKg: 1_000,
            workingSetCount: 2,
            warmupSetCount: 1,
            failureRate: 0,
            bestE1RMKg: 100,
            relativeStrength: 1.4,
            e1RMConfidence: .derived,
            muscleLoad: ["腿": 1_000]
        )
        var strengthObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(strength)) as? [String: Any])
        strengthObject.removeValue(forKey: "targetWorkingSetCount")
        strengthObject.removeValue(forKey: "targetSetCompletion")
        let decodedStrength = try JSONDecoder().decode(
            StrengthSummaryMetrics.self,
            from: JSONSerialization.data(withJSONObject: strengthObject)
        )

        XCTAssertNil(decodedStrength.targetWorkingSetCount)
        XCTAssertNil(decodedStrength.targetSetCompletion)

        let cardio = CardioSummaryMetrics(
            distanceKm: 5,
            paceSecondsPerKm: 360,
            averageCadence: 170,
            strokeCount: nil,
            heartRateRecovery60: nil,
            vo2Max: nil,
            vo2MaxConfidence: .unavailable
        )
        var cardioObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(cardio)) as? [String: Any])
        cardioObject.removeValue(forKey: "usedHeartRateReserve")
        cardioObject.removeValue(forKey: "intensityConfidence")
        cardioObject.removeValue(forKey: "percentageByIntensityZone")
        let decodedCardio = try JSONDecoder().decode(
            CardioSummaryMetrics.self,
            from: JSONSerialization.data(withJSONObject: cardioObject)
        )

        XCTAssertNil(decodedCardio.usedHeartRateReserve)
        XCTAssertNil(decodedCardio.intensityConfidence)
        XCTAssertNil(decodedCardio.percentageByIntensityZone)
    }

    func testSchemaFourteenSetStillDecodesWithoutScientificTimeline() throws {
        let old = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "exerciseID":"00000000-0000-0000-0000-000000000002",
          "exerciseName":"卧推",
          "setNumber":1,
          "loadKg":80,
          "reps":8,
          "rir":1,
          "completedAt":"2026-07-26T10:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let set = try decoder.decode(SetResult.self, from: Data(old.utf8))

        XCTAssertNil(set.startedAt)
        XCTAssertNil(set.restEndedAt)
        XCTAssertNil(set.actualRestSeconds)
        XCTAssertNil(set.heartRateResponse)
    }

    func testLegacyDraftsDecodeWithoutNewTimelineCollections() throws {
        let cardioDraft = CardioSessionDraft(modality: .running, intensity: .zone2)
        let cardioData = try JSONEncoder().encode(cardioDraft)
        var cardioObject = try XCTUnwrap(JSONSerialization.jsonObject(with: cardioData) as? [String: Any])
        cardioObject.removeValue(forKey: "workloadSegments")
        cardioObject.removeValue(forKey: "workloadWarnings")
        let decodedCardioDraft = try JSONDecoder().decode(
            CardioSessionDraft.self,
            from: JSONSerialization.data(withJSONObject: cardioObject)
        )

        let exercise = ExercisePrescription(
            name: "卧推",
            pattern: .horizontalPush,
            sets: 3,
            repLower: 6,
            repUpper: 10,
            targetRIR: 1,
            isPriority: true
        )
        let workoutDraft = WorkoutDraft(
            sourceSessionID: UUID(),
            session: TrainingSession(name: "胸", focus: "胸", exercises: [exercise]),
            exerciseIndex: 0,
            setNumber: 1,
            loadKg: 80,
            reps: 8,
            rir: 1,
            techniqueQuality: 4,
            hasPain: false
        )
        let workoutData = try JSONEncoder().encode(workoutDraft)
        var workoutObject = try XCTUnwrap(JSONSerialization.jsonObject(with: workoutData) as? [String: Any])
        workoutObject.removeValue(forKey: "pauseIntervals")
        let decodedWorkoutDraft = try JSONDecoder().decode(
            WorkoutDraft.self,
            from: JSONSerialization.data(withJSONObject: workoutObject)
        )

        XCTAssertEqual(decodedCardioDraft.workloadSegments, [])
        XCTAssertEqual(decodedCardioDraft.workloadWarnings, [])
        XCTAssertEqual(decodedWorkoutDraft.pauseIntervals, [])
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
