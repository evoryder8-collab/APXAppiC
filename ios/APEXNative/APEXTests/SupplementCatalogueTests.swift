import XCTest
@testable import APEX

/// The picker replaces typing a name in by hand, so it has to be faster than
/// that. A search that only matches exact prefixes is not.
final class SupplementCatalogueTests: XCTestCase {

    func testCatalogueLoadsFromTheBundle() {
        // A silent decode failure would leave an empty picker that still looks
        // like it is working.
        XCTAssertFalse(SupplementCatalogue.all.isEmpty, "the catalogue did not load")
        XCTAssertTrue(SupplementCatalogue.all.allSatisfy { !$0.doses.isEmpty },
                      "a supplement with no dose options cannot be added")
        XCTAssertTrue(SupplementCatalogue.all.allSatisfy { $0.summary.count > 40 },
                      "a summary too short to say anything useful")
    }

    func testFindsWhatWasMeantDespiteTheSpelling() {
        // Nobody spells these correctly, and the picker exists to save typing.
        let cases: [(String, String)] = [
            ("creatine", "creatine_monohydrate"),
            ("kreatine", "creatine_monohydrate"),
            ("creatin", "creatine_monohydrate"),
            ("ashwaganda", "ashwagandha"),
            ("ashwagandha", "ashwagandha"),
            ("citruline", "citrulline_malate"),
            ("alpha gpc", "alpha_gpc"),
            ("alphagpc", "alpha_gpc"),
            ("rodiola", "rhodiola"),
            ("taurin", "taurine"),
            ("carnitin", "l_carnitine"),
            ("glutamin", "l_glutamine"),
            ("nac", "nac"),
            ("inositol", "inositol"),
            ("magnezium", "magnesium_glycinate"),
        ]
        for (query, expected) in cases {
            let results = SupplementCatalogue.search(query)
            XCTAssertEqual(results.first?.id, expected,
                           "\"\(query)\" found \(results.first?.id ?? "nothing")")
        }
    }

    func testAbbreviationsAndAlternateNamesResolve() {
        XCTAssertEqual(SupplementCatalogue.search("fish oil").first?.id, "omega_3")
        XCTAssertEqual(SupplementCatalogue.search("d3").first?.id, "vitamin_d3")
        XCTAssertEqual(SupplementCatalogue.search("b12").first?.id, "vitamin_b12")
        XCTAssertEqual(SupplementCatalogue.search("turmeric").first?.id, "curcumin")
    }

    func testAnEmptyQueryStillOffersTheCatalogue() {
        XCTAssertFalse(SupplementCatalogue.search("").isEmpty,
                       "opening the picker should show something to browse")
    }

    func testNonsenseFindsNothingRatherThanSomethingWrong() {
        // Offering a confident wrong answer is worse than offering none.
        XCTAssertTrue(SupplementCatalogue.search("qwertyuiop").isEmpty)
    }

    func testEvidenceIsStatedIncludingWhenItIsAbsent() {
        // A catalogue that presents tribulus and creatine identically is not
        // being straight with the person reading it.
        let creatine = SupplementCatalogue.all.first { $0.id == "creatine_monohydrate" }
        let tribulus = SupplementCatalogue.all.first { $0.id == "tribulus" }
        XCTAssertEqual(creatine?.evidence, "strong")
        XCTAssertEqual(tribulus?.evidence, "insufficient")
        XCTAssertEqual(tribulus?.evidenceLabel, "Not supported by evidence")
        // And the honest ones say so in the summary rather than only in a label.
        XCTAssertTrue(tribulus?.summary.lowercased().contains("not to raise") ?? false)
    }

    func testDosesFormatInTheUnitTheyAreSoldIn() {
        guard let gpc = SupplementCatalogue.all.first(where: { $0.id == "alpha_gpc" }) else {
            return XCTFail("Alpha-GPC missing")
        }
        XCTAssertEqual(gpc.formattedDose(300), "300 mg")
        XCTAssertTrue(gpc.doses.contains(600), "the commonly sold 600 mg size is missing")

        guard let whey = SupplementCatalogue.all.first(where: { $0.id == "whey_protein" }) else {
            return XCTFail("Whey missing")
        }
        XCTAssertEqual(whey.formattedDose(30), "30 g")
    }
}
