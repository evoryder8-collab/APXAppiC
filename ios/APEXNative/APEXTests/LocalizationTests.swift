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

    func testHydrationPresetNamesAreNaturalInEveryOfferedLanguage() {
        let state = LanguageState.shared
        let previous = state.language
        defer { state.language = previous }

        let expected: [AppLanguage: [String]] = [
            .german: ["Glas", "Flasche", "Kaffee", "Tee", "Saft", "Proteinshake"],
            .swissGerman: ["Glas", "Flasche", "Kaffee", "Tee", "Saft", "Proteinshake"],
            .italian: ["Bicchiere", "Bottiglia", "Caffè", "Tè", "Succo", "Frullato"],
            .spanish: ["Vaso", "Botella", "Café", "Té", "Zumo", "Batido"],
            .portuguese: ["Copo", "Garrafa", "Café", "Chá", "Sumo", "Batido"],
            .japanese: ["コップ", "ボトル", "コーヒー", "お茶", "ジュース", "プロテインシェイク"],
            .romanian: ["Pahar", "Sticlă", "Cafea", "Ceai", "Suc", "Shake proteic"],
            .thai: ["แก้ว", "ขวด", "กาแฟ", "ชา", "น้ำผลไม้", "โปรตีนเชค"],
        ]
        let canonical = HydrationLedger.defaultPresetTemplates.map(\.name)

        for (language, translations) in expected {
            state.language = language
            XCTAssertEqual(canonical.map(state.text), translations, "Bad hydration terms for \(language.rawValue)")
        }

        state.language = .romanian
        XCTAssertEqual(state.hydrationPresetName("Glass"), "Pahar")
        XCTAssertEqual(state.hydrationPresetName("Paharul meu mare"), "Paharul meu mare")
    }

    func testRomanianSessionBriefingUsesNaturalTrainingLanguage() {
        let state = LanguageState.shared
        let previous = state.language
        defer { state.language = previous }
        state.language = .romanian

        XCTAssertEqual(state.text("Worked today"), "Zone vizate azi")
        XCTAssertEqual(state.text("Also involved"), "Alți mușchi implicați")
        XCTAssertEqual(state.text("Why this shape"), "De ce este structurată așa")
        XCTAssertEqual(state.text("Range of motion"), "Mobilitate articulară")
        XCTAssertEqual(state.text("Mobility and reset"), "Mobilitate și detensionare")
        XCTAssertEqual(
            state.text("Range you can control is the range you keep. This works the hips and the upper back through positions that sitting takes away, holding them long enough for the nervous system to accept them."),
            "Controlul contează mai mult decât amplitudinea. Sesiunea mobilizează șoldurile și partea superioară a spatelui în poziții pe care statul prelungit pe scaun le limitează, fără să forțeze capătul mișcării."
        )
        XCTAssertEqual(
            state.text("Breathe out at the end of each position. Holding your breath keeps the tension you came to release."),
            "Expiră lent la capătul fiecărei mișcări și păstrează respirația relaxată. Dacă trebuie să-ți ții respirația, redu amplitudinea."
        )
    }

    func testEnglishReturnsCanonicalSharedValue() {
        let state = LanguageState.shared
        let previous = state.language
        defer { state.language = previous }
        state.language = .english

        XCTAssertEqual(state.text("Heart Bowl"), "Heart Bowl")
    }
}
