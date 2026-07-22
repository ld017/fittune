import XCTest
@testable import FitTune

final class ExerciseReplacementEngineTests: XCTestCase {
    func testHardFiltersRemoveDisabledInjuredAndUnavailableExercises() throws {
        let current = try exercise("杠铃卧推")
        let disabled = try exercise("哑铃卧推")
        let injured = try exercise("蝴蝶机夹胸")
        let unavailable = try exercise("片装式水平推胸")
        let context = ExerciseReplacementContext(
            current: current,
            phase: .primary,
            availableEquipment: [.barbell],
            disabledExerciseIDs: [disabled.id],
            injuredMuscles: [.chest],
            favoriteIDs: [],
            recentExerciseIDs: [],
            includeUnavailableEquipment: false
        )

        let results = ExerciseReplacementEngine.rank(
            catalog: [current, disabled, injured, unavailable],
            context: context
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testUnavailableEquipmentAppearsOnlyWhenExplicitlyIncluded() throws {
        let current = try exercise("杠铃卧推")
        let machine = try exercise("片装式水平推胸")
        var context = context(current: current, equipment: [.barbell])

        XCTAssertFalse(ExerciseReplacementEngine.rank(catalog: [machine], context: context).contains { $0.id == machine.id })

        context.includeUnavailableEquipment = true
        let candidate = try XCTUnwrap(ExerciseReplacementEngine.rank(catalog: [machine], context: context).first)
        XCTAssertFalse(candidate.equipmentAvailable)
    }

    func testSamePatternRanksAboveSameMuscleDifferentPatternAndExplainsScore() throws {
        let current = try exercise("杠铃卧推")
        let samePattern = try exercise("哑铃卧推")
        let sameMuscle = try exercise("哑铃飞鸟")
        var context = context(current: current, equipment: [.dumbbell])
        context.phase = .accessory
        context.favoriteIDs = [samePattern.id]
        context.recentExerciseIDs = [samePattern.id]

        let results = ExerciseReplacementEngine.rank(catalog: [sameMuscle, samePattern], context: context)

        XCTAssertEqual(results.map(\.id), [samePattern.id, sameMuscle.id])
        XCTAssertTrue(results[0].reasons.contains("同为水平推"))
        XCTAssertTrue(results[0].reasons.contains("主练胸部"))
        XCTAssertTrue(results[0].reasons.contains("适合辅助项"))
        XCTAssertTrue(results[0].reasons.contains("已收藏"))
        XCTAssertTrue(results[0].reasons.contains("近期训练表现可参考"))
    }

    func testCurrentExerciseIsNeverReturnedAsItsOwnReplacement() throws {
        let current = try exercise("杠铃卧推")

        let results = ExerciseReplacementEngine.rank(
            catalog: [current, try exercise("哑铃卧推")],
            context: context(current: current, equipment: [.barbell, .dumbbell])
        )

        XCTAssertFalse(results.contains { $0.id == current.id })
    }

    func testTiedCandidatesSortByFavoriteThenLocalizedName() throws {
        let current = try exercise("杠铃卧推")
        let first = try exercise("哑铃地板卧推")
        let second = try exercise("哑铃挤压卧推")
        var context = context(current: current, equipment: [.dumbbell])
        context.favoriteIDs = [second.id]

        let results = ExerciseReplacementEngine.rank(catalog: [first, second], context: context)

        XCTAssertEqual(results.first?.id, second.id)
    }

    func testLoadTransferPreservesOnlyExactImplementationOrExactHistory() throws {
        let current = ExercisePrescription(
            name: "杠铃卧推",
            pattern: .horizontalPush,
            sets: 4,
            repLower: 6,
            repUpper: 10,
            targetRIR: 0,
            isPriority: true,
            suggestedLoadKg: 80,
            equipmentKind: .barbell
        )
        let same = try exercise("杠铃卧推")
        let different = try exercise("哑铃卧推")

        let preserved = ExerciseReplacementEngine.transferLoad(from: current, to: same, history: [])
        let cleared = ExerciseReplacementEngine.transferLoad(from: current, to: different, history: [])

        XCTAssertEqual(preserved.suggestedLoadKg, 80)
        XCTAssertEqual(preserved.confidence, .derived)
        XCTAssertNil(cleared.suggestedLoadKg)
        XCTAssertEqual(cleared.confidence, .unavailable)
    }

    private func context(current: ExerciseOption, equipment: Set<EquipmentKind>) -> ExerciseReplacementContext {
        ExerciseReplacementContext(
            current: current,
            phase: .primary,
            availableEquipment: equipment,
            disabledExerciseIDs: [],
            injuredMuscles: [],
            favoriteIDs: [],
            recentExerciseIDs: [],
            includeUnavailableEquipment: false
        )
    }

    private func exercise(_ name: String) throws -> ExerciseOption {
        try XCTUnwrap(ExerciseCatalog.builtIns.first { $0.name == name }, "动作库缺少 \(name)")
    }
}

