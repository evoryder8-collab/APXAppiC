/*
 * Region is detected, not asked, and it must never change how a stored food
 * is read - only how it is shown and ranked.
 */
import XCTest
@testable import APEX

final class FoodRegionTests: XCTestCase {
    func testClassifiesBothCodeShapes() {
        // A device region is alpha-2; an App Store storefront is alpha-3.
        XCTAssertEqual(FoodRegion.classify("CH"), .europe)
        XCTAssertEqual(FoodRegion.classify("CHE"), .europe)
        XCTAssertEqual(FoodRegion.classify("ro"), .europe)
        XCTAssertEqual(FoodRegion.classify("US"), .unitedStates)
        XCTAssertEqual(FoodRegion.classify("USA"), .unitedStates)
        XCTAssertNil(FoodRegion.classify("JP"))
        XCTAssertNil(FoodRegion.classify(""))
        XCTAssertNil(FoodRegion.classify(nil))
    }

    /// The case that made storefront the weaker signal: someone living in
    /// Switzerland whose Apple ID still bills to Romania is still European,
    /// but a US expat in Zurich should read as European, not American.
    func testDeviceRegionOutranksTheStorefront() {
        XCTAssertEqual(FoodRegion.detected(deviceRegion: "CH", storefront: "USA"), .europe)
        XCTAssertEqual(FoodRegion.detected(deviceRegion: "US", storefront: "CHE"), .unitedStates)
        // Storefront only speaks when the device region says nothing useful.
        XCTAssertEqual(FoodRegion.detected(deviceRegion: "JP", storefront: "CHE"), .europe)
        XCTAssertEqual(FoodRegion.detected(deviceRegion: nil, storefront: nil), .international)
    }

    func testStoredOverrideBeatsDetection() {
        var settings = UserSettings(
            userID: UUID(), voiceOn: true, ticksOn: true,
            notificationsOn: false, guardianFactor: 1.4, addons: [:]
        )
        settings.addons["food_region"] = .string("united_states")
        XCTAssertEqual(FoodRegion.resolved(settings, detected: .europe), .unitedStates)
        settings.addons["food_region"] = .string("nonsense")
        XCTAssertEqual(FoodRegion.resolved(settings, detected: .europe), .europe, "a bad value falls back to detection")
        settings.addons.removeValue(forKey: "food_region")
        XCTAssertEqual(FoodRegion.resolved(settings, detected: .europe), .europe)
    }

    func testPresentationRules() {
        XCTAssertTrue(FoodRegion.europe.presentation.metric)
        XCTAssertTrue(FoodRegion.europe.presentation.showsKilojoules)
        XCTAssertFalse(FoodRegion.unitedStates.presentation.metric)
        XCTAssertFalse(FoodRegion.unitedStates.presentation.showsKilojoules)
        // Everywhere else is metric, but has no regional staple table yet.
        XCTAssertTrue(FoodRegion.international.presentation.metric)
        XCTAssertFalse(FoodRegion.international.presentation.showsKilojoules)
    }

    /// EU Regulation 1169/2011 fixes the conversion factor.
    func testKilojouleConversion() {
        XCTAssertEqual(FoodRegion.kilojoules(100), 418)
        XCTAssertEqual(FoodRegion.kilojoules(0), 0)
    }
}
