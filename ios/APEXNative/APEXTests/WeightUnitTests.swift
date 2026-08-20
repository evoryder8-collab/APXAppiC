import XCTest
@testable import APEX

final class WeightUnitTests: XCTestCase {

    func testPoundsConvertAndComeBackUnchanged() {
        // Storage stays in kilograms, so a round trip must not drift: these
        // numbers are compared week to week.
        for kilograms in [45.0, 71.0, 82.5, 118.0] {
            let pounds = WeightUnit.pounds.value(fromKilograms: kilograms)
            let back = WeightUnit.pounds.kilograms(fromValue: pounds)
            XCTAssertEqual(back, kilograms, accuracy: 0.0001)
        }
    }

    func testDisplayReadsTheWayPeopleSpeak() {
        XCTAssertEqual(WeightUnit.kilograms.format(kilograms: 71), "71 kg")
        XCTAssertEqual(WeightUnit.kilograms.format(kilograms: 71.4), "71.4 kg")
        // No decimal on pounds: nobody weighs to a tenth of a pound.
        XCTAssertEqual(WeightUnit.pounds.format(kilograms: 71), "157 lb")
    }

    func testAnUnsetOrUnknownPreferenceStaysMetric() {
        XCTAssertEqual(WeightUnit.current(nil), .kilograms)
    }
}
