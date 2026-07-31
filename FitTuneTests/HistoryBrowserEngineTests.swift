import XCTest
@testable import FitTune

final class HistoryBrowserEngineTests: XCTestCase {
    func testBrowseSortsStrengthCardioAndSportNewestFirst() {
        let strength = strengthRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "上肢力量",
            completedAt: date(100)
        )
        let cardio = cardioRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            date: date(300)
        )
        let sport = HistorySportProjection(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            date: date(200),
            title: "篮球对抗",
            searchTerms: ["篮球"]
        )

        let result = HistoryBrowserEngine.browse(
            strength: [strength],
            cardio: [cardio],
            sports: [sport]
        )

        XCTAssertEqual(result.map(\.type), [.cardio, .sport, .strength])
        XCTAssertEqual(result.map(\.id), [cardio.id, sport.id, strength.id])
    }

    func testBrowseAppliesTypeAndInclusiveDateFiltersTogether() {
        let early = strengthRecord(id: UUID(), name: "早期力量", completedAt: date(100))
        let inRange = strengthRecord(id: UUID(), name: "区间力量", completedAt: date(200))
        let cardio = cardioRecord(id: UUID(), date: date(200))

        let result = HistoryBrowserEngine.browse(
            strength: [early, inRange],
            cardio: [cardio],
            sports: [],
            filter: HistoryBrowserFilter(
                types: [.strength],
                startDate: date(200),
                endDate: date(200)
            )
        )

        XCTAssertEqual(result.map(\.id), [inRange.id])
    }

    func testSearchMatchesStrengthSessionAndExerciseNames() {
        let matchingExercise = strengthRecord(
            id: UUID(),
            name: "推训练",
            completedAt: date(300),
            exerciseName: "上斜哑铃卧推"
        )
        let matchingSession = strengthRecord(
            id: UUID(),
            name: "哑铃全身循环",
            completedAt: date(200),
            exerciseName: "深蹲"
        )
        let unrelated = strengthRecord(
            id: UUID(),
            name: "拉训练",
            completedAt: date(100),
            exerciseName: "高位下拉"
        )

        let result = HistoryBrowserEngine.browse(
            strength: [matchingExercise, matchingSession, unrelated],
            cardio: [],
            sports: [],
            filter: HistoryBrowserFilter(query: "  哑铃 ")
        )

        XCTAssertEqual(result.map(\.id), [matchingExercise.id, matchingSession.id])
    }

    func testSearchMatchesCardioAndSportNames() {
        let cardio = cardioRecord(id: UUID(), date: date(100), modality: .running)
        let sport = HistorySportProjection(
            id: UUID(),
            date: date(200),
            title: "周末球局",
            searchTerms: ["三人篮球", "室内球馆"]
        )

        let runningResult = HistoryBrowserEngine.browse(
            strength: [],
            cardio: [cardio],
            sports: [sport],
            filter: HistoryBrowserFilter(query: "跑步")
        )
        let sportResult = HistoryBrowserEngine.browse(
            strength: [],
            cardio: [cardio],
            sports: [sport],
            filter: HistoryBrowserFilter(query: "篮球")
        )

        XCTAssertEqual(runningResult.map(\.id), [cardio.id])
        XCTAssertEqual(sportResult.map(\.id), [sport.id])
    }

    func testBrowseCannotReturnDeletedRecordsThatAreNotInActiveInput() {
        let active = strengthRecord(id: UUID(), name: "保留记录", completedAt: date(200))
        let deleted = strengthRecord(id: UUID(), name: "已删除记录", completedAt: date(300))

        let result = HistoryBrowserEngine.browse(
            strength: [active],
            cardio: [],
            sports: []
        )

        XCTAssertEqual(result.map(\.id), [active.id])
        XCTAssertFalse(result.contains { $0.id == deleted.id })
    }

    private func strengthRecord(
        id: UUID,
        name: String,
        completedAt: Date,
        exerciseName: String = "杠铃深蹲"
    ) -> WorkoutRecord {
        WorkoutRecord(
            id: id,
            sessionName: name,
            startedAt: completedAt.addingTimeInterval(-3_600),
            completedAt: completedAt,
            readinessScore: 80,
            sets: [
                SetResult(
                    exerciseID: UUID(),
                    exerciseName: exerciseName,
                    setNumber: 1,
                    loadKg: 60,
                    reps: 8,
                    rir: 2,
                    completedAt: completedAt
                )
            ]
        )
    }

    private func cardioRecord(
        id: UUID,
        date: Date,
        modality: CardioModality = .cycling
    ) -> CardioWorkoutRecord {
        CardioWorkoutRecord(
            id: id,
            date: date,
            modality: modality,
            intensity: .zone2,
            durationMinutes: 30,
            activeEnergyKcal: 220,
            source: "测试"
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }
}
