import XCTest
@testable import APEX

/// Guards against the two ways a screen ends up half-translated.
///
/// The app looked partly untranslated for a long time and the tables were not
/// the problem: 301 strings were written as bare literals that never asked for
/// a translation at all, and most of them already had Romanian and Thai
/// sitting unused in the files. Adding a language would have made that worse,
/// because the new table would have been just as ignored.
///
/// So two rules, enforced here rather than remembered. Every user-facing
/// string must go through the lookup, and every key the lookup asks for must
/// exist in every language shipped.
final class LocalisationCoverageTests: XCTestCase {

    /// Languages held to full parity with each other. A key present in one and
    /// absent in another is the shape of a half-finished pass, so these fail
    /// the moment they diverge.
    private let completeLanguages = ["de", "de-CH", "it", "es", "pt", "ja", "ro", "th"]

    /// Kept explicit so a newly introduced locale starts behind the parity gate
    /// until its full and compact tables are complete.
    private let inProgressLanguages: [String] = []

    private var languages: [String] { completeLanguages + inProgressLanguages }

    private func table(_ language: String) -> [String: String]? {
        guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                        subdirectory: nil, localization: language)
        else { return nil }
        return NSDictionary(contentsOf: url) as? [String: String]
    }

    func testEveryLanguageHasATable() {
        for language in languages {
            XCTAssertNotNil(table(language), "no strings table for \(language)")
        }
    }

    func testTablesAreNotMissingKeysTheOthersHave() {
        var keysByLanguage: [String: Set<String>] = [:]
        for language in completeLanguages {
            guard let table = table(language) else { continue }
            keysByLanguage[language] = Set(table.keys)
        }
        guard let reference = keysByLanguage.values.max(by: { $0.count < $1.count }) else { return }
        for (language, keys) in keysByLanguage {
            let missing = reference.subtracting(keys)
            XCTAssertTrue(missing.isEmpty,
                          "\(language) is missing \(missing.count) keys, e.g. \(missing.prefix(3))")
        }
    }

    /// A key in a new table that exists nowhere else is a typo, and a typo here
    /// is invisible: the lookup simply falls through to English and the string
    /// stays English forever.
    func testInProgressTablesInventNoKeysOfTheirOwn() {
        /* The reference is the Romanian table plus the typed keys, whose
           English lives inline in Swift rather than in any table. A new
           language reaches those through the tables, so its file legitimately
           carries keys Romanian's file does not. */
        guard var reference = table("ro").map({ Set($0.keys) }) else {
            return XCTFail("no Romanian table to compare against")
        }
        reference.formUnion(LocalizedKey.allEnglishValues)
        for language in inProgressLanguages {
            guard let keys = table(language).map({ Set($0.keys) }) else { continue }
            let unknown = keys.subtracting(reference)
            XCTAssertTrue(
                unknown.isEmpty,
                "\(language) has \(unknown.count) keys no other language has, e.g. \(unknown.prefix(3))"
            )
        }
    }

    /// A translation must not carry script from an unrelated language.
    ///
    /// A Cyrillic fragment once ended up glued to the front of a Japanese
    /// string. It renders, it is not an error, and nobody who does not read
    /// Japanese would ever notice, which is precisely why a machine should be
    /// the one checking.
    func testTranslationsDoNotMixUnrelatedScripts() {
        let cyrillic = CharacterSet(charactersIn: "\u{0400}"..."\u{04FF}")
        let thaiRange = CharacterSet(charactersIn: "\u{0E00}"..."\u{0E7F}")
        for language in languages {
            guard let table = table(language) else { continue }
            for (key, value) in table {
                /* A key that already carries foreign script is a string about
                   languages, such as the list of language names, where every
                   script belongs on purpose. */
                if key.rangeOfCharacter(from: thaiRange) != nil { continue }
                XCTAssertNil(
                    value.rangeOfCharacter(from: cyrillic),
                    "\(language) has Cyrillic in \"\(key)\": \(value)"
                )
                if language != "th" {
                    XCTAssertNil(
                        value.rangeOfCharacter(from: thaiRange),
                        "\(language) has Thai script in \"\(key)\": \(value)"
                    )
                }
            }
        }
    }

    /// An English word must not be left stranded inside a non-Latin translation.
    ///
    /// Latin letters belong in Japanese and Thai all the time: product names,
    /// units, people. So the test is not whether Latin appears, but whether a
    /// Latin word appears that is not in the English being translated. "App
    /// Store" and "SkiErg" survive because the original says them; a Japanese
    /// question ending in "continuous" does not, because the original never
    /// contained that word and the sentence was simply left half written.
    func testNonLatinTranslationsDoNotStrandEnglishWords() {
        /* Names the app owns. A translator may introduce one where the English
           left the subject implicit, which Thai in particular often needs, so
           these are allowed even when the original does not say them. */
        let ownNames: Set<String> = ["apex", "orbit", "focus"]
        let words = try! NSRegularExpression(pattern: "[A-Za-z]{4,}")
        for language in ["ja", "th"] {
            guard let table = table(language) else { continue }
            for (key, value) in table where key != value {
                let source = key.lowercased()
                let range = NSRange(value.startIndex..., in: value)
                for match in words.matches(in: value, range: range) {
                    guard let found = Range(match.range, in: value) else { continue }
                    let word = String(value[found])
                    XCTAssertTrue(
                        source.contains(word.lowercased()) || ownNames.contains(word.lowercased()),
                        """
                        \(language) leaves the English word "\(word)" inside \
                        "\(key)", and the original never used it: \(value)
                        """
                    )
                }
            }
        }
    }

    /// A label shouted in English must stay shouted in translation.
    ///
    /// These are section headings and stat labels, and the capitals are what
    /// makes them read as headings rather than as sentences. A translation that
    /// quietly drops to sentence case looks like a different kind of element on
    /// the screen. Latin scripts only: Japanese and Thai have no letter case.
    /// Abbreviations that a translation may legitimately spell out in full.
    private static let acronyms: Set<String> = [
        "TDEE", "BMR", "EVOO", "RPE", "RIR", "PAL", "HRV", "KCAL", "REPS", "SEC",
    ]

    func testShoutedLabelsStayShouted() {
        for language in ["de", "de-CH", "it", "es", "pt", "ro"] {
            guard let table = table(language) else { continue }
            for (key, value) in table {
                let keyLetters = key.filter(\.isLetter)
                /* Four letters, so initialisms and units are not swept in. */
                guard keyLetters.count >= 4, keyLetters.allSatisfy(\.isUppercase) else { continue }
                /* Keys marked SHORT hold weekday abbreviations, where the
                   language decides the casing: Romanian writes "Mi", not "MI". */
                guard !key.contains("SHORT") else { continue }
                /* Acronyms are not shouted labels, they are abbreviations, and
                   a language may spell one out: TDEE properly becomes
                   "Gesamtumsatz" and EVOO "ulei de masline extravirgin".
                   Listed rather than guessed at, because no rule separates an
                   initialism from a capitalised word reliably. */
                guard !Self.acronyms.contains(key) else { continue }
                let valueLetters = value.filter(\.isLetter)
                guard !valueLetters.isEmpty else { continue }
                /* An acronym spelled out is a translation, not a casing slip:
                   EVOO properly becomes "ulei de masline extravirgin". */
                let keyWords = key.split(separator: " ").count
                let valueWords = value.split(separator: " ").count
                guard valueWords <= keyWords + 1 else { continue }
                XCTAssertTrue(
                    valueLetters.allSatisfy(\.isUppercase),
                    "\(language) lowercases the shouted label \"\(key)\": \(value)"
                )
            }
        }
    }

    /// A translated format string must take exactly the arguments the original does.
    ///
    /// This is the one class of translation error that is not merely ugly. The
    /// caller passes an Int where the format says %d; if a translation drops
    /// that placeholder the argument is ignored, and if it invents one the
    /// formatter reads memory that was never passed. Word order may move freely,
    /// so this compares the multiset of specifiers rather than the sequence.
    func testFormatStringsTakeTheSameArguments() {
        /* No space flag: "15% calorie" would otherwise read as a "% c"
           specifier, and a percentage written in prose is not a placeholder.
           Nothing in this app formats with the space flag. */
        let specifier = try! NSRegularExpression(
            pattern: "%(?:[-+#0]*)(?:[0-9]+)?(?:\\.[0-9]+)?[@dfsxXeEgGcup%]"
        )
        func specifiers(_ text: String) -> [String] {
            let range = NSRange(text.startIndex..., in: text)
            return specifier.matches(in: text, range: range)
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
                /* A literal percent consumes no argument. */
                .filter { $0 != "%%" }
                .sorted()
        }
        for language in languages {
            guard let table = table(language) else { continue }
            for (key, value) in table {
                let expected = specifiers(key)
                guard !expected.isEmpty else { continue }
                XCTAssertEqual(
                    specifiers(value), expected,
                    "\(language) changes the arguments of \"\(key)\": \(value)"
                )
            }
        }
    }

    /// A language may not be offered to users until its table is complete.
    ///
    /// This is the check that stops the readiness flag from being a claim. A
    /// language marked ready must actually have every key, because the person
    /// who suffers a half-finished translation is the one who reads it: they
    /// see a native sentence beside an English one and cannot tell an
    /// unfinished string from a broken app.
    func testNoLanguageIsOfferedBeforeItIsFinished() {
        guard let reference = table("ro").map({ Set($0.keys) }) else {
            return XCTFail("no Romanian table to compare against")
        }
        for language in AppLanguage.allCases where language.isReleaseReady {
            guard language != .english else { continue }
            guard let keys = table(language.rawValue).map({ Set($0.keys) }) else {
                return XCTFail("\(language.rawValue) is offered but has no table")
            }
            let missing = reference.subtracting(keys)
            XCTAssertTrue(
                missing.isEmpty,
                """
                \(language.rawValue) is marked release ready but is missing \
                \(missing.count) strings. Either finish it or set isReleaseReady \
                to false, because shipping it half done is worse for the people \
                who read it than shipping English.
                """
            )
        }
    }

    /// Records how far each language has got. Not a pass or fail on its own:
    /// it is here so the number is printed by the suite rather than being
    /// anybody's recollection.
    func testCoverageIsRecorded() {
        guard let reference = table("ro")?.count, reference > 0 else { return }
        for language in languages {
            let count = table(language)?.count ?? 0
            let percent = Int((Double(count) / Double(reference) * 100).rounded())
            print("localisation coverage \(language): \(count)/\(reference) (\(percent)%)")
        }
    }

    func testNothingIsTranslatedToItsOwnEnglish() {
        // A key whose value equals the key is an untranslated placeholder that
        // passes every other check while showing English on screen.
        // Exercise names are deliberately classified separately for every
        // market. An `english` classification is a sourced terminology choice,
        // not untranslated interface copy, so the stranded-copy guard must use
        // the committed exercise policy as its allowlist.
        let exerciseNames = Set(ExerciseCatalog.all.map(\.name))
        for language in languages {
            guard let table = table(language) else { continue }
            let untouched = table.filter { key, value in
                key == value
                    && key.count > 12
                    && key.contains(" ")
                    && !exerciseNames.contains(key)
            }
            XCTAssertLessThan(untouched.count, 40,
                              "\(language) has \(untouched.count) values identical to their English")
        }
    }

    func testEveryOfferedLanguageHasTheAuthoredCompactTable() throws {
        let languages = ["en", "de", "de-CH", "it", "es", "pt", "ja", "ro", "th"]
        let portalKeys = [
            "Fitness Plan",
            "Transition Phase",
            "Main Phase",
            "If you haven't trained in a long time.",
            "Fit enough to start the main journey.",
            "Return here after a long break to rebuild consistency, movement quality and training tolerance.",
            "Choose this when regular training feels manageable and you're ready to build strength, muscle and performance.",
        ]
        let expectedPortalValues: [String: [String]] = [
            "en": ["Fitness Plan", "Transition", "Main", "Back after a long break?", "Ready for the main phase.", "Rebuild your base after a break.", "Ready to build strength and muscle."],
            "de": ["Trainingsplan", "Übergang", "Hauptphase", "Nach längerer Pause", "Bereit für die Hauptphase", "Zurück zu Rhythmus und Technik", "Kraft und Muskeln aufbauen"],
            "de-CH": ["Trainingsplan", "Übergang", "Hauptphase", "Nach ere längere Pause", "Bereit für d Hauptphase", "Zrugg zu Rhythmus und Technik", "Chraft und Muskle ufbaue"],
            "it": ["Piano di allenamento", "Transizione", "Principale", "Rientro dopo una lunga pausa", "Pronto per la fase principale", "Ritrova la base dopo la pausa", "Forza e massa, si parte"],
            "es": ["Plan de entrenamiento", "Transición", "Principal", "Vuelves tras un parón largo", "Listo para la fase principal", "Recupera tu base tras el parón", "A por fuerza y músculo"],
            "pt": ["Plano de treino", "Transição", "Principal", "Regresso após uma pausa longa", "Pronto para a fase principal", "Recupera a base após a pausa", "Força e músculo a seguir"],
            "ja": ["トレーニングプラン", "移行期", "メイン", "ブランク明けはここから", "メイン開始の準備OK", "ブランク後の土台づくり", "筋力と筋肉を伸ばす"],
            "ro": ["Plan de antrenament", "Tranziție", "Principală", "Revii după o pauză lungă.", "Ești gata pentru etapa principală.", "Reia ritmul după o pauză lungă.", "Gata pentru forță și masă."],
            "th": ["แผนการฝึก", "ช่วงเปลี่ยนผ่าน", "ช่วงหลัก", "กลับมาฝึกหลังพักนาน", "พร้อมเริ่มช่วงหลัก", "เรียกพื้นฐานกลับมาหลังพักนาน", "พร้อมเพิ่มแรงและกล้ามเนื้อ"],
        ]
        var expectedKeys: Set<String>?

        for language in languages {
            guard let url = Bundle.main.url(
                forResource: "LocalizableShort",
                withExtension: "strings",
                subdirectory: nil,
                localization: language
            ) else {
                XCTFail("Missing compact table for \(language)")
                continue
            }
            let data = try Data(contentsOf: url)
            let table = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
            XCTAssertEqual(table?.count, 37, "Unexpected compact-label count for \(language)")
            XCTAssertFalse(table?.values.contains(where: { $0.isEmpty }) ?? true)
            let keys = Set(table?.keys.map { $0 } ?? [])
            XCTAssertTrue(
                Set(portalKeys).isSubset(of: keys),
                "Missing compact Fitness Plan copy for \(language)"
            )
            for (key, expected) in zip(portalKeys, expectedPortalValues[language] ?? []) {
                XCTAssertEqual(table?[key], expected, "Unexpected compact Fitness Plan copy for \(language): \(key)")
            }
            if let expectedKeys {
                XCTAssertEqual(keys, expectedKeys, "Compact keys drifted for \(language)")
            } else {
                expectedKeys = keys
            }
            if language == "de-CH" {
                XCTAssertFalse(table?.values.contains(where: { $0.contains("ß") }) ?? true)
            }
        }
    }

    func testEveryTranslatedLanguageHasAuthoredFullFitnessPlanCopy() {
        let keys = [
            "Fitness Plan",
            "If you haven't trained in a long time.",
            "Fit enough to start the main journey.",
            "Return here after a long break to rebuild consistency, movement quality and training tolerance.",
            "Choose this when regular training feels manageable and you're ready to build strength, muscle and performance.",
        ]
        let expectedValues: [String: [String]] = [
            "de": ["Trainingsplan", "Wenn du lange nicht trainiert hast.", "Deine Basis reicht für den Einstieg in die Hauptphase.", "Starte hier nach einer längeren Pause und finde zurück zu Rhythmus, sauberer Technik und Belastbarkeit.", "Wähle diese Phase, wenn regelmäßiges Training gut klappt und du Kraft, Muskeln und Leistung weiterentwickeln willst."],
            "de-CH": ["Trainingsplan", "Wenn du lang nüm trainiert hesch.", "Dini Basis längt für de Start i d Hauptphase.", "Fang nach ere längere Pause da aa und find zrugg zu Rhythmus, sauberer Technik und Belastbarkeit.", "Wähl die Phase, wenn regelmässigs Training guet klappt und du Chraft, Muskle und Leistig witerentwickle wotsch."],
            "it": ["Piano di allenamento", "Se non ti alleni da molto tempo.", "Hai la base per iniziare la fase principale.", "Riparti da qui dopo una lunga pausa per ritrovare costanza, tecnica e tolleranza all'allenamento.", "Scegli questa fase quando allenarti con regolarità ti risulta gestibile e sei pronto a sviluppare forza, massa muscolare e prestazione."],
            "es": ["Plan de entrenamiento", "Si llevas mucho tiempo sin entrenar.", "Tienes base para empezar la fase principal.", "Vuelve aquí tras un parón largo para recuperar constancia, técnica y tolerancia al entrenamiento.", "Elige esta fase cuando entrenar con regularidad ya te resulte llevadero y estés listo para ganar fuerza, músculo y rendimiento."],
            "pt": ["Plano de treino", "Se já não treinas há muito tempo.", "Tens base para começar a fase principal.", "Começa aqui depois de uma pausa longa para recuperares consistência, técnica e tolerância ao treino.", "Escolhe esta fase quando treinar com regularidade já for confortável e estiveres pronto para desenvolver força, músculo e desempenho."],
            "ja": ["トレーニングプラン", "しばらく運動から離れていた人向け", "メインフェーズを始められる体力がある人向け", "長いブランク明けはここから。習慣、フォーム、トレーニングに耐える力を取り戻します。", "継続して運動できる土台があり、筋力・筋肉・パフォーマンスを伸ばしたい人はこちら。"],
            "ro": ["Plan de antrenament", "Revii la antrenamente după o pauză lungă.", "Ai baza necesară pentru etapa principală.", "Revino aici după o pauză lungă ca să-ți refaci ritmul, tehnica și toleranța la efort.", "Alege etapa asta când te antrenezi deja constant și ești gata să crești în forță, masă musculară și performanță."],
            "th": ["แผนการฝึก", "กลับมาฝึกหลังหยุดไปนาน", "ฟิตพอที่จะเริ่มช่วงหลัก", "ถ้าหยุดฝึกไปนาน ให้เริ่มตรงนี้เพื่อเรียกความสม่ำเสมอ ฟอร์มการเคลื่อนไหว และความพร้อมรับการฝึกกลับมา", "เลือกช่วงนี้เมื่อฝึกเป็นประจำได้สบายแล้ว และพร้อมพัฒนาความแข็งแรง กล้ามเนื้อ และสมรรถนะ"],
        ]

        for language in completeLanguages {
            guard let table = table(language) else {
                XCTFail("Missing full table for \(language)")
                continue
            }
            for (key, expected) in zip(keys, expectedValues[language] ?? []) {
                XCTAssertEqual(table[key], expected, "Unexpected full Fitness Plan copy for \(language): \(key)")
            }
        }
    }

    @MainActor
    func testCompactLookupUsesTheSelectedLanguageAndFallsBackSafely() {
        let state = LanguageState.shared
        let original = state.language
        defer { state.language = original }

        state.language = .german
        XCTAssertEqual(state.shortText("Settings"), "Optionen")
        state.language = .japanese
        XCTAssertEqual(state.shortText("Exercises"), "種目")
        state.language = .thai
        XCTAssertEqual(state.shortText("History"), "ประวัติ")
        XCTAssertEqual(state.shortText("A label without a compact form"),
                       state.text("A label without a compact form"))
    }

    func testTranslationsAvoidProseEmDashes() {
        for language in languages {
            guard let table = table(language) else { continue }
            let offenders = table.filter { $0.value.contains("\u{2014}") }
            XCTAssertTrue(offenders.isEmpty,
                          "\(language) uses an em dash in \(offenders.count) strings")
        }
    }
}
