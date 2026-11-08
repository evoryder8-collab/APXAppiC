import ImageIO
import PDFKit
import XCTest
@testable import APEX

/*
 * The export is what an assessment reads, so it has to say what happened
 * accurately: which sessions, in the order they were performed, with the flags
 * that explain why a day looked the way it did.
 */
final class ExportReportTests: XCTestCase {
    private let user = UUID()
    private let programID = UUID()
    private let dayID = UUID()
    private let sessionID = UUID()

    func testLocalizedMassUnitsAndIncompleteVolume() {
        let english = Locale(identifier: "en_GB")
        XCTAssertEqual(LiftedMassComparison.formattedMass(1000, locale: english), "1 ton")
        XCTAssertEqual(LiftedMassComparison.formattedMass(1167.89, locale: english, partial: true), "at least 1.1678 tons")
        XCTAssertEqual(LiftedMassComparison.formattedMass(2e33, locale: english), "2 quettatons")
        XCTAssertEqual(LiftedMassComparison.formattedMass(2000, locale: Locale(identifier: "ja_JP"), partial: true), "2トン以上")
        XCTAssertEqual(LiftedMassComparison.formattedMass(20000, locale: Locale(identifier: "ro_RO")), "20 de tone")
    }

    private func data(
        completed: Bool = true,
        deload: Bool = false,
        events: [EventRecord] = [],
        logs: [WorkoutLog] = []
    ) -> DashboardData {
        var data = DashboardData()
        data.programs = [
            Program(id: programID, userID: user, slug: "main", name: "Main Phase", description: "")
        ]
        data.programDays = [
            ProgramDay(
                id: dayID, userID: user, programID: programID, weekday: 1, name: "Legs A",
                dayType: "legs_a", estimatedMinutes: 50, warmupNote: "", sortOrder: 0
            )
        ]
        data.workoutSessions = [
            WorkoutSession(
                id: sessionID, userID: user, date: "2026-01-05", programDayID: dayID,
                isLite: false, isDeload: deload, isEventRecovery: false, completed: completed,
                qualityScore: 0.92, startedAt: nil, completedAt: nil, notes: "Felt strong"
            )
        ]
        data.workoutLogs = logs
        data.events = events
        data.dailyLogs = [
            DailyLog(
                id: UUID(), userID: user, date: "2026-01-05", kcal: 2400, proteinG: 180,
                fatG: 70, carbsG: 250, waterL: 3.0, estimatedTDEE: nil, computedPAL: nil,
                activityMode: "quick", weightKG: nil
            )
        ]
        return data
    }

