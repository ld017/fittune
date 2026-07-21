import XCTest
@testable import FitTune

final class TrendEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testThirtyDayWindowIncludesBoundaryAndExcludesOlderAndDeletedRecords() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let boundary = calendar.date(byAdding: .day, value: -30, to: now)!
        let old = calendar.date(byAdding: .second, value: -1, to: boundary)!
        let records = [record(date: boundary, load: 80), record(date: old, load: 200)]

        let result = TrendEngine.strength(records: records, bodyWeightKg: 80, now: now)

        XCTAssertEqual(result.sampleCount, 1)
        XCTAssertEqual(result.latestValue ?? 0, 80 * (1 + 10.0 / 30), accuracy: 0.001)
    }

    func testStrengthTrendUsesWorkingSetsAndReturnsRelativeStrength() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let earlier = calendar.date(byAdding: .day, value: -20, to: now)!
        let warmup = SetResult(exerciseID: UUID(), exerciseName: "杠铃卧推", setNumber: 1, loadKg: 100, reps: 10, rir: 0, completedAt: earlier, setKind: .warmup)
        let records = [record(date: earlier, load: 60, extraSets: [warmup]), record(date: now, load: 72)]

        let result = TrendEngine.strength(records: records, bodyWeightKg: 80, now: now)

        XCTAssertEqual(result.sampleCount, 2)
        XCTAssertEqual(result.direction, .improving)
        XCTAssertEqual(result.relativeValue ?? 0, 1.2, accuracy: 0.001)
    }

    func testSingleSampleDoesNotManufactureTrend() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let result = TrendEngine.strength(records: [record(date: now, load: 60)], bodyWeightKg: 70, now: now)
        XCTAssertEqual(result.direction, .unavailable)
    }

    func testRepeatedLowRecoveryAndPerformanceDeclineOnlySuggestsDeload() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let records = (0..<3).map { offset in
            record(date: calendar.date(byAdding: .day, value: -offset * 3, to: now)!, load: 60 - Double(offset) * -5)
        }
        let recovery = (0..<3).map { offset in
            RecoveryEntry(date: calendar.date(byAdding: .day, value: -offset * 3, to: now)!, sleepHours: 5.5, sleepQuality: 2, soreness: 4, stress: 4, motivation: 2, readinessScore: 48)
        }

        let suggestion = TrendEngine.deloadSuggestion(workouts: records, recovery: recovery, now: now)

        XCTAssertNotNil(suggestion)
        XCTAssertTrue(suggestion!.isAdvisoryOnly)
    }

    private func record(date: Date, load: Double, extraSets: [SetResult] = []) -> WorkoutRecord {
        let set = SetResult(exerciseID: UUID(), exerciseName: "杠铃卧推", setNumber: 1, loadKg: load, reps: 10, rir: 0, completedAt: date, setKind: .working)
        return WorkoutRecord(sessionName: "胸", startedAt: date.addingTimeInterval(-3600), completedAt: date, readinessScore: 70, sets: [set] + extraSets)
    }
}
