import XCTest
@testable import FitTune

final class CardioEnergyEstimatorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testOneHourInclineWalkUsesACSMSegmentsForAbout427ActiveKcal() {
        let input = CardioEnergyInput(
            modality: .inclineWalking,
            intensity: .zone2,
            startedAt: start,
            completedAt: start.addingTimeInterval(3_600),
            weightKg: 70,
            profile: nil,
            confirmedDistanceKm: 5,
            sensorDistanceKm: nil,
            workloadSegments: [
                .init(
                    startedAt: start,
                    endedAt: start.addingTimeInterval(3_600),
                    speedKph: 5,
                    inclinePercent: 8,
                    handrailSupport: .none,
                    source: .userEntered
                )
            ],
            metricSamples: [],
            deviceEstimateKcal: 166,
            deviceEnergySource: .appleWatch,
            importedDeviceOnly: false
        )

        let estimate = CardioEnergyEstimator.estimate(input)

        XCTAssertEqual(estimate.kilocalories, 427, accuracy: 1)
        XCTAssertEqual(estimate.diagnostics?.comparisonEstimateKcal, 166)
        XCTAssertTrue(estimate.method.contains("ACSM"))
        XCTAssertGreaterThan(estimate.lowerBound, 300)
    }

    func testTwoInclineSegmentsIntegrateTheirOwnSpeedAndGrade() {
        let segments = [
            CardioWorkloadSegment(
                startedAt: start,
                endedAt: start.addingTimeInterval(1_800),
                speedKph: 4.5,
                inclinePercent: 6,
                source: .userEntered
            ),
            CardioWorkloadSegment(
                startedAt: start.addingTimeInterval(1_800),
                endedAt: start.addingTimeInterval(3_600),
                speedKph: 5.5,
                inclinePercent: 10,
                source: .userEntered
            )
        ]

        let estimate = CardioEnergyEstimator.estimate(input(workloadSegments: segments))

        XCTAssertEqual(estimate.kilocalories, 433.3, accuracy: 0.1)
        XCTAssertNotEqual(estimate.kilocalories, TrainingEngine.netActiveEnergy(met: 6.5, weightKg: 70, minutes: 60))
    }

    func testDistanceConflictAndSustainedHandrailsDemoteACSM() {
        let mismatched = CardioEnergyEstimator.estimate(input(
            confirmedDistanceKm: 2,
            workloadSegments: [walkingSegment(speedKph: 5, inclinePercent: 8)]
        ))
        let handrails = CardioEnergyEstimator.estimate(input(
            workloadSegments: [walkingSegment(speedKph: 5, inclinePercent: 8, handrailSupport: .sustained)]
        ))

        XCTAssertTrue(mismatched.diagnostics?.warnings.contains { $0.contains("距离") } == true)
        XCTAssertGreaterThanOrEqual(mismatched.upperBound / mismatched.kilocalories, 1.25)
        XCTAssertFalse(handrails.diagnostics?.primaryModel.contains("ACSM") == true)
        XCTAssertFalse(handrails.method.contains("ACSM"))
    }

    func testHeartRateFillsOnlyCoveredIntervalsAndMETFillsGap() {
        let source = MetricProvenance(source: .bluetooth, sourceName: "H10", confidence: .measured, coverage: 1)
        let samples = stride(from: 0.0, through: 1_200, by: 10).map {
            WorkoutMetricSample(timestamp: start.addingTimeInterval($0), heartRateBPM: 145, provenance: source)
        }
        var profile = cardioProfile()
        profile.ageYears = 30
        profile.biologicalSex = .male

        let estimate = CardioEnergyEstimator.estimate(input(
            modality: .cycling,
            completedAt: start.addingTimeInterval(1_800),
            profile: profile,
            metricSamples: samples
        ))

        XCTAssertTrue(estimate.method.contains("Keytel"))
        XCTAssertEqual(estimate.kilocalories, 248.7, accuracy: 1)
        XCTAssertLessThan(estimate.kilocalories, 300)
    }

    func testCyclingPowerUsesEighteenToTwentyFivePercentEfficiencyRange() {
        let estimate = CardioEnergyEstimator.estimate(input(
            modality: .cycling,
            workloadSegments: [
                .init(startedAt: start, endedAt: start.addingTimeInterval(3_600), powerWatts: 200, source: .device)
            ]
        ))

        XCTAssertTrue(estimate.method.contains("功率"))
        XCTAssertEqual(estimate.lowerBound, 688.3, accuracy: 1)
        XCTAssertEqual(estimate.upperBound, 955.9, accuracy: 1)
    }

    func testDeviceOnlyImportUsesWideDeviceRangeButManualValueStaysComparison() {
        let deviceOnly = CardioEnergyEstimator.estimate(input(
            workloadSegments: [],
            deviceEstimateKcal: 300,
            deviceEnergySource: .appleWatch,
            importedDeviceOnly: true
        ))
        let manual = CardioEnergyEstimator.estimate(input(
            workloadSegments: [],
            deviceEstimateKcal: 300,
            deviceEnergySource: .manual,
            importedDeviceOnly: false
        ))

        XCTAssertEqual(deviceOnly.kilocalories, 300)
        XCTAssertLessThanOrEqual(deviceOnly.lowerBound, 225)
        XCTAssertGreaterThanOrEqual(deviceOnly.upperBound, 375)
        XCTAssertEqual(manual.diagnostics?.comparisonEstimateKcal, 300)
        XCTAssertFalse(manual.method.contains("Apple Watch"))
    }

    private func input(
        modality: CardioModality = .inclineWalking,
        intensity: CardioIntensity = .zone2,
        completedAt: Date? = nil,
        profile: UserProfile? = nil,
        confirmedDistanceKm: Double? = nil,
        workloadSegments: [CardioWorkloadSegment] = [],
        metricSamples: [WorkoutMetricSample] = [],
        deviceEstimateKcal: Double? = nil,
        deviceEnergySource: MetricSource? = nil,
        importedDeviceOnly: Bool = false
    ) -> CardioEnergyInput {
        CardioEnergyInput(
            modality: modality,
            intensity: intensity,
            startedAt: start,
            completedAt: completedAt ?? start.addingTimeInterval(3_600),
            weightKg: 70,
            profile: profile,
            confirmedDistanceKm: confirmedDistanceKm,
            sensorDistanceKm: nil,
            workloadSegments: workloadSegments,
            metricSamples: metricSamples,
            deviceEstimateKcal: deviceEstimateKcal,
            deviceEnergySource: deviceEnergySource,
            importedDeviceOnly: importedDeviceOnly
        )
    }

    private func walkingSegment(speedKph: Double, inclinePercent: Double, handrailSupport: HandrailSupport = .none) -> CardioWorkloadSegment {
        CardioWorkloadSegment(
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            speedKph: speedKph,
            inclinePercent: inclinePercent,
            handrailSupport: handrailSupport,
            source: .userEntered
        )
    }

    private func cardioProfile() -> UserProfile {
        UserProfile(
            nickname: "Test",
            goal: .generalFitness,
            secondaryGoal: .none,
            experience: .intermediate,
            weeklyDays: 3,
            sessionMinutes: 60,
            equipment: .fullGym,
            bodyWeightKg: 70,
            loadIncrementKg: 2.5
        )
    }
}
