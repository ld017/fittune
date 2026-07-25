import XCTest
@testable import FitTune

@MainActor
final class CardioSessionTests: XCTestCase {
    func testCardioDraftPersistsInitialWorkloadAndConfirmedDistance() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let segment = CardioWorkloadSegment(
            startedAt: start,
            speedKph: 5,
            inclinePercent: 8,
            handrailSupport: .none,
            source: .userEntered
        )
        let draft = CardioSessionDraft(
            modality: .inclineWalking,
            intensity: .zone2,
            startedAt: start,
            workloadSegments: [segment],
            confirmedDistanceMeters: 5_000
        )

        let restored = try JSONDecoder().decode(
            CardioSessionDraft.self,
            from: JSONEncoder().encode(draft)
        )

        XCTAssertEqual(restored.workloadSegments, [segment])
        XCTAssertEqual(restored.confirmedDistanceMeters, 5_000)
    }

    func testModalitiesExposeOnlySupportedMetrics() {
        XCTAssertTrue(CardioSessionCapabilities.metrics(for: .running, hasWatch: false).contains(.pace))
        XCTAssertTrue(CardioSessionCapabilities.metrics(for: .inclineWalking, hasWatch: false).contains(.incline))
        XCTAssertTrue(CardioSessionCapabilities.metrics(for: .stairClimber, hasWatch: false).contains(.floors))
        XCTAssertTrue(CardioSessionCapabilities.metrics(for: .cycling, hasWatch: false).contains(.power))
        XCTAssertFalse(CardioSessionCapabilities.metrics(for: .swimming, hasWatch: false).contains(.strokeCount))
        XCTAssertTrue(CardioSessionCapabilities.unavailableMetrics(for: .swimming, hasWatch: false).contains(.strokeCount))
    }

    func testCardioDraftRestoresWithoutDuplicatingSamples() throws {
        let defaults = makeDefaults()
        let store = AppStore(defaults: defaults)
        store.startCardioSession(modality: .running, intensity: .zone2)
        let sample = WorkoutMetricSample(
            id: UUID(),
            timestamp: .now,
            cadence: 170,
            distanceMeters: 100,
            provenance: .init(source: .phoneSensor, sourceName: "iPhone", confidence: .measured, coverage: 1)
        )
        store.appendCardioMetricSample(sample)
        store.appendCardioMetricSample(sample)
        store.checkpointActiveCardio()

        let restored = AppStore(defaults: defaults)

        XCTAssertEqual(restored.activeCardioDraft?.id, store.activeCardioDraft?.id)
        XCTAssertEqual(restored.activeCardioDraft?.metricSamples.count, 1)
        XCTAssertEqual(restored.activeCardioDraft?.distanceMeters, 100)
    }

    func testLiveCardioKeepsAndSegmentsInitialTreadmillWorkload() throws {
        let defaults = makeDefaults()
        let store = AppStore(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        store.startCardioSession(
            modality: .inclineWalking,
            intensity: .zone2,
            speedKph: 5,
            inclinePercent: 8,
            powerWatts: nil,
            handrailSupport: .none,
            at: start
        )
        store.updateCardioWorkload(
            speedKph: 5.5,
            inclinePercent: 10,
            powerWatts: nil,
            handrailSupport: .occasional,
            at: start.addingTimeInterval(1_800)
        )

        let draft = try XCTUnwrap(store.activeCardioDraft)
        XCTAssertEqual(draft.workloadSegments.count, 2)
        XCTAssertEqual(draft.workloadSegments[0].endedAt, start.addingTimeInterval(1_800))
        XCTAssertEqual(draft.workloadSegments[1].speedKph, 5.5)
    }

    func testCardioEntryConfigurationStartsLiveSessionWithoutDroppingInputs() {
        let store = AppStore(defaults: makeDefaults())
        store.startCardioSession(
            modality: .inclineWalking,
            intensity: .zone2,
            speedKph: 5.2,
            inclinePercent: 9,
            powerWatts: nil,
            handrailSupport: .occasional
        )

        XCTAssertEqual(store.activeCardioDraft?.currentWorkload?.speedKph, 5.2)
        XCTAssertEqual(store.activeCardioDraft?.currentWorkload?.inclinePercent, 9)
        XCTAssertEqual(store.activeCardioDraft?.currentWorkload?.handrailSupport, .occasional)
    }

    func testMachineLevelCalibrationResolvesGradeAndSurvivesPersistence() throws {
        let segment = CardioWorkloadSegment(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            speedKph: 5,
            inclineInputMode: .machineLevel,
            inclineLevel: 10,
            machineMaximumLevel: 20,
            maximumGradeCalibration: .init(rise: 30, horizontalRun: 100),
            handrailSupport: .none,
            source: .userEntered
        )

        let restored = try JSONDecoder().decode(
            CardioWorkloadSegment.self,
            from: JSONEncoder().encode(segment)
        )

        XCTAssertEqual(restored.resolvedInclinePercent, 15)
        XCTAssertEqual(restored.inclineLevel, 10)
        XCTAssertEqual(restored.machineMaximumLevel, 20)
        XCTAssertEqual(restored.maximumGradeCalibration, .init(rise: 30, horizontalRun: 100))
    }

    func testMachineLevelWorkloadChangeCreatesSegmentAndKeepsCalibration() throws {
        let store = AppStore(defaults: makeDefaults())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let calibration = TreadmillGradeCalibration(rise: 20, horizontalRun: 100)
        store.startCardioSession(
            modality: .inclineWalking,
            intensity: .zone2,
            speedKph: 5,
            inclineInputMode: .machineLevel,
            inclineLevel: 20,
            machineMaximumLevel: 20,
            maximumGradeCalibration: calibration,
            handrailSupport: .none,
            at: start
        )

        store.updateCardioWorkload(
            speedKph: 5.5,
            inclineInputMode: .machineLevel,
            inclineLevel: 20,
            machineMaximumLevel: 20,
            maximumGradeCalibration: calibration,
            powerWatts: nil,
            handrailSupport: .none,
            at: start.addingTimeInterval(60)
        )

        let draft = try XCTUnwrap(store.activeCardioDraft)
        XCTAssertEqual(draft.workloadSegments.count, 2)
        XCTAssertEqual(draft.currentWorkload?.speedKph, 5.5)
        XCTAssertEqual(draft.currentWorkload?.resolvedInclinePercent, 20)
        XCTAssertEqual(draft.currentWorkload?.maximumGradeCalibration, calibration)
    }

    func testTreadmillCalibrationPersistsAndReusesForFutureMachineLevelSession() throws {
        let defaults = makeDefaults()
        let calibration = TreadmillMachineCalibration(
            maximumLevel: 15,
            gradeCalibration: .init(rise: 30, horizontalRun: 100)
        )
        let store = AppStore(defaults: defaults)
        store.setTreadmillMachineCalibration(calibration)

        let restored = AppStore(defaults: defaults)
        XCTAssertEqual(restored.treadmillMachineCalibration, calibration)

        restored.startCardioSession(
            modality: .inclineWalking,
            intensity: .zone2,
            speedKph: 5,
            inclineInputMode: .machineLevel,
            inclineLevel: 7.5,
            handrailSupport: .none
        )

        let workload = try XCTUnwrap(restored.activeCardioDraft?.currentWorkload)
        XCTAssertEqual(workload.machineMaximumLevel, 15)
        XCTAssertEqual(workload.maximumGradeCalibration, calibration.gradeCalibration)
        XCTAssertEqual(workload.resolvedInclinePercent, 15)

        restored.discardCardioSession()
        XCTAssertEqual(restored.treadmillMachineCalibration, calibration)
        restored.startCardioSession(
            modality: .inclineWalking,
            intensity: .zone2,
            inclineInputMode: .machineLevel,
            inclineLevel: 15
        )
        XCTAssertEqual(restored.activeCardioDraft?.currentWorkload?.resolvedInclinePercent, 30)
    }

    func testLegacyWorkloadWithoutInclineModeDecodesAsPercentGrade() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "startedAt": 0,
          "speedKph": 5,
          "inclinePercent": 8,
          "handrailSupport": "none",
          "source": "userEntered"
        }
        """.data(using: .utf8)!

        let restored = try JSONDecoder().decode(CardioWorkloadSegment.self, from: json)

        XCTAssertEqual(restored.resolvedInclinePercent, 8)
        XCTAssertEqual(restored.resolvedInclineInputMode, .percentGrade)
    }

    func testManualMachineLevelWorkoutRecordsLevelAndUsesMETUntilCalibrated() throws {
        let record = TrainingEngine.makeCardioWorkout(
            modality: .inclineWalking,
            intensity: .zone2,
            minutes: 30,
            weightKg: 70,
            speedKph: 5,
            inclineInputMode: .machineLevel,
            inclineLevel: 20,
            machineMaximumLevel: 20,
            maximumGradeCalibration: nil,
            handrailSupport: .none
        )

        let workload = try XCTUnwrap(record.workloadSegments?.first)
        XCTAssertEqual(workload.inclineLevel, 20)
        XCTAssertEqual(workload.machineMaximumLevel, 20)
        XCTAssertTrue(record.energyMethod?.contains("MET") == true)
        XCTAssertTrue(record.energyDiagnostics?.warnings.contains { $0.contains("档位") && $0.contains("校准") } == true)
    }

    func testIdenticalCardioWorkloadUpdateDoesNotCreateAnotherSegment() throws {
        let store = AppStore(defaults: makeDefaults())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.startCardioSession(
            modality: .cycling,
            intensity: .zone2,
            powerWatts: 180,
            at: start
        )

        store.updateCardioWorkload(
            speedKph: nil,
            inclinePercent: nil,
            powerWatts: 180,
            handrailSupport: .none,
            at: start.addingTimeInterval(600)
        )

        let draft = try XCTUnwrap(store.activeCardioDraft)
        XCTAssertEqual(draft.workloadSegments.count, 1)
        XCTAssertNil(draft.workloadSegments[0].endedAt)
    }

    func testStaleCardioWorkloadUpdateLeavesOpenSegmentUntouched() throws {
        let store = AppStore(defaults: makeDefaults())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.startCardioSession(modality: .inclineWalking, intensity: .zone2, speedKph: 5, at: start)

        store.updateCardioWorkload(
            speedKph: 6,
            inclinePercent: nil,
            powerWatts: nil,
            handrailSupport: .none,
            at: start
        )

        let draft = try XCTUnwrap(store.activeCardioDraft)
        XCTAssertEqual(draft.workloadSegments.count, 1)
        XCTAssertEqual(draft.workloadSegments[0].speedKph, 5)
        XCTAssertNil(draft.workloadSegments[0].endedAt)
    }

    func testFinishingCardioBeforeItsStartKeepsDraftOpen() throws {
        let store = AppStore(defaults: makeDefaults())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.startCardioSession(modality: .inclineWalking, intensity: .zone2, speedKph: 5, at: start)

        let record = store.finishCardioSession(status: .completed, at: start.addingTimeInterval(-1))

        XCTAssertNil(record)
        XCTAssertNotNil(store.activeCardioDraft)
        XCTAssertNil(store.activeCardioDraft?.workloadSegments[0].endedAt)
        XCTAssertTrue(store.cardioWorkouts.isEmpty)
    }

    func testPermissionInterruptionCreatesPartialResultWithGapReason() throws {
        let store = AppStore(defaults: makeDefaults())
        store.startCardioSession(modality: .cycling, intensity: .zone2)
        store.markCardioDataGap("定位权限被撤回")

        let result = try XCTUnwrap(store.finishCardioSession(status: .partial))

        XCTAssertEqual(result.completionStatus, .partial)
        XCTAssertEqual(result.dataGapReason, "定位权限被撤回")
        XCTAssertTrue(result.metricSamples?.isEmpty ?? true)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "CardioSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
