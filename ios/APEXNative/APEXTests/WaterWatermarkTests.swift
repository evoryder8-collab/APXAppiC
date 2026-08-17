import XCTest
@testable import APEX

/*
 * Pins the hydration merge rule that a manual reduction must survive.
 *
 * The original code took max(local, healthKit). Because APEX mirrors its own
 * additions into HealthKit, that made every decrease temporary: the next
 * sync restored the higher total and the person's edit silently vanished.
 * These cases describe the watermark behaviour instead: import only what
 * HealthKit has learned since the last sync.
 */
final class WaterWatermarkTests: XCTestCase {

    /// Mirrors AppSession's merge decision so the rule can be exercised
    /// without a live HealthKit store or Supabase session.
    private func merged(local: Double, healthKit: Double, watermark: Double?) -> Double {
        guard let watermark else { return max(local, healthKit) }
        let newlyLogged = healthKit - watermark
        guard newlyLogged > 0.001 else { return local }
        return min(6, ((local + newlyLogged) * 100).rounded() / 100)
    }

    func testFirstSyncOfADayAdoptsTheRicherRecord() {
        XCTAssertEqual(merged(local: 0, healthKit: 1.2, watermark: nil), 1.2, accuracy: 0.0001)
        XCTAssertEqual(merged(local: 2.0, healthKit: 1.2, watermark: nil), 2.0, accuracy: 0.0001)
    }

    func testManualReductionIsNotUndoneByTheNextSync() {
        /* 3.10 L logged through APEX, so HealthKit and the watermark agree.
           The person removes 250 ml by mistake-correction. */
        let afterManualRemoval = 2.85
        let result = merged(local: afterManualRemoval, healthKit: 3.10, watermark: 3.10)
        XCTAssertEqual(result, 2.85, accuracy: 0.0001, "A manual decrease must stick")
    }

    func testRepeatedSyncsDoNotRatchetTheTotalUpward() {
        var local = 2.85
        for _ in 0..<5 {
            local = merged(local: local, healthKit: 3.10, watermark: 3.10)
        }
        XCTAssertEqual(local, 2.85, accuracy: 0.0001)
    }

    func testWaterLoggedElsewhereStillArrives() {
        /* The Watch adds 300 ml: HealthKit moves past the watermark. */
        let result = merged(local: 2.85, healthKit: 3.40, watermark: 3.10)
        XCTAssertEqual(result, 3.15, accuracy: 0.0001, "New external water is imported as a delta")
    }

    func testAppExAdditionsDoNotDoubleCount() {
        /* APEX adds 250 ml: local and HealthKit both rise, and the watermark
           rises with them, so the following sync contributes nothing. */
        let localAfterAdd = 3.10
        let healthKitAfterAdd = 3.10
        let watermarkAfterAdd = 3.10
        XCTAssertEqual(
            merged(local: localAfterAdd, healthKit: healthKitAfterAdd, watermark: watermarkAfterAdd),
            3.10,
            accuracy: 0.0001
        )
    }

    func testTotalStaysWithinTheDailyCeiling() {
        XCTAssertEqual(merged(local: 5.9, healthKit: 9.0, watermark: 3.0), 6.0, accuracy: 0.0001)
    }
}
