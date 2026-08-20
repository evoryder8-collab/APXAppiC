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
    private let completeLanguages = ["ro", "th"]

    /// Languages still being filled in. They must have a table and must not
    /// contain a key nobody else has, but they are allowed to be short, because
    /// a missing key falls back to English rather than breaking anything. They
    /// graduate to the list above when their coverage reaches parity.
    private let inProgressLanguages = ["de", "de-CH", "it", "es", "ja", "pt"]

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
        for language in languages {
            guard let table = table(language) else { continue }
            let untouched = table.filter { key, value in
                key == value && key.count > 12 && key.contains(" ")
            }
            XCTAssertLessThan(untouched.count, 40,
                              "\(language) has \(untouched.count) values identical to their English")
        }
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
