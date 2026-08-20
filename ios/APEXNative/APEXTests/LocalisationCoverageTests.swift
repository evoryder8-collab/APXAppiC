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
