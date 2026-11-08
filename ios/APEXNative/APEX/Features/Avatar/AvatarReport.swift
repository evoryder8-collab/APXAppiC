import CoreTransferable
import CoreText
import UIKit
import UniformTypeIdentifiers

enum AvatarReportPeriod: String, CaseIterable, Identifiable {
    case month = "1 month", quarter = "3 months", halfYear = "6 months", year = "1 year"
    case allTime = "All time", custom = "Custom"
    var id: Self { self }

    func resolve(today: String, earliest: String, customFrom: String, customTo: String) -> ClosedRange<String>? {
        func valid(_ day: String) -> Bool {
            guard let date = APEXDateMath.date(from: day) else { return false }
            return APEXDateMath.key(from: date) == day
        }
        guard valid(today) else { return nil }
        switch self {
        case .custom:
            guard valid(customFrom), valid(customTo), customFrom <= customTo, customTo <= today else { return nil }
            return customFrom...customTo
        case .allTime:
            return (valid(earliest) ? min(earliest, today) : today)...today
        default:
            let months = self == .month ? 1 : self == .quarter ? 3 : self == .halfYear ? 6 : 12
            guard let end = APEXDateMath.date(from: today),
                  let prior = APEXDateMath.calendar.date(byAdding: .month, value: -months, to: end) else { return nil }
            let start = APEXDateMath.adding(days: 1, to: APEXDateMath.key(from: prior))
            return start...today
        }
    }
}

struct AvatarReport: Transferable {
    let ownerID: UUID
    let displayName: String
    let snapshots: [RPGSnapshot]
    let partialScores: [String: Double]
    let sessions: [WorkoutSession]
    let logs: [WorkoutLog]
    let unit: WeightUnit
    var exercises: [Exercise] = []
    var trainingProfile: TrainingProfile90? = nil
    var bodyweightBySession: [UUID: Double] = [:]
    var earlierFirst: [String: StrengthProgress.SessionTotals] = [:]
    var joinedDate: String?
    var period: AvatarReportPeriod = .allTime
    var reportDates: ClosedRange<String>? = nil

    static func earliestDate(in data: DashboardData, owner: UUID, today: String) -> String {
        let sessions = data.workoutSessions.filter { $0.userID == owner && $0.completed }
        let byID = Dictionary(sessions.map { ($0.id, $0.date) }, uniquingKeysWith: { first, _ in first })
        let imports = data.importedActivities.compactMap { row -> String? in
            guard row.userID == owner, row.hiddenAt == nil, row.durationMinutes > 0,
                  !ExternalWorkoutImport.isAPEXBundleIdentifier(row.sourceBundleIdentifier ?? "") else { return nil }
            if let linked = row.apexWorkoutSessionID { return byID[linked] }
            return row.date
        }
        let runs = data.orbitRuns.filter { $0.userID == owner && $0.status == "completed" }.map(\.localDate)
        let scores = data.snapshots.filter { $0.userID == owner }.map(\.date)
        return (sessions.map(\.date) + imports + runs + scores).filter { day in
            day <= today && APEXDateMath.date(from: day).map { APEXDateMath.key(from: $0) } == day
        }.min() ?? today
    }

    static func scoped(ownerID: UUID, data: DashboardData, partialScores: [String: Double],
                       period: AvatarReportPeriod, dates: ClosedRange<String>, today: String) -> Self {
        let sessions = data.workoutSessions.filter { $0.userID == ownerID && $0.completed && dates.contains($0.date) }
        let ids = Set(sessions.map(\.id))
        let earlier = data.workoutSessions.filter { $0.userID == ownerID && $0.completed && $0.date < dates.lowerBound }
        let previous = earlier.isEmpty ? [] : StrengthProgress.exerciseHistory(ownerID: ownerID, sessions: earlier,
            logs: data.workoutLogs, exercises: data.exercises)
        let first = Dictionary(uniqueKeysWithValues: previous.compactMap { item in item.sessions.first.map { (item.key, $0) } })
        let required = Set(first.values.map(\.sessionID))
        let weights = bodyweights(in: data, owner: ownerID, through: dates.upperBound,
                                  sessions: sessions + earlier.filter { required.contains($0.id) })
        let joined = data.accountCreation.flatMap { creation -> String? in
            let day = creation.date.apexDateKey
            return creation.userID == ownerID && day <= dates.upperBound ? day : nil
        }
        let profile = TrainingProfile90.summarize(ownerID: ownerID, data: data,
            from: period == .allTime ? nil : dates.lowerBound, through: dates.upperBound)
        return Self(ownerID: ownerID, displayName: data.profile?.userID == ownerID ? data.profile?.displayName ?? "" : "",
                    snapshots: data.snapshots.filter { $0.userID == ownerID && dates.contains($0.date) },
                    partialScores: period == .allTime && dates.upperBound == today ? partialScores : [:],
                    sessions: sessions, logs: data.workoutLogs.filter { $0.userID == ownerID && ids.contains($0.sessionID) },
                    unit: .current(data.settings?.userID == ownerID ? data.settings : nil),
                    exercises: data.exercises.filter { $0.userID == ownerID }, trainingProfile: profile,
                    bodyweightBySession: weights,
                    earlierFirst: first, joinedDate: joined, period: period, reportDates: dates)
    }

