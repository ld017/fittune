import XCTest
@testable import FitTune

final class ExerciseCatalogTests: XCTestCase {
    func testRequestedV1ExercisesHaveCorrectPatternEquipmentAndSubcategory() throws {
        let expected: [(String, MovementPattern, EquipmentKind, ExerciseSubcategory)] = [
            ("哑铃前平举", .shoulderIsolation, .dumbbell, .shoulderFront),
            ("哑铃弯举", .arms, .dumbbell, .biceps),
            ("哑铃锤式弯举", .arms, .dumbbell, .brachialis),
            ("负重引体向上", .verticalPull, .bodyweightBand, .verticalPull),
            ("对握高位下拉", .verticalPull, .cable, .verticalPull),
            ("窄握高位下拉", .verticalPull, .cable, .verticalPull),
            ("反手高位下拉", .verticalPull, .cable, .verticalPull),
            ("泽奇深蹲", .squat, .barbell, .squat),
            ("颈前深蹲", .squat, .barbell, .squat)
        ]

        for item in expected {
            let exercise = try XCTUnwrap(TrainingEngine.allExercises.first { $0.name == item.0 }, "缺少动作：\(item.0)")
            XCTAssertEqual(exercise.pattern, item.1, item.0)
            XCTAssertEqual(exercise.equipment, item.2, item.0)
            XCTAssertEqual(exercise.resolvedSubcategory, item.3, item.0)
        }
    }

    func testCatalogUsesUniqueStableIDsAndCanonicalNames() {
        let catalog = TrainingEngine.allExercises
        XCTAssertEqual(Set(catalog.map(\.id)).count, catalog.count)
        XCTAssertEqual(Set(catalog.map { $0.name.normalizedExerciseName }).count, catalog.count)
        XCTAssertFalse(catalog.contains { $0.name.contains(" + ") })
    }

    func testLegacyFrontSquatAliasResolvesToCanonicalFrontSquat() {
        XCTAssertEqual(TrainingEngine.canonicalExercise(named: "前蹲")?.name, "颈前深蹲")
    }

    func testReplacementCandidatesNeverCrossMovementPattern() {
        for pattern in MovementPattern.allCases {
            XCTAssertTrue(TrainingEngine.exerciseAlternatives(for: pattern).allSatisfy { $0.pattern == pattern })
        }
    }

    func testCustomExerciseRoundTripsWithSourceAndReplacementIDs() throws {
        let custom = ExerciseOption(
            name: "我的单臂下拉",
            pattern: .verticalPull,
            equipment: .cable,
            category: .back,
            subcategory: .verticalPull,
            stableID: "custom.test.pull",
            replacementIDs: ["back.cable.verticalPull.对握高位下拉"],
            source: .custom
        )

        let decoded = try JSONDecoder().decode(ExerciseOption.self, from: JSONEncoder().encode(custom))

        XCTAssertEqual(decoded, custom)
        XCTAssertEqual(decoded.source, .custom)
    }

    func testCompatibleFavoriteIsPreferredButIncompatibleFavoriteIsIgnored() {
        let profile = UserProfile(
            nickname: "测试",
            goal: .hypertrophy,
            secondaryGoal: .none,
            experience: .intermediate,
            weeklyDays: 3,
            sessionMinutes: 60,
            equipment: .dumbbells,
            bodyWeightKg: 70,
            loadIncrementKg: 2.5
        )
        let dumbbellPress = try! XCTUnwrap(TrainingEngine.canonicalExercise(named: "哑铃卧推"))
        let barbellSquat = try! XCTUnwrap(TrainingEngine.canonicalExercise(named: "杠铃深蹲"))

        let plan = TrainingEngine.generatePlan(
            for: profile,
            favoriteExerciseIDs: [dumbbellPress.id, barbellSquat.id],
            customExercises: []
        )

        let horizontalPresses = plan.sessions.flatMap(\.exercises).filter { $0.pattern == .horizontalPush }
        XCTAssertTrue(horizontalPresses.allSatisfy { $0.name == "哑铃卧推" })
        XCTAssertFalse(plan.sessions.flatMap(\.exercises).contains { $0.name == "杠铃深蹲" })
    }
}
