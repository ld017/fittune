import XCTest
@testable import FitTune

final class BluetoothHeartRateParserTests: XCTestCase {
    func testParsesEightAndSixteenBitHeartRate() throws {
        XCTAssertEqual(try BluetoothHeartRateParser.parse([0x00, 72]).bpm, 72)
        XCTAssertEqual(try BluetoothHeartRateParser.parse([0x01, 0x2C, 0x01]).bpm, 300)
    }

    func testParsesContactEnergyAndRRIntervals() throws {
        let result = try BluetoothHeartRateParser.parse([0x1E, 100, 0x2C, 0x01, 0x00, 0x04])
        XCTAssertEqual(result.contactDetected, true)
        XCTAssertEqual(result.energyExpendedKilojoules, 300)
        XCTAssertEqual(result.rrIntervalsSeconds, [1.0])

        let poorContact = try BluetoothHeartRateParser.parse([0x02, 80])
        XCTAssertEqual(poorContact.contactDetected, false)
    }
}
