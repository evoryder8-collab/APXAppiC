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
        XCTAssertGreaterThanOrEqual(document.pageCount, 3)
        let firstPage = try XCTUnwrap(document.page(at: 0)?.string)
        XCTAssertTrue(firstPage.contains("63 / 100"))
        XCTAssertTrue(firstPage.contains("2026-01-05"))
        XCTAssertFalse(firstPage.contains("99 / 100"))
        let extracted = try XCTUnwrap(document.string)
        XCTAssertTrue(extracted.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").contains("last word"))
        let charts = try XCTUnwrap(document.page(at: document.pageCount - 1)?.string)
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
        XCTAssertTrue(charts.contains(LanguageState.shared.text("One recorded session")))
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
        let page = try XCTUnwrap(document.page(at: 1))
        let text = try XCTUnwrap(page.string)
        let language = LanguageState.shared
        XCTAssertTrue(text.contains(language.text("Hip Thrust") + " · " + language.text("Lower body")))
        XCTAssertTrue(text.contains(language.text("Barbell Hip Thrust")))
        XCTAssertTrue(text.contains(language.text("Machine Hip Thrust")))
        XCTAssertTrue(text.contains("1.78 t"))
        XCTAssertTrue(text.contains("1.48 t"))
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
    func testEmptyAvatarPDFReportsMissingEvidence() throws {
        let pdf = AvatarReport(ownerID: user, displayName: "Sample", snapshots: [], partialScores: ["health": 51],
                               sessions: [], logs: [], unit: .kilograms).pdfData()
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        let text = try XCTUnwrap(document.string)
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertTrue(text.contains(LanguageState.shared.text("Building your baseline")))
        XCTAssertTrue(text.contains("51 / 100"))
        XCTAssertTrue(text.contains(LanguageState.shared.text("No exercises recorded yet.")))
        XCTAssertTrue(text.contains(LanguageState.shared.text("No loaded sessions recorded yet.")))
    }
}