    private func log(_ name: String, set: Int, weight: Double?, reps: Int?, at: String) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), userID: user, sessionID: sessionID, exerciseID: nil, exerciseName: name,
            setNumber: set, weightKG: weight, reps: reps, rir: 2, skipped: false,
            overrideFlag: false, createdAt: at
        )
    }

    func testTheReportNamesItsRangeAndProgramme() {
        let report = ExportReport.build(data(), slug: "main", from: "2026-01-01", to: "2026-01-31")
        XCTAssertTrue(report.hasPrefix("# APEX training report: Main Phase"))
        XCTAssertTrue(report.contains("Range: 2026-01-01 to 2026-01-31"))
    }

    func testACompletedSessionCarriesItsQuality() {
        let report = ExportReport.build(data(), slug: "main", from: "2026-01-01", to: "2026-01-31")
        XCTAssertTrue(report.contains("- 2026-01-05: Legs A (Full, completed, quality 92%)"))
        XCTAssertTrue(report.contains("Notes: Felt strong"))
    }

    func testAPlannedSessionIsNotReportedAsDone() {
        let report = ExportReport.build(
            data(completed: false), slug: "main", from: "2026-01-01", to: "2026-01-31"
        )
        XCTAssertTrue(report.contains("planned only"))
        XCTAssertFalse(report.contains("quality"))
    }

    func testDeloadAndEventWindowsAreFlagged() {
        let event = EventRecord(
            id: UUID(), userID: user, name: "Shoot", type: "filming",
            startDate: "2026-01-08", endDate: "2026-01-09", notes: ""
        )
        let report = ExportReport.build(
            data(deload: true, events: [event]), slug: "main", from: "2026-01-01", to: "2026-01-31"
        )
        XCTAssertTrue(report.contains("DELOAD"))
        XCTAssertTrue(report.contains("event window"))
        XCTAssertTrue(report.contains("- Shoot (filming), 2026-01-08 to 2026-01-09"))
    }

    func testSetsAppearInTheOrderTheyWerePerformed() {
        let logs = [
            log("Squat", set: 1, weight: 100, reps: 5, at: "2026-01-05T10:10:00Z"),
            log("Warm-up Bike", set: 1, weight: nil, reps: 1, at: "2026-01-05T10:00:00Z"),
            log("Squat", set: 2, weight: 100, reps: 5, at: "2026-01-05T10:15:00Z"),
        ]
        let report = ExportReport.build(
            data(logs: logs), slug: "main", from: "2026-01-01", to: "2026-01-31"
        )
        guard let bike = report.range(of: "**Warm-up Bike**"),
              let squat = report.range(of: "**Squat**") else {
            return XCTFail("both movements should be listed")
        }
        /* The bike came first on the clock, so it comes first in the receipt. */
        XCTAssertTrue(bike.lowerBound < squat.lowerBound)
        XCTAssertTrue(report.contains("  - Set 1: 100 kg, 5 reps, RIR 2"))
        XCTAssertTrue(report.contains("bodyweight"))
    }

    func testDailyNutritionIsIncluded() {
        let report = ExportReport.build(data(), slug: "main", from: "2026-01-01", to: "2026-01-31")
        XCTAssertTrue(report.contains("- 2026-01-05: 2400 kcal, P 180 g, F 70 g, C 250 g, water 3 L"))
    }

    func testDatesOutsideTheRangeStayOut() {
        let report = ExportReport.build(data(), slug: "main", from: "2026-02-01", to: "2026-02-28")
        XCTAssertFalse(report.contains("2026-01-05"))
        XCTAssertTrue(report.contains("No closed-day meal verdicts were available in this range."))
    }

    @MainActor
    func testCoverPlacesLiftedVolumeAboveItsIllustrationAndSetsBelow() throws {
        let fixture = data(logs: (1...37).map { log("Squat", set: $0, weight: 100, reps: 10, at: "") })
        let pdf = AvatarReport.scoped(ownerID: user, data: fixture, partialScores: [:], period: .allTime,
                                     dates: "2026-01-05"..."2026-01-05", today: "2026-01-05").pdfData()
        let doc = try XCTUnwrap(PDFDocument(data: pdf))
        let page = try XCTUnwrap(doc.page(at: 0))
        let language = LanguageState.shared
        func bounds(_ text: String) throws -> CGRect {
            try XCTUnwrap(doc.findString(text, withOptions: []).first { $0.pages.first == page }).bounds(for: page)
        }
        let mass = try XCTUnwrap(LiftedMassComparison.caption(kilograms: 37000))
        let art = try XCTUnwrap(page.annotations.first {
            ($0.action as? PDFActionURL)?.url == mass.source && $0.bounds.height > 50 && $0.bounds.minX < 100
        }).bounds
        let value = try bounds(LiftedMassComparison.formattedMass(37000, locale: language.language.locale))
        XCTAssertGreaterThan(try bounds(language.text("Lifted volume")).minY, value.maxY - 2)
        XCTAssertGreaterThan(value.minY, art.maxY)
        XCTAssertLessThan(abs(value.minX - art.minX), 16)
        XCTAssertGreaterThan(art.minY, try bounds(language.text("Performed sets")).maxY)
        let attachment = XCTAttachment(data: pdf, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "Lifted volume cover.pdf"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testAvatarPDFPaginatesRankingsAndShowsRecordedLoadInTheChosenUnit() throws {
        let secondID = UUID()
        let second = WorkoutSession(
            id: secondID, userID: user, date: "2026-03-05", programDayID: dayID,
            isLite: false, isDeload: false, isEventRecovery: false, completed: true,
            qualityScore: 1, startedAt: nil, completedAt: nil, notes: ""
        )
        let repeated = WorkoutLog(
            id: UUID(), userID: user, sessionID: secondID, exerciseID: nil, exerciseName: "Bench Press",
            setNumber: 1, weightKG: 30, reps: 6, rir: nil, skipped: false, overrideFlag: false, createdAt: ""
        )
        let longName = String(repeating: "Custom training variation ", count: 8) + "last word"
        let once = (1...24).map { log("Accessory \($0)", set: 1, weight: nil, reps: 8, at: "") }
            + [log(longName, set: 1, weight: nil, reps: 8, at: "")]
        let recorded = [log("Bench Press", set: 1, weight: 20, reps: 5, at: ""),
                        log("Squat", set: 1, weight: 40, reps: 4, at: ""), repeated]
        let otherOwner = RPGSnapshot(id: UUID(), userID: UUID(), date: "2020-01-01", overall: 99,
                                     health: 99, joint: 99, flexibility: 99, endurance: 99,
                                     strength: 99, strengthUpper: 99, strengthLower: 99)
        let scores = [("2026-01-05", 45.0), ("2026-02-05", 60.0), ("2026-03-05", 63.0)].map { day, value in
            RPGSnapshot(id: UUID(), userID: user, date: day, overall: value, health: value, joint: value,
                        flexibility: value, endurance: value, strength: value, strengthUpper: value, strengthLower: value)
        }
        let pdf = AvatarReport(ownerID: user, displayName: "Sample", snapshots: scores + [otherOwner], partialScores: [:],
                               sessions: data().workoutSessions + [second], logs: once + recorded, unit: .pounds).pdfData()
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
        let scorePage = try XCTUnwrap(pages.first { $0.contains(LanguageState.shared.text("Avatar scores")) })
        XCTAssertTrue(scorePage.contains("63 / 100"))
        XCTAssertTrue(scorePage.contains("2026-01-05"))
        let extracted = try XCTUnwrap(document.string)
        XCTAssertFalse(extracted.contains("99 / 100"))
        XCTAssertTrue(extracted.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").contains("last word"))
        let charts = try XCTUnwrap(pages.first { $0.contains(LanguageState.shared.text("Strength progress")) })
        XCTAssertGreaterThan(pages.filter { $0.contains(LanguageState.shared.text("Most trained exercises")) }.count, 1)
        let localizedLatest = 66.1.formatted(.number.locale(LanguageState.shared.language.locale))
        XCTAssertTrue(charts.contains(localizedLatest + " lb"))
        XCTAssertTrue(charts.contains("+22 lb"))
        let axis = try XCTUnwrap(WorkoutChartCalendar(from: "2026-01-05", to: "2026-03-05"))
        XCTAssertEqual(axis.ticks.count, 5)
        let early = try XCTUnwrap(APEXDateMath.date(from: "2026-01-06"))
        XCTAssertLessThan(axis.position(early), 0.02)
        let middleDate = axis.label(axis.ticks[2], locale: LanguageState.shared.language.locale)
        XCTAssertTrue(charts.contains(middleDate), "The PDF must label dates between the first and latest set")
        XCTAssertTrue(charts.contains("6 " + LanguageState.shared.text("reps")))
        XCTAssertFalse(charts.contains("Accessory"))
        XCTAssertFalse(charts.contains(LanguageState.shared.text("Squat")))
        XCTAssertFalse(extracted.contains(LanguageState.shared.text("One recorded session")))
        let attachment = XCTAttachment(data: pdf, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "Avatar report.pdf"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testAvatarPDFRanksFamilyOnceWithItsDistinctSessionCountAndVariantBreakdown() throws {
        let sameDay = WorkoutSession(
            id: UUID(), userID: user, date: "2026-01-05", programDayID: dayID,
            isLite: false, isDeload: false, isEventRecovery: false, completed: true,
            qualityScore: 1, startedAt: nil, completedAt: nil, notes: ""
        )
        let rows = [
            log("Barbell Hip Thrust", set: 1, weight: 50, reps: 6, at: ""),
            log("Machine Hip Thrust", set: 1, weight: 90, reps: 8, at: ""),
            WorkoutLog(id: UUID(), userID: user, sessionID: sameDay.id, exerciseID: nil,
                       exerciseName: "Machine Hip Thrust", setNumber: 1, weightKG: 95, reps: 8, rir: nil,
                       movementID: "machine_hip_thrust", skipped: false, overrideFlag: false, createdAt: ""),
        ]
        let pdf = AvatarReport(ownerID: user, displayName: "Sample", snapshots: [], partialScores: [:],
                               sessions: data().workoutSessions + [sameDay], logs: rows, unit: .kilograms).pdfData()
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        let page = try XCTUnwrap((0..<document.pageCount).compactMap { document.page(at: $0) }.first {
            $0.string?.contains(LanguageState.shared.text("Most trained exercises")) == true
        })
        let text = try XCTUnwrap(page.string)
        let language = LanguageState.shared
        XCTAssertTrue(text.contains(language.text("Hip Thrust") + " · " + language.text("Lower body")))
        XCTAssertTrue(text.contains(language.text("Barbell Hip Thrust")))
        XCTAssertTrue(text.contains(language.text("Machine Hip Thrust")))
        XCTAssertTrue(text.contains("1.78 tons"))
        XCTAssertTrue(text.contains("1.48 tons"))
        XCTAssertTrue(text.contains("300 kg"))
        XCTAssertTrue(text.contains("80.9 kg"))
        let expectedRows = [
            (language.text("Hip Thrust") + " · " + language.text("Lower body"), 2, 22),
            (language.text("Machine Hip Thrust"), 2, 16),
            (language.text("Barbell Hip Thrust"), 1, 6),
        ]
        for (name, sessions, reps) in expectedRows {
            let title = try XCTUnwrap(document.findString(name, withOptions: .literal).first { $0.pages.first == page })
            let midY = title.bounds(for: page).midY
            let sessionCell = CGRect(x: 242, y: midY - 3, width: 62, height: 6)
            let repsCell = CGRect(x: 307, y: midY - 3, width: 74, height: 6)
            XCTAssertEqual(page.selection(for: sessionCell)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), String(sessions), name)
            XCTAssertEqual(page.selection(for: repsCell)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), String(reps), name)
        }
    }

    @MainActor
    func testObjectComparisonsPreferASingleThenWholeCopiesThenAMilestone() throws {
        let language = LanguageState.shared
        let previous = language.language
        defer { language.language = previous }
        language.language = .english

        let engine = try XCTUnwrap(LiftedMassComparison.caption(kilograms: 37_833))
        XCTAssertEqual(engine.caption, "About the weight of a fully loaded airport fire engine")
        let pianos = try XCTUnwrap(LiftedMassComparison.caption(kilograms: 708))
        XCTAssertEqual(pianos.caption, "Around 3x Upright pianos")
        XCTAssertEqual(LiftedMassComparison.caption(kilograms: 752)?.caption, "Around 4x Treadmills")
        XCTAssertTrue(pianos.fact?.contains("Yamaha") == true)
        XCTAssertEqual(pianos.artworkURL?.lastPathComponent, "upright-piano.webp")
        XCTAssertEqual(LiftedMassComparison.caption(kilograms: .leastNonzeroMagnitude)?.caption,
                       "Table tennis ball · Next milestone")
        XCTAssertEqual(LiftedMassComparison.caption(kilograms: .greatestFiniteMagnitude)?.caption,
                       "The Sun · Milestone passed")
        XCTAssertNil(LiftedMassComparison.caption(kilograms: 0))
        XCTAssertNil(LiftedMassComparison.caption(kilograms: .infinity))

        language.language = .german
        let localizedPianos = try XCTUnwrap(LiftedMassComparison.caption(kilograms: 708))
        XCTAssertTrue(localizedPianos.caption.hasSuffix(language.format("About %d of these", 3)))
        XCTAssertEqual(localizedPianos.source, pianos.source)
        XCTAssertEqual(localizedPianos.artworkURL, pianos.artworkURL)
    }

    func testEachObjectComparisonHasADecodableBundledIllustration() throws {
        struct ObjectArtwork: Decodable { let artwork: String }
        let catalog = try XCTUnwrap(Bundle.main.url(forResource: "lifted-mass-landmarks", withExtension: "json"))
        let objects = try JSONDecoder().decode([ObjectArtwork].self, from: Data(contentsOf: catalog))
        XCTAssertFalse(objects.isEmpty)
        XCTAssertEqual(Set(objects.map(\.artwork)).count, objects.count)
        for object in objects {
            try autoreleasepool {
                let url = try XCTUnwrap(Bundle.main.url(forResource: object.artwork, withExtension: nil,
                                                        subdirectory: "award-objects"), object.artwork)
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), object.artwork)
                let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), object.artwork)
                XCTAssertGreaterThan(image.width, 1, object.artwork)
                XCTAssertGreaterThan(image.height, 1, object.artwork)
            }
        }
    }

    @MainActor
    func testAvatarPDFChartsPushUpFamiliesAndRecordedUnilateralVolume() throws {
        let second = WorkoutSession(id: UUID(), userID: user, date: "2026-02-09", programDayID: dayID,
                                    isLite: false, isDeload: false, isEventRecovery: false, completed: true,
                                    qualityScore: 1, startedAt: nil, completedAt: nil, notes: "")
        let third = WorkoutSession(id: UUID(), userID: user, date: "2026-03-02", programDayID: dayID,
                                   isLite: false, isDeload: false, isEventRecovery: false, completed: true,
                                   qualityScore: 1, startedAt: nil, completedAt: nil, notes: "")
        func later(_ name: String, _ movement: String?, _ kg: Double?, _ reps: Int) -> WorkoutLog {
            WorkoutLog(id: UUID(), userID: user, sessionID: second.id, exerciseID: nil, exerciseName: name,
                       setNumber: 1, weightKG: kg, reps: reps, rir: nil, movementID: movement,
                       skipped: false, overrideFlag: false, createdAt: "")
        }
        let rows = [
            log("Strict Push-Up", set: 1, weight: nil, reps: 12, at: ""),
            log("Diamond or Close-Grip Push-Up", set: 2, weight: nil, reps: 8, at: ""),
            later("Incline Push-Up", "incline_push_up", nil, 25),
            log("Bulgarian Split Squat", set: 1, weight: 14, reps: 8, at: ""),
            later("Bulgarian Split Squat", "bulgarian_split_squat", 18, 10),
            log("Reverse Lunge", set: 1, weight: 10, reps: 14, at: ""),
            later("Reverse Lunge", "reverse_lunge", 12, 16),
        ] + (1...3).map { set in
            WorkoutLog(id: UUID(), userID: user, sessionID: third.id, exerciseID: nil, exerciseName: "Dumbbell Curl",
                       setNumber: set, weightKG: 3.5, reps: 8, rir: 2, skipped: false, overrideFlag: false, createdAt: "")
        }
        var fixture = data(logs: rows + [rows[0]])
        fixture.workoutSessions += [second, third]
        let profile = TrainingProfile90.summarize(ownerID: user, data: fixture, through: third.date)
        XCTAssertEqual(profile.classifiedWorkouts, 3)
        let pdf = AvatarReport(ownerID: user, displayName: "Alex Morgan", snapshots: [], partialScores: [:],
                               sessions: fixture.workoutSessions, logs: fixture.workoutLogs, unit: .kilograms,
                               trainingProfile: profile, bodyweightBySession: [sessionID: 60, second.id: 60]).pdfData()
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
        let language = LanguageState.shared
        let summary = try XCTUnwrap(pages.first)
        XCTAssertTrue(summary.contains(language.text(profile.athleteTitle)))
        XCTAssertTrue(summary.contains(language.text("All-time training totals")))
        let charts = pages.filter { $0.contains(language.text("Strength progress")) }.joined(separator: "\n")
        XCTAssertTrue(charts.contains(language.text("Strength progress")))
        XCTAssertTrue(charts.contains("Split Squat"))
        XCTAssertTrue(charts.contains("Bulgarian"))
        XCTAssertTrue(charts.contains("Reverse"))
        XCTAssertTrue(charts.contains(language.format("%d reps", 10) + " × 18 kg"))
        XCTAssertTrue(charts.contains(language.text("Working leg")))
        XCTAssertTrue(charts.contains(language.text("Front foot · estimated")))
        XCTAssertTrue(charts.contains("≈ 66 kg"))
        XCTAssertTrue(charts.contains(language.text("Body + load")))
        XCTAssertTrue(charts.contains(language.text("Added weight")))
        XCTAssertTrue(charts.contains(language.text("Before").uppercased(with: language.language.locale)))
        XCTAssertTrue(charts.contains(language.text("After").uppercased(with: language.language.locale)))
        XCTAssertFalse(charts.contains(language.text("Push-Up")))
        XCTAssertFalse(charts.contains(language.text("Dumbbell Curl")))
        for (reps, kg) in [(18, 292), (30, 332)] {
            XCTAssertTrue(charts.contains(language.text("Recorded reps") + " " + String(reps)))
            XCTAssertTrue(charts.contains(language.text("Lifted volume") + " " + String(kg) + " kg"))
        }
        let rankings = try XCTUnwrap(pages.first { $0.contains(language.text("Most trained exercises")) })
        XCTAssertTrue(rankings.contains(language.text("Most trained exercises")))
        XCTAssertTrue(rankings.contains(language.text("Push-Up")))
        XCTAssertTrue(rankings.contains(language.text("Dumbbell Curl")))
        for section in ["Reps per session", "Recorded volume per session", "Avatar scores"] {
            XCTAssertFalse(pages.contains { $0.contains(language.text(section)) })
        }
        XCTAssertTrue(summary.contains("708 kg"))
        XCTAssertTrue(summary.split(whereSeparator: { $0.isWhitespace }).contains("10"))
        XCTAssertTrue(summary.split(whereSeparator: { $0.isWhitespace }).contains("117"))
        let summaryText = summary.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let mass = try XCTUnwrap(LiftedMassComparison.caption(kilograms: 708))
        XCTAssertTrue(summaryText.contains(mass.caption))
        XCTAssertNotNil(mass.artworkURL)
        let summaryIndex = try XCTUnwrap(pages.firstIndex(of: summary))
        let page = try XCTUnwrap(document.page(at: summaryIndex)?.pageRef)
        var resources: CGPDFDictionaryRef?, objects: CGPDFDictionaryRef?
        guard let dictionary = page.dictionary,
              CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
              CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else {
            return XCTFail("The illustrated summary page must contain PDF drawing resources.")
        }
        var hasImage = false
        CGPDFDictionaryApplyBlock(objects, { _, value, _ in
            var stream: CGPDFStreamRef?, subtype: UnsafePointer<CChar>?
            if CGPDFObjectGetValue(value, .stream, &stream), let stream,
               let dictionary = CGPDFStreamGetDictionary(stream),
               CGPDFDictionaryGetName(dictionary, "Subtype", &subtype),
               let subtype, String(cString: subtype) == "Image" { hasImage = true }
            return !hasImage
        }, nil)
        XCTAssertTrue(hasImage, "The summary page must embed the selected object illustration.")
        XCTAssertTrue(summaryText.contains(try XCTUnwrap(mass.fact)))
        let hero = try XCTUnwrap(LiftedMassComparison.heroCaption(kilograms: 708))
        XCTAssertTrue(summaryText.contains(hero.caption))
        let linkURLs = (0..<document.pageCount).compactMap { document.page(at: $0) }.flatMap(\.annotations).compactMap { ($0.action as? PDFActionURL)?.url }
        XCTAssertTrue(linkURLs.contains(mass.source))
        XCTAssertTrue(linkURLs.contains(hero.source))
        let attachment = XCTAttachment(data: pdf, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "Avatar family progress.pdf"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testRecordedHipThrustLoadsSurviveLegacyAndCurrentReceiptNames() throws {
        let dateLoads: [(String, Double?)] = [("2026-08-07", nil), ("2026-08-14", 8), ("2026-11-06", 36)]
        let name = "B-Stance or Single-Leg Hip Thrust"
        var fixture = data()
        fixture.workoutSessions = []
        for (date, kg) in dateLoads {
            let session = WorkoutSession(id: UUID(), userID: user, date: date, programDayID: dayID, isLite: false,
                                         isDeload: false, isEventRecovery: false, completed: true, qualityScore: 1,
                                         startedAt: nil, completedAt: nil, notes: "")
            fixture.workoutSessions.append(session)
            fixture.workoutLogs += (1...(kg == nil ? 2 : 3)).map { index in
                WorkoutLog(id: UUID(), userID: user, sessionID: session.id, exerciseID: nil, exerciseName: name,
                           setNumber: index, weightKG: kg, reps: 10, rir: nil,
                           movementID: date == "2026-11-06" ? "b_stance_hip_thrust" : nil,
                           skipped: false, overrideFlag: false, createdAt: "")
            }
        }
        let history = StrengthProgress.exerciseHistory(ownerID: user, sessions: fixture.workoutSessions, logs: fixture.workoutLogs)
        let exercise = try XCTUnwrap(history.first)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(exercise.sessions.map { $0.heaviestSet?.kg }, [nil, 8, 36])
        XCTAssertEqual(exercise.points.map(\.topWeight), [8, 36])
        XCTAssertEqual(exercise.totals.recordedReps, 80)
        let report = AvatarReport.scoped(ownerID: user, data: fixture, partialScores: [:], period: .allTime,
                                        dates: "2026-08-07"..."2026-11-06", today: "2026-11-08")
        let pdf = report.pdfData()
        let text = try XCTUnwrap(PDFDocument(data: pdf)?.string)
        let language = LanguageState.shared
        XCTAssertTrue(text.contains(language.format("%d reps", 10) + " × 36 kg"))
        XCTAssertTrue(text.contains(language.text("Recorded reps") + " · " + language.format("%d reps", 20)))
        let sample = XCTAttachment(data: pdf, uniformTypeIdentifier: "com.adobe.pdf")
        sample.name = "Hip thrust receipt example.pdf"
        sample.lifetime = .keepAlways
        add(sample)
    }

    @MainActor
    func testWorkingLegPDFUsesLatestInRangeLoadAndDatedBodyweight() throws {
        var fixture = data()
        let language = LanguageState.shared
        let previous = language.language
        language.language = .english
        defer { language.language = previous }
        let rows = [("2026-02-01", 0.0), ("2026-03-03", 12), ("2026-03-10", 24),
                    ("2026-03-17", 20), ("2026-03-24", 20), ("2026-03-31", 18), ("2026-04-01", 200)]
        fixture.workoutSessions = rows.map { date, _ in
            WorkoutSession(id: UUID(), userID: user, date: date, programDayID: dayID, isLite: false, isDeload: false,
                           isEventRecovery: false, completed: true, qualityScore: 1, startedAt: date + "T10:00:00Z",
                           completedAt: nil, notes: "")
        }
        fixture.workoutLogs = zip(fixture.workoutSessions, rows).map { session, row in
            WorkoutLog(id: UUID(), userID: user, sessionID: session.id, exerciseID: nil, exerciseName: "Bulgarian Split Squat",
                       setNumber: 1, weightKG: row.1, reps: 8, rir: 2, movementID: "bulgarian_split_squat",
                       skipped: false, overrideFlag: false, createdAt: "")
        }
        fixture.accountCreation = .init(userID: user, date: try XCTUnwrap(APEXDateMath.date(from: "2026-01-30")))
        let weights = [("2026-01-31", 61.0), ("2026-02-28", 60.0), ("2026-03-10", 45), ("2026-03-16", 70), ("2026-03-31", 55)]
        fixture.healthMetrics = weights.map { date, kg in
            HealthMetric(id: UUID(), userID: user, date: date, weightKG: kg)
        } + [HealthMetric(id: UUID(), userID: UUID(), date: "2026-03-17", weightKG: 150)]
        let range = "2026-03-01"..."2026-03-31"
        func report() -> AvatarReport {
            AvatarReport.scoped(ownerID: user, data: fixture, partialScores: [:], period: .custom, dates: range, today: "2026-04-08")
        }
        let pdf = report().pdfData()
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        let page = try XCTUnwrap((0..<document.pageCount).compactMap { document.page(at: $0) }.first {
            $0.string?.contains("Working leg") == true
        })
        let text = try XCTUnwrap(page.string)
        XCTAssertTrue(text.contains("Best working load · 8 reps × 24 kg"))
        XCTAssertTrue(text.contains("≈ 62 kg"))
        XCTAssertTrue(text.contains("73 kg"))
        XCTAssertTrue(text.contains("0 kg"))
        XCTAssertTrue(text.contains("BEFORE") && text.contains(language.dateKey("2026-02-01")))
        XCTAssertTrue(text.contains("AFTER") && text.contains(language.dateKey("2026-03-31")))
        XCTAssertTrue(text.contains("PERSONAL RECORD") && text.contains("20 kg") && text.contains("90 kg"))
        XCTAssertTrue(text.contains("8 reps · " + language.dateKey("2026-03-17")))
        XCTAssertTrue(try XCTUnwrap(document.string).contains("Joined FITR MAX"))
        XCTAssertFalse(text.contains("200 kg"))
        let cover = try XCTUnwrap(document.page(at: 0))
        func coverY(_ label: String) throws -> CGFloat {
            let mark = try XCTUnwrap(document.findString(label, withOptions: .literal).first { $0.pages.first == cover }, label)
            return mark.bounds(for: cover).midY
        }
        let hero = try XCTUnwrap(LiftedMassComparison.heroCaption(kilograms: 752))
        XCTAssertGreaterThan(try coverY("Strength athlete"), try coverY("Training totals"))
        XCTAssertGreaterThan(try coverY("Training totals"), try coverY("Around 4x Treadmills"))
        XCTAssertGreaterThan(try coverY("Around 4x Treadmills"), try coverY(hero.caption))
        XCTAssertGreaterThan(try coverY(hero.caption), try coverY("Classified workouts"))
        let copy = try XCTUnwrap(document.string)
        for obsolete in ["Matched working load", "Median session-best", "Known external load", "Volume sums each"] {
            XCTAssertFalse(copy.contains(obsolete))
        }
        let attachment = XCTAttachment(data: pdf, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "Working leg before and after.pdf"
        attachment.lifetime = .keepAlways
        add(attachment)

        // No in-range bodyweight can be recovered from foreign or future measurements.
        fixture.healthMetrics.removeAll { $0.userID == user }
        fixture.healthMetrics.append(HealthMetric(id: UUID(), userID: user, date: "2026-04-01", weightKG: 90))
        let partial = try XCTUnwrap(PDFDocument(data: report().pdfData())?.string)
        XCTAssertTrue(partial.contains("Added weight"))
        XCTAssertFalse(partial.contains("Body + load"))
        XCTAssertFalse(partial.contains("Front foot · estimated"))
    }

    @MainActor
    func testSparseChartPrintsActualSingleEvenBelowTheSessionsHeaviestSet() throws {
        let reps = [log("Dumbbell Curl", set: 1, weight: 24, reps: 6, at: ""),
                    log("Dumbbell Curl", set: 2, weight: 21, reps: 1, at: "")]
        var fixture = data(logs: reps)
        fixture.accountCreation = .init(userID: UUID(), date: .distantPast)
        let report = AvatarReport.scoped(ownerID: user, data: fixture, partialScores: [:], period: .custom,
                                        dates: "2026-01-05"..."2026-01-05", today: "2026-01-07")
        XCTAssertNil(report.joinedDate)
        let text = try XCTUnwrap(PDFDocument(data: report.pdfData())?.string)
        XCTAssertTrue(text.contains(LanguageState.shared.text("Best single") + " · 21 kg"))
        XCTAssertFalse(text.contains(LanguageState.shared.text("Best single") + " · 24 kg"))
    }

    func testSameDaySplitSessionsFollowTheirActualStartTimeAcrossTimezoneOffsets() {
        var fixture = data()
        var morning = fixture.workoutSessions[0]
        morning.startedAt = "2026-01-05T12:00:00+03:00"
        let later = WorkoutSession(id: UUID(), userID: user, date: morning.date, programDayID: dayID,
            isLite: false, isDeload: false, isEventRecovery: false, completed: true, qualityScore: 1,
            startedAt: "2026-01-05T10:00:00Z", completedAt: nil, notes: "")
        fixture.workoutSessions = [later, morning]
        let earlySet = log("Bulgarian Split Squat", set: 1, weight: 0, reps: 10, at: "")
        let lateSet = WorkoutLog(id: UUID(), userID: user, sessionID: later.id, exerciseID: nil,
            exerciseName: earlySet.exerciseName, setNumber: 1, weightKG: 9, reps: 8, rir: nil,
            skipped: false, overrideFlag: false, createdAt: "")
        let history = StrengthProgress.exerciseHistory(ownerID: user, sessions: fixture.workoutSessions, logs: [lateSet, earlySet])
        XCTAssertEqual(history.first?.sessions.map(\.sessionID), [morning.id, later.id])
        XCTAssertEqual(history.first?.sessions.compactMap { $0.heaviestSet?.kg }, [0, 9])
    }

    func testAvatarReportCalendarRangesRejectInvalidDatesAndClampMonthEnds() {
        func bounds(_ preset: AvatarReportPeriod, _ today: String, _ from: String = "", _ to: String = "") -> ClosedRange<String>? {
            preset.resolve(today: today, earliest: "2023-03-17", customFrom: from, customTo: to)
        }
        XCTAssertEqual(bounds(.month, "2024-03-31"), "2024-03-01"..."2024-03-31")
        XCTAssertEqual(bounds(.quarter, "2026-11-08"), "2026-08-09"..."2026-11-08")
        XCTAssertEqual(bounds(.halfYear, "2026-11-08"), "2026-05-09"..."2026-11-08")
        XCTAssertEqual(bounds(.year, "2024-02-29"), "2023-03-01"..."2024-02-29")
        XCTAssertEqual(bounds(.allTime, "2026-11-08"), "2023-03-17"..."2026-11-08")
        XCTAssertEqual(bounds(.custom, "2026-11-08", "2026-10-01", "2026-10-01"), "2026-10-01"..."2026-10-01")
        XCTAssertNil(bounds(.custom, "2026-11-08", "2026-11-08", "2026-11-09"))
        XCTAssertNil(bounds(.custom, "2026-11-08", "2026-11-08", "2026-11-07"))
        XCTAssertNil(bounds(.custom, "2026-11-08", "2026-02-30", "2026-03-01"))
    }

    @MainActor
    func testAvatarCustomPDFScopesSessionsScoresAndTrainingProfile() throws {
        let squat = log("Squat", set: 1, weight: 40, reps: 4, at: "")
        var fixture = data(logs: [squat])
        let previousID = UUID()
        let outside = WorkoutSession(id: previousID, userID: user, date: "2025-12-31", programDayID: dayID,
                                 isLite: false, isDeload: false, isEventRecovery: false, completed: true,
                                 qualityScore: 1, startedAt: nil, completedAt: nil, notes: "")
        fixture.workoutSessions.append(outside)
        fixture.workoutLogs.append(WorkoutLog(id: UUID(), userID: user, sessionID: previousID, exerciseID: nil,
            exerciseName: "Outside-window exercise", setNumber: 1, weightKG: 80, reps: 10, rir: 2,
            skipped: false, overrideFlag: false, createdAt: ""))
        fixture.snapshots = [RPGSnapshot(id: UUID(), userID: user, date: outside.date, overall: 91, health: 91,
            joint: 91, flexibility: 91, endurance: 91, strength: 91, strengthUpper: 91, strengthLower: 91)]
        let dates = "2026-01-05"..."2026-01-11"
        let report = AvatarReport.scoped(ownerID: user, data: fixture, partialScores: ["health": 88],
                                         period: .custom, dates: dates, today: "2026-11-08")
        XCTAssertEqual(report.sessions.map(\.id), [sessionID])
        XCTAssertEqual(report.logs.map(\.id), [squat.id])
        XCTAssertTrue(report.snapshots.isEmpty)
        XCTAssertTrue(report.partialScores.isEmpty)
        let profile = try XCTUnwrap(report.trainingProfile)
        XCTAssertEqual(profile.from, dates.lowerBound)
        XCTAssertEqual(profile.to, dates.upperBound)
        XCTAssertEqual(profile.dayCount, 7)
        XCTAssertEqual(profile.laterStart, "2026-01-08")
        XCTAssertEqual(profile.classifiedWorkouts, 1)
        let extracted = try XCTUnwrap(PDFDocument(data: report.pdfData())?.string)
        for expected in ["Training totals", "Training profile"] {
            XCTAssertTrue(extracted.contains(LanguageState.shared.text(expected)))
        }
        XCTAssertTrue(extracted.contains("160 kg"))
        XCTAssertTrue(extracted.contains(LanguageState.shared.dateKey(dates.upperBound)))
        for excluded in ["All-time training totals", "90-day training profile", "Outside-window exercise", "91 / 100", "88 / 100"] {
            XCTAssertFalse(extracted.contains(LanguageState.shared.text(excluded)))
        }
    }

    @MainActor
    func testEmptyAvatarPDFReportsMissingEvidence() throws {
        let pdf = AvatarReport(ownerID: user, displayName: "Sample", snapshots: [], partialScores: ["health": 51],
                               sessions: [], logs: [], unit: .kilograms).pdfData()
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        let text = try XCTUnwrap(document.string)
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertTrue(text.contains("51 / 100"))
        for section in ["Most trained exercises", "Strength progress", "Overall Fitness Level", "All-time training totals"] {
            XCTAssertFalse(text.contains(LanguageState.shared.text(section)))
        }
        let empty = AvatarReport(ownerID: user, displayName: "Sample", snapshots: [], partialScores: [:],
                                 sessions: [], logs: [], unit: .kilograms)
        let baseline = try XCTUnwrap(PDFDocument(data: empty.pdfData()))
        XCTAssertEqual(baseline.pageCount, 1)
        XCTAssertTrue(try XCTUnwrap(baseline.string).contains(LanguageState.shared.text("Building your baseline")))
    }
}
