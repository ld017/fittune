import XCTest
@testable import FitTune

final class DomainModelTests: XCTestCase {
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
}
