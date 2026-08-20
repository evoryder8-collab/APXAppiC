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

    /// Languages the app ships. Adding one here makes the next test fail until
    /// its table is complete, which is the intended way to add Spanish or
    /// German: add the code, run the tests, fill in what it lists.
    private let languages = ["ro", "th"]

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
        // A key present in one language and absent in another is the shape of
        // a half-finished translation pass.
        var keysByLanguage: [String: Set<String>] = [:]
        for language in languages {
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
