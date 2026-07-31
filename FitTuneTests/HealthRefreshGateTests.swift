import XCTest
@testable import FitTune

final class HealthRefreshGateTests: XCTestCase {
    func testRequestDuringRefreshSchedulesExactlyOneFollowUp() {
        var gate = HealthRefreshGate()

        XCTAssertTrue(gate.requestRefresh())
        XCTAssertFalse(gate.requestRefresh())
        XCTAssertFalse(gate.requestRefresh())
        XCTAssertTrue(gate.finishRefreshAndBeginPending())
        XCTAssertFalse(gate.finishRefreshAndBeginPending())
    }

    func testIdleRequestCanStartAgainAfterCompletion() {
        var gate = HealthRefreshGate()

        XCTAssertTrue(gate.requestRefresh())
        XCTAssertFalse(gate.finishRefreshAndBeginPending())
        XCTAssertTrue(gate.requestRefresh())
    }
}
