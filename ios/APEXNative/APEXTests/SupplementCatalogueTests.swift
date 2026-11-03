import XCTest
@testable import APEX

/// The picker replaces typing a name in by hand, so it has to be faster than
/// that. A search that only matches exact prefixes is not.
final class SupplementCatalogueTests: XCTestCase {

    @MainActor
    func testArchivingDailySupplementPersistsAcrossDatesAndKeepsHistoryAndOwnerBoundary() async throws {
        let session = AppSession(developerSandboxRole: .coach)
        defer { session.invalidateDeveloperSandbox() }
        let operation = try XCTUnwrap(session.accountOperationLease())
        session.data = APEXDebugFixture.dashboard(userID: operation.ownerID)
        XCTAssertFalse(session.developerSandboxHasExternalDependencies)
        let supplement = try XCTUnwrap(session.activeSupplements.first)
        let originalCount = session.data.supplements.count
        let previousDose = SupplementLog(
            id: UUID(), userID: operation.ownerID, date: "2026-11-02",
            supplementID: supplement.id, checkedAt: "2026-11-02T07:00:00Z"
        )
        session.data.supplementLogs.append(previousDose)
        let previousLogs = session.data.supplementLogs

        try await session.archiveSupplement(supplement, operation: operation)

        XCTAssertEqual(session.data.supplements.count, originalCount)
        XCTAssertTrue(try XCTUnwrap(session.data.supplements.first { $0.id == supplement.id }).archived)
        XCTAssertEqual(session.data.supplementLogs, previousLogs)
        for offset in [0, 1] {
            session.browsingDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: offset, to: Date()))
            XCTAssertFalse(session.activeSupplements.contains { $0.id == supplement.id },
                           "Retirement changes the routine, not just one calendar date.")
        }

        // The stored row survives reopening as an archive, not a deleted record.
        let stored = try JSONEncoder().encode(session.data)
        session.data = try JSONDecoder().decode(DashboardData.self, from: stored)
        XCTAssertFalse(session.activeSupplements.contains { $0.id == supplement.id })
        XCTAssertEqual(session.data.supplementLogs, previousLogs)

        let foreign = Supplement(
            id: UUID(), userID: UUID(), name: "Other account's supplement", dose: "1 g",
            timing: "anytime", clockTime: nil, offsetMinutes: nil,
            groupLabel: "Daily", trainingDaysOnly: false, sortOrder: 0
        )
        session.data.supplements.append(foreign)
        do {
            try await session.archiveSupplement(foreign, operation: operation)
            XCTFail("A supplement owned by another account must not be changed.")
        } catch is CancellationError {
            // The production ownership guard must reject this mutation.
        }
        XCTAssertFalse(try XCTUnwrap(session.data.supplements.first { $0.id == foreign.id }).archived)
        XCTAssertEqual(session.data.supplementLogs, previousLogs)
    }

    func testSupplementLogOutboxPayloadPreservesOwnerAndDay() throws {
        let row = SupplementLog(id: UUID(), userID: UUID(), date: "2026-11-02",
            supplementID: UUID(), checkedAt: "2026-11-02T06:30:00Z")
        let operation = try OfflineOperation.upsert(row, table: "supplement_logs",
            onConflict: "user_id,date,supplement_id")
        let payload = try XCTUnwrap(operation.payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(SupplementLog.self, from: payload)

        XCTAssertEqual(restored, row)
        XCTAssertEqual(operation.table, "supplement_logs")
        XCTAssertEqual(operation.onConflict, "user_id,date,supplement_id")
    }

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
            ("ashwaganda", "ashwagandha_root"),
            ("ashwagandha", "ashwagandha_root"),
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

    func testBrowseOrderLeadsWithProteinThenCreatineBeforeAlphabeticalCatalogue() {
        let results = SupplementCatalogue.search("", limit: 200)

        XCTAssertEqual(Array(results.prefix(2).map(\.id)), ["whey_protein", "creatine_monohydrate"])
        XCTAssertEqual(
            results.dropFirst(2).map(\.name),
            results.dropFirst(2).map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        )
        XCTAssertEqual(Set(results.map(\.id)).count, results.count, "browse order must not duplicate the core entries")
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

extension SupplementCatalogueTests {

    func testTheNewCompoundsAreThereAndFindable() {
        let cases: [(String, String)] = [
            ("cla", "cla"),
            ("ginseng", "panax_ginseng"),
            ("gingseng", "panax_ginseng"),
            ("ginkgo", "ginkgo_biloba"),
            ("gingko", "ginkgo_biloba"),
            ("greens", "greens_powder"),
            ("powergreens", "greens_powder"),
            ("prebiotic", "inulin"),
            ("postbiotic", "butyrate"),
            ("boulardii", "saccharomyces_boulardii"),
            ("mct", "mct_oil"),
            ("nmn", "nmn"),
            ("spirulina", "spirulina"),
            ("yohimbine", "yohimbine"),
        ]
        for (query, expected) in cases {
            XCTAssertEqual(SupplementCatalogue.search(query).first?.id, expected,
                           "\"\(query)\" found \(SupplementCatalogue.search(query).first?.id ?? "nothing")")
        }
    }

    func testTheTwoAshwagandhaExtractsAreDistinct() {
        // They are different chemistry marketed for opposite effects, so
        // collapsing them into one row loses the only thing that separates
        // them. Named for what they are; the trade names only search.
        let root = SupplementCatalogue.all.first { $0.id == "ashwagandha_root" }
        let rootLeaf = SupplementCatalogue.all.first { $0.id == "ashwagandha_root_leaf" }
        XCTAssertNotNil(root)
        XCTAssertNotNil(rootLeaf)
        XCTAssertNotEqual(root?.timing, rootLeaf?.timing, "the two extracts are timed the same")
        XCTAssertEqual(SupplementCatalogue.search("ksm66").first?.id, "ashwagandha_root")
        XCTAssertEqual(SupplementCatalogue.search("sensoril").first?.id, "ashwagandha_root_leaf")
        // Neither name leads with a brand.
        XCTAssertFalse(root?.name.lowercased().contains("ksm") ?? true)
        XCTAssertFalse(rootLeaf?.name.lowercased().contains("sensoril") ?? true)
    }

    func testUnderEighteenLosesTheUntestedBotanicalsAndKeepsTheNutrients() {
        let adult = SupplementCatalogue.visible(forAge: 30).map(\.id)
        let teen = SupplementCatalogue.visible(forAge: 16).map(\.id)
        XCTAssertLessThan(teen.count, adult.count, "nothing was restricted at all")

        // Hormonal, interaction-heavy and liver-risk botanicals go.
        for id in ["ashwagandha_root", "ashwagandha_root_leaf", "ginkgo_biloba",
                   "st_johns_wort", "yohimbine", "dhea", "tribulus", "five_htp",
                   "green_tea_extract", "garcinia", "panax_ginseng"] {
            XCTAssertFalse(teen.contains(id), "\(id) is still offered to a sixteen year old")
        }
        // Food-equivalent nutrients stay: restricting these would be theatre.
        for id in ["creatine_monohydrate", "whey_protein", "vitamin_d3", "omega_3",
                   "magnesium_glycinate", "psyllium", "iron", "casein", "pea_protein"] {
            XCTAssertTrue(teen.contains(id), "\(id) was hidden from a sixteen year old for no reason")
        }
    }

    func testEveryRestrictedEntryExplainsWhy() {
        // Hiding something without a reason is indistinguishable from a bug,
        // and the reason is what makes it reviewable.
        for entry in SupplementCatalogue.all where entry.adultOnly == true {
            XCTAssertNotNil(entry.restriction, "\(entry.id) is restricted with no reason given")
            XCTAssertGreaterThan(entry.restriction?.count ?? 0, 20, entry.id)
        }
    }

    func testSearchRespectsAgeRatherThanFilteringAfterwards() {
        // A restricted supplement must not surface by name either, or the
        // gate is decorative.
        XCTAssertTrue(SupplementCatalogue.search("yohimbine", age: 16).isEmpty)
        XCTAssertFalse(SupplementCatalogue.search("yohimbine", age: 30).isEmpty)
        XCTAssertTrue(SupplementCatalogue.search("ashwagandha", age: 17).isEmpty)
    }

    func testCaffeineIsGuidedRatherThanHidden() {
        // Hiding caffeine from a sixteen year old would be pretending they
        // cannot buy a coffee. The guidance is what is useful.
        let teen = SupplementCatalogue.visible(forAge: 16).first { $0.id == "caffeine" }
        XCTAssertNotNil(teen, "caffeine was hidden rather than qualified")
        XCTAssertNotNil(teen?.youthNote)
        XCTAssertTrue(teen?.youthNote?.contains("100") ?? false)
    }
}

extension SupplementCatalogueTests {

    /// Every user-facing string in the catalogue has to resolve in both
    /// languages, or a Romanian or Thai user reads English in the middle of an
    /// otherwise translated screen.
    func testEverySupplementStringIsTranslated() {
        for language in ["ro", "th"] {
            guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                            subdirectory: nil, localization: language),
                  let table = NSDictionary(contentsOf: url) as? [String: String]
            else {
                XCTFail("no \(language) strings table")
                continue
            }
            var missing: [String] = []
            for entry in SupplementCatalogue.all {
                for text in [entry.name, entry.summary, entry.category,
                             entry.restriction, entry.femaleWarning, entry.youthNote].compactMap({ $0 }) {
                    if table[text] == nil { missing.append(text) }
                }
            }
            XCTAssertEqual(missing.count, 0,
                           "\(language) is missing \(missing.count): \(missing.prefix(3))")
        }
    }

    func testTranslationsAvoidEmDashes() {
        // Prose em dashes were asked to stay out of the interface.
        for language in ["ro", "th"] {
            guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                            subdirectory: nil, localization: language),
                  let table = NSDictionary(contentsOf: url) as? [String: String]
            else { continue }
            for entry in SupplementCatalogue.all {
                for key in [entry.summary, entry.restriction, entry.femaleWarning].compactMap({ $0 }) {
                    guard let translated = table[key] else { continue }
                    XCTAssertFalse(translated.contains("\u{2014}"),
                                   "\(language) translation of \(entry.id) contains an em dash")
                }
            }
        }
    }

    func testDosePresetsLeaveRoomForTheUsersOwn() {
        // Two ready-made sizes, because the third pill is the one that takes
        // whatever is printed on the tub the user actually bought.
        for entry in SupplementCatalogue.all {
            XCTAssertLessThanOrEqual(entry.presetDoses.count, 2, entry.id)
            XCTAssertGreaterThan(entry.presetDoses.count, 0, entry.id)
        }
    }

    func testWomenAreWarnedOnlyWhereThereIsAReason() {
        // Over-warning is its own failure: a caution on everything teaches
        // people to ignore the ones that matter.
        let warned = SupplementCatalogue.all.filter { $0.femaleWarning != nil }
        XCTAssertGreaterThan(warned.count, 5, "no sex-specific cautions at all")
        XCTAssertLessThan(warned.count, 25, "so many cautions that none of them read as important")

        for id in ["st_johns_wort", "dhea", "vitamin_a", "tribulus", "tongkat_ali"] {
            XCTAssertNotNil(SupplementCatalogue.all.first { $0.id == id }?.femaleWarning, id)
        }
        // Things women more often need more of, not less, carry no warning.
        for id in ["creatine_monohydrate", "iron", "whey_protein", "vitamin_d3", "folate"] {
            XCTAssertNil(SupplementCatalogue.all.first { $0.id == id }?.femaleWarning,
                         "\(id) warns women off something they may well need")
        }
        // And every warning says why rather than just flagging.
        for entry in warned {
            XCTAssertGreaterThan(entry.femaleWarning?.count ?? 0, 60, entry.id)
        }
    }
}