    private static func bodyweights(in data: DashboardData, owner: UUID, through end: String,
                                    sessions: [WorkoutSession]) -> [UUID: Double] {
        struct Observation {
            let date: String
            let kg: Double
            let priority: Int
            let time: Date?
            let tie: String
        }
        var observations: [Observation] = []
        func add(_ date: String, _ kg: Double?, priority: Int, time: Date? = nil, tie: String) {
            guard let kg, (10...500).contains(kg), date <= end, FBDate.validDate(date) != nil else { return }
            observations.append(Observation(date: date, kg: kg, priority: priority, time: time, tie: tie))
        }
        for row in data.healthMetrics where row.userID == owner {
            add(row.date, row.weightKG, priority: 2, tie: row.id.uuidString)
        }
        for row in data.dailyLogs where row.userID == owner {
            add(row.date, row.weightKG, priority: 1, tie: row.id.uuidString)
        }
        let evidence = (data.fitnessEvidence ?? []).filter { $0.userID == owner && $0.metric == .bodyMass && $0.unit == "kg" }
        let superseded = Set(evidence.compactMap(\.supersedesID))
        for row in evidence where !superseded.contains(row.id) {
            guard let time = ExternalWorkoutImport.parseTimestamp(row.measuredAt) else { continue }
            add(String(row.measuredAt.prefix(10)), row.value, priority: 0, time: time, tie: row.importedAt + row.id.uuidString)
        }
        observations.sort {
            ($0.date, $0.priority, $0.time ?? .distantPast, $0.tie) < ($1.date, $1.priority, $1.time ?? .distantPast, $1.tie)
        }
        var bySession: [UUID: Double] = [:]
        var dayStart = 0
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            while dayStart < observations.count && observations[dayStart].date < session.date { dayStart += 1 }
            let started = ExternalWorkoutImport.parseTimestamp(session.startedAt)
            let sameDay = observations[dayStart...].prefix { $0.date == session.date }.last { row in
                guard let time = row.time, let started else { return true }
                return time <= started
            }
            bySession[session.id] = sameDay?.kg ?? (dayStart > 0 ? observations[dayStart - 1].kg : nil)
        }
        return bySession
    }

    var fileName: String {
        let separators = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        let cleanName = displayName.components(separatedBy: separators).joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var name = ""
        for character in cleanName {
            guard name.utf8.count + String(character).utf8.count <= 200 else { break }
            name.append(character)
        }
        let date = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        return [name.isEmpty ? "Avatar" : name, date, AppBrand.name].joined(separator: " - ") + ".pdf"
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { report in
            await report.pdfData()
        }
        .suggestedFileName { $0.fileName }
    }

    @MainActor
    func pdfData() -> Data {
        let scores = snapshots.filter { $0.userID == ownerID }.sorted { $0.date < $1.date }
        let history = StrengthProgress.exerciseHistory(ownerID: ownerID, sessions: sessions, logs: logs, exercises: exercises)
        let families = StrengthProgress.rankedFamilies(history)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            let pages = Pages(context: context, report: self)
            if let trainingProfile, trainingProfile.classifiedWorkouts > 0 {
                pages.drawTrainingProfile(trainingProfile)
            }
            if !families.isEmpty { pages.drawLifetimeTotals(families) }
            if let trainingProfile, trainingProfile.classifiedWorkouts > 0 {
                pages.drawProfileSummary(trainingProfile)
            }
            if !families.isEmpty {
                pages.drawCharts(families)
                pages.drawRankings(families)
            }
            pages.drawScores(scores)
            if pages.page == 0 {
                pages.begin("Avatar report", subtitle: pages.language.text(period == .allTime ? "Building your baseline" : "No data for this period"))
            }
        }
    }

    @MainActor
    private final class Pages {
        let context: UIGraphicsPDFRendererContext
        let report: AvatarReport
        let language = LanguageState.shared
        let ink = UIColor(red: 0.06, green: 0.14, blue: 0.16, alpha: 1)
        let green = UIColor(red: 0.00, green: 0.42, blue: 0.34, alpha: 1)
        let muted = UIColor(white: 0.34, alpha: 1)
        let rule = UIColor(white: 0.86, alpha: 1)
        var page = 0
        var y: CGFloat = 0

        init(context: UIGraphicsPDFRendererContext, report: AvatarReport) {
            self.context = context
            self.report = report
        }

        func beginPage() {
            context.beginPage()
            page += 1
            label(AppBrand.name, 38, 32, 200, size: 13, weight: .heavy, color: green)
            label(report.displayName, 260, 32, 314, size: 12, alignment: .right)
            line(38, 61, 574, 61, color: ink)
            line(38, 748, 574, 748, color: rule)
            let footer = report.reportDates.map {
                language.text("Avatar report") + "   ·   " + language.text(report.period.rawValue) + "   ·   "
                    + language.dateKey($0.lowerBound) + " – " + language.dateKey($0.upperBound)
            } ?? language.text("Avatar report")
            label(footer, 38, 758, 462, size: 10, color: muted)
            label(String(page), 508, 758, 66, size: 10, alignment: .right)
            y = 83
        }

        func begin(_ section: String, subtitle: String) {
            beginPage()
            label(language.text(section), 38, y, 536, size: 30, weight: .bold)
            y += 43
            for part in wrapped(subtitle, width: 536, size: 12) where !part.isEmpty {
                label(part, 38, y, 536, size: 12, color: muted)
                y += 17
            }
            y += 13
        }

        func drawScores(_ rows: [RPGSnapshot]) {
            let datedRows = rows.compactMap { row in
                APEXDateMath.date(from: row.date).map { (row: row, time: $0.timeIntervalSinceReferenceDate) }
            }
            let start = datedRows.first?.time ?? 0
            let span = (datedRows.last?.time ?? start) - start
            let metrics: [(String, String, KeyPath<RPGSnapshot, Double>)] = [
                ("overall", "Overall Fitness Level", \.overall), ("health", "Health", \.health),
                ("joint", "Joint Health Balance", \.joint), ("flexibility", "Body Flexibility", \.flexibility),
                ("endurance", "Endurance & VO₂ max", \.endurance), ("strength", "Strength", \.strength),
                ("upper", "Upper Body Strength", \.strengthUpper), ("lower", "Lower Body Strength", \.strengthLower),
            ]
            let recorded = metrics.compactMap { key, title, path -> (String, KeyPath<RPGSnapshot, Double>, Double)? in
                guard let value = rows.last?[keyPath: path] ?? report.partialScores[key], value.isFinite else { return nil }
                return (title, path, value)
            }
            guard !recorded.isEmpty else { return }
            let dates = [datedRows.first?.row.date, datedRows.last?.row.date].compactMap { $0 }
            let subtitle = dates.first == dates.last ? (dates.first ?? "") : dates.joined(separator: " – ")
            begin("Avatar scores", subtitle: subtitle)
            for (index, metric) in recorded.enumerated() {
                let (title, path, value) = metric
                let x: CGFloat = index.isMultiple(of: 2) ? 38 : 315
                let top = y + CGFloat(index / 2) * 139
                let card = CGRect(x: x, y: top, width: 259, height: 187)
                UIColor(white: 0.965, alpha: 1).setFill()
                UIBezierPath(roundedRect: card, cornerRadius: 10).fill()
                label(language.text(title), x + 13, top + 12, 233, size: 13, weight: .semibold)
                label(number(value) + " / 100", x + 13, top + 32, 233, size: 22, weight: .bold)
                let bounds = CGRect(x: x + 14, y: top + 68, width: 231, height: 36)
                let points = datedRows.compactMap { row, time -> CGPoint? in
                    guard row[keyPath: path].isFinite else { return nil }
                    let fraction = span > 0 ? (time - start) / span : 0.5
                    return CGPoint(x: bounds.minX + fraction * bounds.width,
                                   y: bounds.maxY - min(100, max(0, row[keyPath: path])) / 100 * bounds.height)
                }
                if points.count >= 2 {
                    line(bounds.minX, bounds.maxY, bounds.maxX, bounds.maxY, color: rule)
                    trace(points)
                }
            }
        }

        func drawTrainingProfile(_ profile: TrainingProfile90) {
            beginPage()
            let top = y
            let title = wrapped(language.text(profile.athleteTitle), width: 492, size: 32, weight: .bold)
            let height = 68 + CGFloat(title.count) * 39
            ink.setFill()
            UIBezierPath(roundedRect: CGRect(x: 38, y: top, width: 536, height: height), cornerRadius: 15).fill()
            let mint = UIColor(red: 0.68, green: 0.93, blue: 0.82, alpha: 1)
            label(language.text(report.period == .allTime ? "90-day training profile" : "Training profile"), 58, top + 15, 496, size: 12, weight: .semibold, color: mint)
            y = top + 32
            for part in title {
                label(part, 58, y, 496, size: 32, weight: .bold, color: .white)
                y += 39
            }
            label(language.dateKey(profile.from) + " – " + language.dateKey(profile.to),
                  58, y + 3, 496, size: 12, color: mint)
            y = top + height + 16
        }

        func drawProfileSummary(_ profile: TrainingProfile90) {
            let metrics = profile.metrics(language: language).filter {
                ($0.value != "0" || $0.key == "Workouts per week") && $0.key != "Recent median reps per resistance session"
            }
            let summary = metrics.map { language.text($0.key) + " " + $0.value }.joined(separator: "   ·   ")
            y += 8
            paragraph(summary, size: 12, color: muted)
        }

        private func paragraph(_ text: String, size: CGFloat, color: UIColor? = nil) {
            for part in wrapped(text, width: 536, size: size) {
                label(part, 38, y, 536, size: size, color: color)
                y += size + 5
            }
        }

        func volume(_ kg: Double, partial: Bool = false) -> String {
            LiftedMassComparison.formattedMass(kg, locale: language.language.locale, partial: partial)
        }

        func drawLifetimeTotals(_ rows: [StrengthProgress.RankedFamily]) {
            let totals = rows.reduce(into: StrengthProgress.LifetimeTotals()) { $0.add($1.totals) }
            if page == 0 || y > 420 { beginPage() }
            label(language.text(report.period == .allTime ? "All-time training totals" : "Training totals"), 38, y, 536, size: 21, weight: .bold)
            y += 35
            if let kg = totals.liftedVolumeKG, let total = liftedVolume(totals) {
                let top = y
                label(language.text("Lifted volume"), 52, y, 522, size: 18, weight: .bold)
                label(total, 52, y + 24, 522, size: 34, weight: .bold, color: green)
                y += 72
                drawComparisons(object: LiftedMassComparison.caption(kilograms: kg),
                                hero: LiftedMassComparison.heroCaption(kilograms: kg))
                line(39, top, 39, y - 8, color: green)
                y += 10
            }
            let metrics = [("Performed sets", String(totals.sets)), ("Recorded reps", recordedReps(totals))]
            for (index, metric) in metrics.enumerated() {
                guard let value = metric.1 else { continue }
                let x = 38 + CGFloat(index) * 274
                label(language.text(metric.0), x, y, 260, size: 13, weight: .semibold)
                label(value, x, y + 19, 260, size: 19, weight: .bold)
            }
            y += 50
            if totals.missingVolume || totals.missingReps {
                paragraph("* " + language.text("Incomplete records"), size: 10, color: muted)
            }
        }

        private func drawComparisons(object: LiftedMassComparison.Comparison?, hero: LiftedMassComparison.Comparison?) {
            guard object != nil || hero != nil else { return }
            let image = object?.artworkURL.flatMap { UIImage(contentsOfFile: $0.path) }
            let textX: CGFloat = image == nil ? 52 : 190
            let width = 574 - textX
            let start = y
            func linked(_ text: String, to source: URL, size: CGFloat, weight: UIFont.Weight, color: UIColor) {
                let top = y
                for part in wrapped(text, width: width, size: size, weight: weight) {
                    label(part, textX, y, width, size: size, weight: weight, color: color)
                    y += size + 4
                }
                context.setURL(source, for: context.cgContext.convertToDeviceSpace(CGRect(x: textX, y: top, width: width, height: y - top)))
            }
            if let object {
                linked(object.caption, to: object.source, size: 13, weight: .semibold, color: green)
                if let fact = object.fact {
                    y += 3
                    linked(fact, to: object.factSource ?? object.source, size: 11, weight: .regular, color: muted)
                }
            }
            if let hero {
                if object != nil { y += 7 }
                linked(hero.caption, to: hero.source, size: 12, weight: .medium, color: green)
            }
            if let image, let object {
                let side: CGFloat = 121
                let height = max(side, y - start)
                let scale = min(side / image.size.width, side / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let frame = CGRect(x: 52 + (side - size.width) / 2, y: start + (height - size.height) / 2,
                                   width: size.width, height: size.height)
                image.draw(in: frame)
                context.setURL(object.source, for: context.cgContext.convertToDeviceSpace(frame))
                y = start + height
            }
            y += 12
        }

        func drawRankings(_ rows: [StrengthProgress.RankedFamily]) {
            let columns: [(title: String, x: CGFloat, width: CGFloat)] = [
                ("Exercise", 38, 201), ("Sessions", 242, 62), ("Recorded reps", 307, 74),
                ("Load per rep", 384, 81), ("Lifted volume", 468, 106),
            ]
            func heading() {
                begin("Most trained exercises", subtitle: language.text("Each completed workout counts once per exercise family."))
                if rows.contains(where: { $0.totals.missingVolume || $0.totals.missingReps }) {
                    paragraph("* " + language.text("Incomplete records"), size: 10, color: muted)
                    y += 6
                }
                var height: CGFloat = 0
                for (i, column) in columns.enumerated() {
                    let lines = wrapped(language.text(column.title), width: column.width - 3, size: 10, weight: .bold)
                    for (j, part) in lines.enumerated() {
                        label(part, column.x, y + 13 * CGFloat(j), column.width, size: 10, weight: .bold,
                              color: muted, alignment: i == 0 ? .left : .right)
                    }
                    height = max(height, CGFloat(lines.count) * 13)
                }
                y += height + 6
            }

            func row(_ title: String, sessions: Int, totals: StrengthProgress.LifetimeTotals, variant: Bool) {
                let size: CGFloat = variant ? 10 : 12
                let indent: CGFloat = variant ? 12 : 0
                let fontWeight: UIFont.Weight = variant ? .regular : .semibold
                let average = totals.averageLoadKG.map { weight($0) + (totals.missingVolume ? "*" : "") }
                let values = [title, String(sessions), recordedReps(totals) ?? "", average ?? "", liftedVolume(totals) ?? ""]
                let cells = zip(columns, values).enumerated().map { i, cell in
                    wrapped(cell.1, width: cell.0.width - (i == 0 ? indent : 0) - 3, size: size, weight: fontWeight)
                }
                let lineCount = cells.map(\.count).max() ?? 1
                if y + min(500, CGFloat(lineCount) * (size + 3) + 8) > 730 { heading() }
                if !variant { line(38, y, 574, y, color: rule) }
                for rowIndex in 0..<lineCount {
                    if y + size + 6 > 730 { heading() }
                    for (i, cell) in cells.enumerated() where rowIndex < cell.count {
                        let inset = i == 0 ? indent : 0
                        label(cell[rowIndex], columns[i].x + inset, y + 3, columns[i].width - inset, size: size,
                              weight: fontWeight, color: variant ? muted : ink, alignment: i == 0 ? .left : .right)
                    }
                    y += size + 3
                }
                y += variant ? 3 : 6
            }

            heading()
            for family in rows {
                row(language.text(family.name) + " · " + language.text(family.region.rawValue),
                    sessions: family.sessionCount, totals: family.totals, variant: false)
                if family.showsVariants {
                    for variant in family.variants {
                        row(language.text(variant.name), sessions: variant.sessionCount, totals: variant.totals, variant: true)
                    }
                }
            }
        }

        private func recordedReps(_ totals: StrengthProgress.LifetimeTotals) -> String? {
            totals.recordedReps.map { number(Double($0)) + (totals.missingReps ? "*" : "") }
        }

        private func liftedVolume(_ totals: StrengthProgress.LifetimeTotals) -> String? {
            totals.liftedVolumeKG.map { volume($0, partial: totals.missingVolume) }
        }

        private struct ChartPoint {
            let sessionID: UUID
            let date: Date
            let value: Double
            let reps: Int?

            init?(_ point: StrengthProgress.Point) {
                guard let date = APEXDateMath.date(from: point.date), point.topWeight.isFinite, point.topWeight > 0 else { return nil }
                sessionID = point.sessionID
                self.date = date
                value = point.topWeight
                reps = point.topReps
            }
        }

        func drawCharts(_ families: [StrengthProgress.RankedFamily]) {
            var firstInSection = true
            for family in families {
                for variant in family.variants {
                    let points = variant.points.compactMap(ChartPoint.init)
                    let panel = legPanel(variant)
                    let best = variant.sessions.filter { $0.bestSingleKG != nil }
                        .max { ($0.bestSingleKG ?? 0) < ($1.bestSingleKG ?? 0) }
                    let single: String? = best.flatMap { row in
                        row.bestSingleKG.map { [language.text("Best single"), weight($0), language.dateKey(row.date)].joined(separator: " · ") }
                    }
                    if points.count >= 2 {
                        drawChart(variant, points: points, panel: panel, single: single, firstInSection: firstInSection)
                    } else if panel != nil || single != nil {
                        if firstInSection || y + 75 + (panel?.height ?? 0) > 730 {
                            begin("Strength progress", subtitle: "")
                        }
                        paragraph(language.text(variant.name), size: 17)
                        if let single { paragraph(single, size: 11, color: green) }
                        if let panel { drawLegPanel(panel, exercise: variant.name) }
                        y += 12
                    } else { continue }
                    firstInSection = false
                }
            }
        }

        private enum LegSupport: String, Decodable { case rearFootElevated, singleSupport, sharedSupport, externalOnly }

        private static let legGuide: [String: LegSupport] = {
            guard let url = Bundle.main.url(forResource: "unilateral-load-guide", withExtension: "json"),
                  let bytes = try? Data(contentsOf: url) else { return [:] }
            return (try? JSONDecoder().decode([String: LegSupport].self, from: bytes)) ?? [:]
        }()

        private struct LegPanel {
            struct Entry {
                let date: String
                let load: String
                let combined: String?
                let estimate: String?
                let recordedReps: String?
            }
            let movement: String
            let before: Entry
            let after: Entry
            let estimateLabel: String
            struct Record {
                let added: String
                let combined: String?
                let performance: String
            }
            let record: Record?
            var height: CGFloat { record == nil ? 250 : 310 }
        }

        private func legPanel(_ variant: StrengthProgress.ExerciseHistory) -> LegPanel? {
            let id = variant.key.hasPrefix("movement:") ? String(variant.key.dropFirst(9)) : ExerciseCatalog.movementID(matchingName: variant.name)
            guard let id, var support = Self.legGuide[id], let earliest = report.earlierFirst[variant.key] ?? variant.sessions.first,
                  let latest = variant.sessions.last else { return nil }
            let words = Set(variant.name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            if !words.isDisjoint(with: ["or", "assisted", "supported", "machine", "smith", "cable", "band"]) { support = .externalOnly }
            func combined(_ row: StrengthProgress.SessionTotals) -> Double? {
                guard support != .externalOnly, let kg = row.heaviestSet?.kg,
                      let body = report.bodyweightBySession[row.sessionID] else { return nil }
                return body + kg
            }
            func entry(_ row: StrengthProgress.SessionTotals) -> LegPanel.Entry {
                let total = combined(row)
                let estimate: String? = total.flatMap { all in
                    guard support == .rearFootElevated || support == .singleSupport else { return nil }
                    let units = report.unit.value(fromKilograms: all * (support == .rearFootElevated ? 0.8436 : 1))
                    return "≈ " + number(units.rounded()) + " " + report.unit.suffix
                }
                return .init(date: language.dateKey(row.date), load: row.heaviestSet.map { weight($0.kg) } ?? language.text("Not recorded"),
                             combined: total.map(weight), estimate: estimate,
                             recordedReps: row.heaviestSet == nil ? row.totals.recordedReps.map { language.format("%d reps", $0) } : nil)
            }
            let eligible = variant.sessions.filter { $0.heaviestSet != nil }
            let withBody = eligible.filter { combined($0) != nil }
            let useBody = !withBody.isEmpty
            let peak = (useBody ? withBody : eligible).max {
                let lhs = (useBody ? combined($0) : $0.heaviestSet?.kg) ?? 0
                let rhs = (useBody ? combined($1) : $1.heaviestSet?.kg) ?? 0
                return (lhs, $0.heaviestSet?.reps ?? 0) < (rhs, $1.heaviestSet?.reps ?? 0)
            }
            let record = peak.flatMap { row in
                row.heaviestSet.map { set in
                    LegPanel.Record(added: weight(set.kg), combined: combined(row).map(weight),
                                    performance: language.format("%d reps", set.reps) + " · " + language.dateKey(row.date))
                }
            }
            return LegPanel(movement: id, before: entry(earliest), after: entry(latest),
                            estimateLabel: language.text(support == .rearFootElevated ? "Front foot · estimated" : "Standing foot · estimated"),
                            record: record)
        }

        private func drawLegPanel(_ panel: LegPanel, exercise: String) {
            if y + 8 + panel.height > 742 { begin(exercise, subtitle: "") }
            let top = y + 8
            let frame = CGRect(x: 38, y: top, width: 536, height: panel.height)
            UIColor(red: 0.94, green: 0.97, blue: 0.96, alpha: 1).setFill()
            UIBezierPath(roundedRect: frame, cornerRadius: 14).fill()
            label(language.text("Working leg"), 52, top + 12, 504, size: 25, weight: .heavy)
            let illustration = Bundle.main.url(forResource: panel.movement, withExtension: "webp", subdirectory: "leg-anatomy")
                .flatMap { UIImage(contentsOfFile: $0.path) }
            for (i, entry) in [panel.before, panel.after].enumerated() {
                let x: CGFloat = i == 0 ? 50 : 311
                let tile = CGRect(x: x, y: top + 56, width: 251, height: 182)
                (i == 0 ? UIColor.white : UIColor(red: 0.81, green: 0.94, blue: 0.90, alpha: 1)).setFill()
                UIBezierPath(roundedRect: tile, cornerRadius: 9).fill()
                let title = language.text(i == 0 ? "Before" : "After").uppercased(with: language.language.locale)
                label(title, x + 10, tile.minY + 7, 230, size: 20, weight: .heavy)
                label(entry.date, x + 10, tile.minY + 34, 230, size: 16, weight: .semibold)
                if i == 0, let joined = report.joinedDate {
                    label(language.text("Joined FITR MAX") + " · " + language.dateKey(joined),
                          x + 10, tile.minY + 55, 230, size: 9, color: muted)
                }
                if let illustration {
                    let scale = min(68 / illustration.size.width, 90 / illustration.size.height)
                    let size = CGSize(width: illustration.size.width * scale, height: illustration.size.height * scale)
                    illustration.draw(in: CGRect(x: x + 40 - size.width / 2, y: tile.minY + 117 - size.height / 2,
                                                 width: size.width, height: size.height))
                }
                let textX = x + 81
                label(language.text("Added weight"), textX, tile.minY + 70, 163, size: 13, weight: .semibold)
                label(entry.load, textX, tile.minY + 88, 163, size: 18, weight: .bold)
                if let combined = entry.combined {
                    label(language.text("Body + load"), textX, tile.minY + 118, 163, size: 13, weight: .semibold)
                    label(combined, textX, tile.minY + 137, 163, size: 22, weight: .bold, color: green)
                }
                if let reps = entry.recordedReps {
                    label(language.text("Recorded reps") + " · " + reps, textX, tile.minY + 122, 163, size: 11, weight: .semibold)
                }
                if let estimate = entry.estimate {
                    label(panel.estimateLabel + " " + estimate, textX, tile.minY + 166, 163, size: 9, color: muted)
                }
            }
            if let record = panel.record {
                let card = CGRect(x: 50, y: top + 245, width: 512, height: 55)
                UIColor(red: 0.905, green: 0.97, blue: 0.95, alpha: 1).setFill()
                UIBezierPath(roundedRect: card, cornerRadius: 9).fill()
                let heading = language.text("Personal record").uppercased(with: language.language.locale)
                let headingLines = wrapped(heading, width: 189, size: 16, weight: .heavy)
                for (i, part) in headingLines.enumerated() {
                    label(part, 61, card.minY + 5 + CGFloat(i) * 17, 189, size: 16, weight: .heavy, color: ink)
                }
                label(record.performance, 61, card.minY + (headingLines.count > 1 ? 39 : 30), 189, size: 11, color: muted)
                let metrics = [(language.text("Added weight"), Optional(record.added)), (language.text("Body + load"), record.combined)]
                for (i, metric) in metrics.enumerated() {
                    guard let value = metric.1 else { continue }
                    let x: CGFloat = 257 + CGFloat(i) * 152
                    label(metric.0, x, card.minY + 6, 145, size: 12, weight: .semibold, color: ink)
                    label(value, x, card.minY + 23, 145, size: 20, weight: .bold, color: green)
                }
            }
            y = frame.maxY + 4
        }

        private func drawChart(_ variant: StrengthProgress.ExerciseHistory, points: [ChartPoint], panel: LegPanel?, single: String?, firstInSection: Bool) {
            guard let first = points.first, let last = points.last,
                  let peak = points.max(by: { $0.value < $1.value }) else { return }
            let highest = peak.value
            let calendar = WorkoutChartCalendar(first: first.date, last: last.date)
            let parts = variant.titleParts(language)
            let title = wrapped(parts.main, width: 530, size: 19, weight: .bold)
            let subtitle = parts.variation.map { wrapped($0, width: 530, size: 12) } ?? []
            let totals = [(language.text("Recorded reps"), recordedReps(variant.totals)),
                          (language.text("Lifted volume"), liftedVolume(variant.totals))]
                .compactMap { key, value in value.map { key + " " + $0 } }
            let totalLines = totals.isEmpty ? [] : wrapped(language.text(report.period.rawValue) + "   ·   " + totals.joined(separator: "   ·   "),
                                                         width: 536, size: 11, weight: .semibold)
            let height = 268 + CGFloat(title.count - 1) * 24 + CGFloat(subtitle.count + totalLines.count) * 16
                + (panel.map { $0.height + 12 } ?? 0) + (single == nil ? 0 : 16)
            func heading() {
                begin("Strength progress", subtitle: language.text("Heaviest recorded working load in each completed session."))
            }
            if firstInSection || y + height > 730 { heading() }
            for titleLine in title {
                if y + 28 > 730 { heading() }
                label(titleLine, 38, y, 536, size: 19, weight: .bold)
                y += 24
            }
            for part in subtitle {
                label(part, 38, y, 530, size: 12, color: muted)
                y += 16
            }
            y -= 24
            let chartReduction: CGFloat = panel.map {
                let panelBottom = y + 268 + CGFloat(totalLines.count) * 16 + (single == nil ? 0 : 16) + 8 + $0.height
                return min(45, max(0, panelBottom - 738))
            } ?? 0
            let field = CGRect(x: 38, y: y + 33, width: 536, height: 141 - chartReduction)
            UIColor(red: 0.96, green: 0.95, blue: 0.99, alpha: 1).setFill()
            UIBezierPath(roundedRect: field, cornerRadius: 12).fill()
            let plot = CGRect(x: 102, y: field.minY + 15, width: 436, height: 92 - chartReduction)
            for tick in [0, highest / 2, highest] {
                let tickY = plot.maxY - CGFloat(tick / highest) * plot.height
                label(weight(tick), 40, tickY - 7, 56, size: 10, color: muted, alignment: .right)
                line(plot.minX, tickY, plot.maxX, tickY, color: rule)
            }
            for tick in calendar.ticks {
                let x = plot.minX + calendar.position(tick) * plot.width
                line(x, plot.minY, x, plot.maxY, color: rule.withAlphaComponent(0.65))
                label(calendar.label(tick, locale: language.language.locale), x - 34,
                      plot.maxY + 7, 68, size: 9, color: muted, alignment: .center)
            }
            let positions = calendar.positions(for: points.map(\.date))
            let coordinates = zip(points, positions).map { point, position in
                CGPoint(x: plot.minX + position * plot.width,
                        y: plot.maxY - point.value / highest * plot.height)
            }
            drawLoadTrace(coordinates, baseline: plot.maxY)
            y -= chartReduction
            func display(_ point: ChartPoint) -> String {
                (point.reps.map { language.format("%d reps", $0) + " × " } ?? "") + weight(point.value)
            }
            let change = last.value - first.value
            let delta = (change > 0 ? "+" : "") + weight(change)
            func endpoint(_ title: String, _ index: Int) -> String {
                let date = calendar.label(points[index].date, locale: language.language.locale)
                return language.text(title) + " · #" + String(index + 1) + " · " + date
            }
            let summary = [(endpoint("First", 0), display(first)), (endpoint("Latest", points.count - 1), display(last)),
                           (language.text("Change"), delta)]
            for (metric, item) in summary.enumerated() {
                let x = 38 + CGFloat(metric) * 182
                let tint = metric == 2 ? UIColor(red: 0.97, green: 0.94, blue: 0.77, alpha: 1)
                                       : UIColor(white: 0.965, alpha: 1)
                tint.setFill()
                UIBezierPath(roundedRect: CGRect(x: x, y: y + 183, width: 172, height: 47), cornerRadius: 9).fill()
                label(item.0, x + 10, y + 186, 153, size: 10, color: muted)
                label(item.1, x + 10, y + 200, 153, size: 15, weight: .bold)
            }
            let record = [language.text("Best working load"), display(peak),
                          peak.date.formatted(Date.FormatStyle(locale: language.language.locale, timeZone: .gmt).year().month(.abbreviated).day())].joined(separator: " · ")
            label(record, 38, y + 242, 536, size: 10, color: muted)
            y += 268
            if let single { paragraph(single, size: 11, color: green) }
            for part in totalLines {
                label(part, 38, y, 536, size: 11, weight: .semibold)
                y += 16
            }
            if let panel { drawLegPanel(panel, exercise: variant.name) }
            y += 12
        }

        private func drawLoadTrace(_ points: [CGPoint], baseline: CGFloat) {
            guard let first = points.first, let last = points.last else { return }
            let purple = UIColor(red: 0.38, green: 0.21, blue: 0.67, alpha: 1)
            let path = UIBezierPath()
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            if let area = path.copy() as? UIBezierPath {
                area.addLine(to: CGPoint(x: last.x, y: baseline))
                area.addLine(to: CGPoint(x: first.x, y: baseline))
                area.close()
                purple.withAlphaComponent(0.09).setFill()
                area.fill()
            }
            path.lineWidth = 2.8
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            purple.setStroke()
            path.stroke()
            for point in points {
                let radius = points.count > 40 ? 1.4 : 2.8
                purple.setFill()
                UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius,
                                            width: radius * 2, height: radius * 2)).fill()
            }
            let end = UIBezierPath(ovalIn: CGRect(x: last.x - 4.3, y: last.y - 4.3, width: 8.6, height: 8.6))
            UIColor.white.setFill()
            end.fill()
            purple.setStroke()
            end.lineWidth = 2.7
            end.stroke()
        }

        func wrapped(_ string: String, width: Double, size: CGFloat, weight: UIFont.Weight = .regular) -> [String] {
            let text = NSAttributedString(string: string, attributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)])
            let typesetter = CTTypesetterCreateWithAttributedString(text)
            var offset = 0
            var lines: [String] = []
            while offset < text.length {
                let count = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, width))
                let part = text.attributedSubstring(from: NSRange(location: offset, length: count)).string
                lines.append(part.trimmingCharacters(in: .whitespacesAndNewlines))
                offset += count
            }
            return lines.isEmpty ? [""] : lines
        }

        func weight(_ kilograms: Double) -> String {
            number(report.unit.value(fromKilograms: kilograms)) + " " + report.unit.suffix
        }

        func number(_ value: Double) -> String {
            value.formatted(.number.locale(language.language.locale).precision(.fractionLength(0...1)))
        }

        func trace(_ points: [CGPoint]) {
            guard let first = points.first, let last = points.last else { return }
            let path = UIBezierPath()
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            green.setStroke()
            path.lineWidth = 2
            path.lineJoinStyle = .round
            path.stroke()
            green.setFill()
            for point in points.count < 24 ? points : [first, last] {
                UIBezierPath(ovalIn: CGRect(x: point.x - 2.6, y: point.y - 2.6, width: 5.2, height: 5.2)).fill()
            }
        }

        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, color: UIColor) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x1, y: y1))
            path.addLine(to: CGPoint(x: x2, y: y2))
            color.setStroke()
            path.lineWidth = 0.7
            path.stroke()
        }

        func label(_ string: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat,
                   size: CGFloat = 13, weight: UIFont.Weight = .regular, color: UIColor? = nil,
                   alignment: NSTextAlignment = .left) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color ?? ink, .paragraphStyle: paragraph,
            ]
            (string as NSString).draw(in: CGRect(x: x, y: y, width: width, height: size * 1.65), withAttributes: attributes)
        }
    }
}
