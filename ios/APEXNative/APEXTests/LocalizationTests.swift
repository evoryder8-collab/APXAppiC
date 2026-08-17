import XCTest
@testable import APEX

@MainActor
final class LocalizationTests: XCTestCase {
    func testThaiRuntimeSeedAndNumericCoachingCopyAreFullyLocalized() {
        let state = LanguageState.shared
        let previous = state.language
        defer { state.language = previous }
        state.language = .thai

        XCTAssertEqual(state.text("Endurance · Clarity · Mastery"), "ความอึด · ความชัดเจน · ความเชี่ยวชาญ")
        XCTAssertEqual(state.text("Bulgarian Split Squat"), "บัลแกเรียนสปลิตสควอต")
        XCTAssertEqual(
            state.text("Optional 35 g carbohydrate adjustment around the run. Review the exact change before applying it."),
            "ปรับคาร์โบไฮเดรตรอบการวิ่งได้อีก 35 กรัม โปรดตรวจการเปลี่ยนแปลงก่อนยืนยัน"
        )
        XCTAssertEqual(
            state.text("Sedentary day: oats 45 g instead of 80 g."),
            "ระดับเคลื่อนไหวน้อย: ปรับข้าวโอ๊ตเป็น 45 กรัม แทน 80 กรัม"
        )
    }

    func testRomanianRuntimeCampaignCopyIsLocalizedWithoutChangingCanonicalData() {
        let state = LanguageState.shared
        let previous = state.language
        defer { state.language = previous }
        state.language = .romanian

        let canonical = "3 campaign sessions are recorded as completed."
        XCTAssertEqual(state.text(canonical), "Sunt înregistrate 3 sesiuni de campanie finalizate.")
        XCTAssertEqual(
            state.text("Very active day: protein stays pinned; nut mix adjusts to 35 g."),
            "Nivel foarte activ: proteina rămâne fixă, iar mixul de nuci se ajustează la 35 g."
        )
        XCTAssertEqual(canonical, "3 campaign sessions are recorded as completed.")
    }

    func testEnglishReturnsCanonicalSharedValue() {
        let state = LanguageState.shared
        let previous = state.language
        defer { state.language = previous }
        state.language = .english

        XCTAssertEqual(state.text("Heart Bowl"), "Heart Bowl")
    }
}
