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
    var currentBodyweight: Double?
    var earlierFirst: [String: StrengthProgress.SessionTotals] = [:]
    var joinedDate: String?
    var period: AvatarReportPeriod = .allTime
    var reportDates: ClosedRange<String>? = nil
    var identityStages: [IdentityStage] = []
    var laterBodyweightBySession: [UUID: LaterBodyweight] = [:]
    var nutrition: NutritionReport? = nil

    /// The nearest weigh-in after a session that has none on or before it, with its date so the figure stays traceable.
    struct LaterBodyweight {
        let kg: Double
        let date: String
    }

    /// Evenly spaced session indexes from first to latest, always including the first, the latest and `keeping` (the record).
    static func sessionSample(count: Int, limit: Int, keeping: Int) -> [Int] {
        guard count > limit, limit > 1 else { return Array(0..<max(0, min(count, limit))) }
        var picks = (0..<limit).map { Int((Double($0) * Double(count - 1) / Double(limit - 1)).rounded()) }
        if !picks.contains(keeping), limit > 2 {
            // Swap the nearest interior pick for the record so the first and latest stay.
            let nearest = (1..<(limit - 1)).min { abs(picks[$0] - keeping) < abs(picks[$1] - keeping) } ?? 1
            picks[nearest] = keeping
        }
        return picks.sorted()
    }

    /// Consecutive months that share one training identity, from the same rules as the 90-day profile.
    struct IdentityStage {
        let from: String
        let to: String
        let title: String
        let workouts: Int
    }

    /// An identity other than the current one, with every span it was held.
    struct EarlierIdentity {
        let title: String
        let spans: [IdentityStage]
        var workouts: Int { spans.reduce(0) { $0 + $1.workouts } }
    }

    /// Every identity other than the current one, once, in the order it was first held.
    /// Months that swap back and forth would otherwise print the same two titles again and again.
    static func earlierIdentities(_ stages: [IdentityStage], current: String) -> [EarlierIdentity] {
        // A span with too few workouts names no identity, so it is not listed as one.
        let others = stages.filter { $0.title != current && $0.title != TrainingProfile90.baselineTitle }
        var order: [String] = []
        for stage in others where !order.contains(stage.title) { order.append(stage.title) }
        return order.map { title in EarlierIdentity(title: title, spans: others.filter { $0.title == title }) }
    }

    static func identityStages(ownerID: UUID, data: DashboardData, dates: ClosedRange<String>) -> [IdentityStage] {
        var stages: [IdentityStage] = []
        var month = String(dates.lowerBound.prefix(7)) + "-01"
        while month <= dates.upperBound {
            guard let start = APEXDateMath.date(from: month),
                  let next = APEXDateMath.calendar.date(byAdding: .month, value: 1, to: start) else { break }
            let nextMonth = APEXDateMath.key(from: next)
            let from = max(month, dates.lowerBound), to = min(APEXDateMath.adding(days: -1, to: nextMonth), dates.upperBound)
            let profile = TrainingProfile90.summarize(ownerID: ownerID, data: data, from: from, through: to)
            if profile.classifiedWorkouts > 0 {
                if let last = stages.last, last.title == profile.athleteTitle, APEXDateMath.adding(days: 1, to: last.to) == from {
                    stages[stages.count - 1] = IdentityStage(from: last.from, to: to, title: last.title,
                                                             workouts: last.workouts + profile.classifiedWorkouts)
                } else {
                    stages.append(IdentityStage(from: from, to: to, title: profile.athleteTitle, workouts: profile.classifiedWorkouts))
                }
            }
            month = nextMonth
        }
        return stages
    }

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
        let owned = StrengthProgress.withoutReplays(data.workoutSessions.filter { $0.userID == ownerID && $0.completed })
        let sessions = owned.filter { dates.contains($0.date) }
        let ids = Set(sessions.map(\.id))
        let earlier = owned.filter { $0.date < dates.lowerBound }
        let previous = earlier.isEmpty ? [] : StrengthProgress.exerciseHistory(ownerID: ownerID, sessions: earlier,
            logs: data.workoutLogs, exercises: data.exercises)
        // A lifetime starting point needs a recorded working load, the same rule the chart applies.
        let first = Dictionary(uniqueKeysWithValues: previous.compactMap { item in
            item.sessions.first { $0.heaviestSet != nil }.map { (item.key, $0) }
        })
        let required = Set(first.values.map(\.sessionID))
        let (weights, laterWeights) = bodyweights(in: data, owner: ownerID, through: dates.upperBound,
                                                  sessions: sessions + earlier.filter { required.contains($0.id) })
        let currentMass = data.weighedProfile(on: today).flatMap { profile -> Double? in
            guard profile.userID == ownerID, (10...500).contains(profile.weightKG) else { return nil }
            // A new profile can carry the database default until the user enters a weight.
            if profile.weightKG == 70 && ProfileIntegrityPolicy.authorizedProtocol(for: profile) == nil &&
                !weights.values.contains(70) {
                let hasMeasurement = data.healthMetrics.contains { $0.userID == ownerID && $0.date <= today && $0.weightKG == 70 } ||
                    data.dailyLogs.contains { $0.userID == ownerID && $0.date <= today && $0.weightKG == 70 }
                if !hasMeasurement { return nil }
            }
            return profile.weightKG
        }
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
                    bodyweightBySession: weights, currentBodyweight: currentMass,
                    earlierFirst: first, joinedDate: joined, period: period, reportDates: dates,
                    identityStages: identityStages(ownerID: ownerID, data: data, dates: dates),
                    laterBodyweightBySession: laterWeights,
                    nutrition: NutritionReport.summarize(ownerID: ownerID, data: data, dates: dates, today: today))
    }

    private static func bodyweights(in data: DashboardData, owner: UUID, through end: String,
                                    sessions: [WorkoutSession]) -> (onOrBefore: [UUID: Double], later: [UUID: LaterBodyweight]) {
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
        // The weigh-ins every target reads: a typed entry outranks a Health reading of the same day.
        for row in Bodyweight.weighIns(ownerID: owner, data: data) {
            add(row.date, row.kg, priority: row.typed ? 2 : 1, tie: "")
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
        var later: [UUID: LaterBodyweight] = [:]
        var dayStart = 0
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            while dayStart < observations.count && observations[dayStart].date < session.date { dayStart += 1 }
            let started = ExternalWorkoutImport.parseTimestamp(session.startedAt)
            let sameDay = observations[dayStart...].prefix { $0.date == session.date }.last { row in
                guard let time = row.time, let started else { return true }
                return time <= started
            }
            bySession[session.id] = sameDay?.kg ?? (dayStart > 0 ? observations[dayStart - 1].kg : nil)
            // No weigh-in yet: the first one after the session (still inside the report) is the closest evidence.
            if bySession[session.id] == nil, let next = observations[dayStart...].first(where: { row in
                guard row.date == session.date, let time = row.time, let started else { return true }
                return time > started
            }) {
                later[session.id] = LaterBodyweight(kg: next.kg, date: next.date)
            }
        }
        return (bySession, later)
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
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: Self.pageSize.width, height: Self.pageSize.height))
        return renderer.pdfData { context in
            let pages = Pages(context: context, report: self)
            let profile = trainingProfile.flatMap { $0.classifiedWorkouts > 0 ? $0 : nil }
            if profile != nil || !families.isEmpty { pages.drawCover(families, profile: profile) }
            if let nutrition { pages.drawNutrition(nutrition) }
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

    /// ISO A4 in PostScript points.
    static let pageSize = CGSize(width: 595.28, height: 841.89)

    /// Draws the report on A4 pages: an illustrated cover, one card per strength series,
    /// the exercise rankings and the Avatar scores. Every figure comes from `StrengthProgress`.
    @MainActor
    private final class Pages {
        let context: UIGraphicsPDFRendererContext
        let report: AvatarReport
        let language = LanguageState.shared

        static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
        // One ink scale, one brand green for identity and one series green for data; amber marks records.
        let ink = Pages.rgb(0x0E1A1F), soft = Pages.rgb(0x3C4A51), muted = Pages.rgb(0x6C7A81), rule = Pages.rgb(0xE2E7E9)
        let canvas = Pages.rgb(0xF4F7F6), green = Pages.rgb(0x00745E), series = Pages.rgb(0x00876C)
        let mint = Pages.rgb(0xB9F0D8), mintWash = Pages.rgb(0xEAF7F1), amber = Pages.rgb(0xE09A0B), amberInk = Pages.rgb(0x8A5A00)
        let amberWash = Pages.rgb(0xFFF4DA), night = Pages.rgb(0x05211C)
        let glow = Pages.rgb(0x34D5A6), violet = Pages.rgb(0x6B5BD6), paper = Pages.rgb(0xF6F9F8)

        let left: CGFloat = 40, right: CGFloat = 555.28, top: CGFloat = 76, bottom: CGFloat = 790
        var width: CGFloat { right - left }
        var page = 0
        var y: CGFloat = 0
        private var section: String?

        init(context: UIGraphicsPDFRendererContext, report: AvatarReport) {
            self.context = context
            self.report = report
        }

        private var locale: Locale { language.language.locale }

        private var footerText: String {
            report.reportDates.map {
                language.text("Avatar report") + "   ·   " + language.text(report.period.rawValue) + "   ·   "
                    + language.dateKey($0.lowerBound) + " – " + language.dateKey($0.upperBound)
            } ?? language.text("Avatar report")
        }

        // MARK: Pages

        func beginPage(_ section: String? = nil) {
            context.beginPage()
            page += 1
            self.section = section
            drawAurora()
            label(AppBrand.name, left, 30, 140, size: 10.5, weight: .heavy, color: green, kern: 1.4)
            if let section {
                let brand = measure(AppBrand.name, size: 10.5, weight: .heavy, kern: 1.4)
                fill(CGRect(x: left + brand + 9, y: 31.5, width: 0.8, height: 11), rule.darker)
                label(language.text(section), left + brand + 17, 30.5, 280, size: 10, weight: .medium, color: muted)
            }
            label(report.displayName, right - 230, 30, 230, size: 10.5, weight: .semibold, color: soft, alignment: .right)
            fill(CGRect(x: left, y: 51, width: width, height: 0.8), ink.withAlphaComponent(0.1))
            fill(CGRect(x: left, y: 802, width: width, height: 0.8), ink.withAlphaComponent(0.1))
            label(footerText, left, 811, width - 60, size: 8.5, color: muted)
            pageNumber(color: soft, background: canvas)
            y = top
        }

        private func pageNumber(color: UIColor, background: UIColor) {
            let number = String(page)
            let pill = max(22, measure(number, size: 8.5, weight: .bold) + 12)
            let frame = CGRect(x: right - pill, y: 808, width: pill, height: 17)
            glass(frame, radius: 8.5, tint: background == canvas ? .white : background, opacity: 0.7)
            centered(number, in: frame, size: 8.5, weight: .bold, color: color)
        }

        func continuePage() { beginPage(section) }

        func begin(_ section: String, subtitle: String) {
            beginPage(section)
            let size = fittingSize(language.text(section), width: width, sizes: [26, 22], weight: .heavy)
            for part in wrapped(language.text(section), width: width, size: size, weight: .heavy) {
                label(part, left, y, width, size: size, weight: .heavy)
                y += size + 7
            }
            for part in wrapped(subtitle, width: width, size: 11.5) where !part.isEmpty {
                label(part, left, y, width, size: 11.5, color: muted)
                y += 16
            }
            y += 14
        }

        // MARK: Cover

        func drawCover(_ families: [StrengthProgress.RankedFamily], profile: TrainingProfile90?) {
            context.beginPage()
            page += 1
            section = nil
            drawAurora()
            label(AppBrand.name, left, 34, 200, size: 12, weight: .heavy, color: green, kern: 2.2)
            let exported = Date.now.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
            label(language.text("Avatar report").uppercased(with: locale) + "  ·  " + exported, right - 260, 35, 260, size: 9,
                  weight: .semibold, color: muted, alignment: .right, kern: 1.2)
            fill(CGRect(x: left, y: 56, width: 34, height: 3), green, radius: 1.5)
            y = 74
            let name = report.displayName.isEmpty ? language.text("Avatar report") : report.displayName
            let nameSize = fittingSize(name, width: width, sizes: [44, 38, 32, 28], weight: .heavy, display: true)
            for part in wrapped(name, width: width, size: nameSize, weight: .heavy, display: true).prefix(2) {
                label(part, left, y, width, size: nameSize, weight: .heavy, display: true)
                y += nameSize + 6
            }
            var lines: [String] = []
            if let dates = report.reportDates {
                lines.append(language.text(report.period.rawValue) + "  ·  " + language.dateKey(dates.lowerBound) + " – "
                               + language.dateKey(dates.upperBound))
            }
            if let joined = report.joinedDate { lines.append(language.text("Joined FITR MAX") + " · " + language.dateKey(joined)) }
            for (index, line) in lines.enumerated() {
                label(line, left, y, width, size: index == 0 ? 12 : 10.5, weight: index == 0 ? .semibold : .regular,
                      color: index == 0 ? green : muted)
                y += index == 0 ? 18 : 16
            }
            y += 16
            if let profile { drawIdentityPanel(profile) }
            if !families.isEmpty {
                let totals = families.reduce(into: StrengthProgress.LifetimeTotals()) { $0.add($1.totals) }
                label(language.text(report.period == .allTime ? "All-time training totals" : "Training totals"),
                      left, y, width, size: 14, weight: .heavy)
                y += 26
                if let kg = totals.liftedVolumeKG, let total = liftedVolume(totals) {
                    drawVolumeCard(kilograms: kg, total: total, stats: coverStats(totals, families: families))
                } else {
                    drawCoverStats(totals, families: families)
                }
                if totals.missingReps {
                    label("* " + language.text("Incomplete records"), left, y, width, size: 9, color: muted)
                    y += 14
                }
            }
            fill(CGRect(x: left, y: 802, width: width, height: 0.8), ink.withAlphaComponent(0.1))
            label(footerText, left, 811, width - 60, size: 8.5, color: muted)
            pageNumber(color: soft, background: canvas)
        }

        /// The current training identity, its mix, and how it changed month by month.
        private func drawIdentityPanel(_ profile: TrainingProfile90) {
            let pad: CGFloat = 24
            let inner = width - pad * 2
            let titleSize = fittingSize(language.text(profile.athleteTitle), width: inner, sizes: [30, 26, 22], weight: .heavy)
            let title = wrapped(language.text(profile.athleteTitle), width: inner, size: titleSize, weight: .heavy)
            // The title above is the current identity; only the others appear below it, once each.
            let earlier = Array(AvatarReport.earlierIdentities(report.identityStages, current: profile.athleteTitle).prefix(6))
            let chips = stageChips(earlier, width: inner)
            let chipRows = Set(chips.map(\.row)).count
            let height = pad + 16 + CGFloat(title.count) * 35 + 18 + 26 + 38 + (chips.isEmpty ? 0 : 30 + CGFloat(chipRows) * 38) + pad - 10
            let panel = CGRect(x: left, y: y, width: width, height: height)
            glass(panel, radius: 24, tint: night, opacity: 1, dark: true)
            // A mesh of light under smoked glass: deep pine into ink blue, lit by emerald, cyan, violet and a warm ember.
            let mesh = raster(panel.size, scale: 2) { cg in
                let size = panel.size
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 24).addClip()
                guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
                if let base = CGGradient(colorsSpace: space, colors: [Pages.rgb(0x041F1B).cgColor, Pages.rgb(0x07302A).cgColor,
                                                                      Pages.rgb(0x0B1E3D).cgColor] as CFArray, locations: [0, 0.5, 1]) {
                    cg.drawLinearGradient(base, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                }
                radial(cg, at: CGPoint(x: size.width * 0.18, y: -size.height * 0.15), radius: size.width * 0.55, color: Pages.rgb(0x12B886), alpha: 0.55)
                radial(cg, at: CGPoint(x: size.width * 1.02, y: size.height * 0.28), radius: size.width * 0.42, color: Pages.rgb(0x1FA7C9), alpha: 0.5)
                radial(cg, at: CGPoint(x: size.width * 0.78, y: size.height * 1.08), radius: size.width * 0.5, color: Pages.rgb(0x7B5CF0), alpha: 0.55)
                radial(cg, at: CGPoint(x: size.width * 0.02, y: size.height * 1.02), radius: size.width * 0.3, color: Pages.rgb(0xF5A524), alpha: 0.28)
                // A soft diagonal sheen, as if light catches the glass.
                if let sheen = CGGradient(colorsSpace: space, colors: [UIColor.white.withAlphaComponent(0).cgColor,
                                                                       UIColor.white.withAlphaComponent(0.09).cgColor,
                                                                       UIColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0.3, 0.5, 0.7]) {
                    cg.drawLinearGradient(sheen, start: CGPoint(x: size.width * 0.15, y: 0), end: CGPoint(x: size.width * 0.75, y: size.height), options: [])
                }
                // Fine grain keeps the large gradients from banding in print.
                var seed: UInt64 = 0x9E3779B97F4A7C15
                func next() -> CGFloat {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    return CGFloat(seed >> 40) / CGFloat(1 << 24)
                }
                cg.setFillColor(UIColor.white.withAlphaComponent(0.05).cgColor)
                for _ in 0..<Int(size.width * size.height / 10) {
                    cg.fill(CGRect(x: next() * size.width, y: next() * size.height, width: 0.5, height: 0.5))
                }
            }
            mesh.draw(in: panel)
            stroke(panel, UIColor.white.withAlphaComponent(0.2), radius: 24, lineWidth: 1)
            let faint = UIColor.white.withAlphaComponent(0.64)
            var cursor = y + pad
            label(language.text(report.period == .allTime ? "90-day training profile" : "Training profile").uppercased(with: locale),
                  left + pad, cursor, inner, size: 9.5, weight: .bold, color: mint)
            cursor += 16
            for part in title {
                label(part, left + pad, cursor, inner, size: titleSize, weight: .heavy, color: .white)
                cursor += 35
            }
            label(language.dateKey(profile.from) + " – " + language.dateKey(profile.to), left + pad, cursor, inner, size: 10.5, color: faint)
            cursor += 18
            let values = Dictionary(profile.metrics(language: language).map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
            let headline = ["Classified workouts", "Workouts per week"].compactMap { key in
                values[key].map { language.text(key) + " " + $0 }
            }.joined(separator: "   ·   ")
            label(headline, left + pad, cursor + 6, inner, size: 11.5, weight: .semibold, color: UIColor.white.withAlphaComponent(0.92))
            cursor += 26
            // Green, deep orange and blue: three hues that stay apart on the dark panel, even as a 4 pt sliver.
            let modes: [(TrainingProfile90.Mode, UIColor)] = [(.resistance, Self.rgb(0x6FE0B4)), (.cardio, Self.rgb(0xFF7A2F)),
                                                             (.mobility, Self.rgb(0x6CB8FF))]
            let present = modes.filter { profile.counts[$0.0, default: 0] > 0 }
            let sum = present.reduce(0) { $0 + profile.counts[$1.0, default: 0] }
            if sum > 0 {
                var x = left + pad
                let usable = inner - CGFloat(present.count - 1) * 3
                for (mode, color) in present {
                    let share = usable * CGFloat(profile.counts[mode, default: 0]) / CGFloat(sum)
                    fill(CGRect(x: x, y: cursor, width: max(4, share), height: 8), color, radius: 4)
                    x += share + 3
                }
                x = left + pad
                var legend = present.map { ($0.1, language.text($0.0.rawValue) + " " + String(profile.counts[$0.0, default: 0])) }
                if profile.runs > 0 { legend.append((UIColor.clear, language.text("Running") + " " + String(profile.runs))) }
                for (color, text) in legend {
                    if color != .clear {
                        fill(CGRect(x: x, y: cursor + 20, width: 7, height: 7), color, radius: 3.5)
                        x += 11
                    }
                    label(text, x, cursor + 16, 160, size: 10.5, weight: .medium, color: UIColor.white.withAlphaComponent(0.82))
                    x += measure(text, size: 10.5, weight: .medium) + 18
                }
            }
            cursor += 38
            if !chips.isEmpty {
                fill(CGRect(x: left + pad, y: cursor, width: inner, height: 0.7), UIColor.white.withAlphaComponent(0.16))
                cursor += 12
                label(language.text("Before").uppercased(with: locale), left + pad, cursor, inner, size: 9.5, weight: .bold, color: mint)
                cursor += 18
                for chip in chips {
                    let frame = chip.frame.offsetBy(dx: left + pad, dy: cursor)
                    glass(frame, radius: 10, tint: .white, opacity: 0.1, dark: true)
                    label(chip.title, frame.minX + 10, frame.minY + 4, frame.width - 20, size: 10.5, weight: .bold, color: .white)
                    label(chip.dates, frame.minX + 10, frame.minY + 17.5, frame.width - 16, size: 8, weight: .medium, color: faint)
                }
            }
            y = panel.maxY + 20
        }

        private struct StageChip {
            let row: Int
            let frame: CGRect
            let title: String
            let dates: String
        }

        private func stageChips(_ identities: [AvatarReport.EarlierIdentity], width available: CGFloat) -> [StageChip] {
            let style = Date.FormatStyle(locale: locale, calendar: APEXDateMath.calendar, timeZone: .gmt).month(.abbreviated)
            // Three per row.
            let gap: CGFloat = 8
            let chipWidth = (available - gap * 2) / 3
            return identities.enumerated().map { index, identity in
                let showYear = Set(identity.spans.flatMap { [$0.from.prefix(4), $0.to.prefix(4)] }).count > 1
                func month(_ day: String) -> String {
                    APEXDateMath.date(from: day).map { $0.formatted(showYear ? style.year() : style) } ?? day
                }
                let range = identity.spans.map { span in
                    month(span.from) == month(span.to) ? month(span.from) : month(span.from) + " – " + month(span.to)
                }.joined(separator: ", ")
                let full = range + " · " + language.format("%d sessions", identity.workouts)
                let dates = measure(full, size: 8, weight: .medium) <= chipWidth - 16 ? full : range
                return StageChip(row: index / 3,
                                 frame: CGRect(x: CGFloat(index % 3) * (chipWidth + gap), y: CGFloat(index / 3) * 38, width: chipWidth, height: 31),
                                 title: language.text(identity.title), dates: dates)
            }
        }

        private func coverStats(_ totals: StrengthProgress.LifetimeTotals, families: [StrengthProgress.RankedFamily]) -> [(String, String)] {
            var items: [(String, String)] = [("Performed sets", number(Double(totals.sets)))]
            if let reps = recordedReps(totals) { items.append(("Recorded reps", reps)) }
            items.append(("Sessions", number(Double(Set(families.flatMap { $0.sessions.map(\.sessionID) }).count))))
            return items
        }

        private func drawVolumeCard(kilograms kg: Double, total: String, stats: [(String, String)]) {
            let object = LiftedMassComparison.caption(kilograms: kg)
            let passed = LiftedMassComparison.passedHeroCaption(kilograms: kg)
            let hero = LiftedMassComparison.heroCaption(kilograms: kg)
            let image = object?.artworkURL.flatMap { UIImage(contentsOfFile: $0.path) }
            let pad: CGFloat = 22, tile: CGFloat = 116
            let inner = left + pad
            let textX = image == nil ? inner : inner + tile + 20
            let textWidth = right - pad - textX
            let valueSize: CGFloat = 36
            let valueLines = wrapped(total, width: width - pad * 2, size: valueSize, weight: .heavy, rounded: true)
            typealias Line = (text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor, link: URL, gap: CGFloat)
            var lines: [Line] = []
            if let object {
                lines.append((object.caption, 14.5, .semibold, ink, object.source, 0))
                if let fact = object.fact { lines.append((fact, 10.5, .regular, muted, object.factSource ?? object.source, 4)) }
            }
            if let passed { lines.append(("✓ " + language.text("Milestone passed") + " · " + passed.caption, 10.5, .semibold, soft, passed.source, 12)) }
            if let hero { lines.append((hero.caption, 10.5, .semibold, green, hero.source, passed == nil ? 12 : 6)) }
            let blocks = lines.map { line in (line, wrapped(line.text, width: textWidth, size: line.size, weight: line.weight)) }
            let progress = hero.flatMap { $0.kg }.map { min(1, max(0, kg / $0)) }
            let textHeight = blocks.reduce(CGFloat(0)) { $0 + $1.0.gap + CGFloat($1.1.count) * ($1.0.size + 4) }
                + (progress == nil ? 0 : 20)
            let artHeight = max(image == nil ? 0 : tile, textHeight)
            let card = CGRect(x: left, y: y, width: width, height: pad + 18 + CGFloat(valueLines.count) * 42 + 10 + artHeight + 18 + 50 + pad - 6)
            glass(card, radius: 24, opacity: 0.6)
            var cursor = y + pad
            label(language.text("Lifted volume"), inner, cursor, width - pad * 2, size: 12.5, weight: .semibold, color: green)
            cursor += 18
            for part in valueLines {
                label(part, inner, cursor, width - pad * 2, size: valueSize, weight: .heavy, color: ink, rounded: true)
                cursor += 42
            }
            cursor += 10
            let artTop = cursor
            if let image, let object {
                let frame = CGRect(x: inner, y: artTop, width: tile, height: tile)
                glass(frame, radius: 18, opacity: 0.9)
                let inset = frame.insetBy(dx: 8, dy: 8)
                let scale = min(inset.width / image.size.width, inset.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                context.cgContext.saveGState()
                UIBezierPath(roundedRect: frame, cornerRadius: 18).addClip()
                image.draw(in: CGRect(x: inset.midX - size.width / 2, y: inset.midY - size.height / 2, width: size.width, height: size.height))
                context.cgContext.restoreGState()
                link(object.source, frame)
            }
            var textY = artTop + max(0, (artHeight - textHeight) / 2)
            for (line, parts) in blocks {
                textY += line.gap
                let start = textY
                for part in parts {
                    label(part, textX, textY, textWidth, size: line.size, weight: line.weight, color: line.color)
                    textY += line.size + 4
                }
                link(line.link, CGRect(x: textX, y: start, width: textWidth, height: textY - start))
            }
            if let progress {
                let track = CGRect(x: textX, y: textY + 6, width: textWidth - 46, height: 7)
                fill(track, ink.withAlphaComponent(0.07), radius: 3.5)
                gradient(CGRect(x: track.minX, y: track.minY, width: max(7, track.width * progress), height: track.height),
                         [series, Self.rgb(0x35C79A)], vertical: false, radius: 3.5)
                label(progress.formatted(.percent.precision(.fractionLength(0)).locale(locale)), track.maxX + 6, textY + 1.5,
                      40, size: 10, weight: .bold, color: green, alignment: .right, rounded: true)
            }
            let statsTop = artTop + artHeight + 18
            fill(CGRect(x: inner, y: statsTop - 1, width: width - pad * 2, height: 0.8), ink.withAlphaComponent(0.08))
            let column = (width - pad * 2) / CGFloat(max(1, stats.count))
            for (index, item) in stats.enumerated() {
                let x = inner + CGFloat(index) * column
                label(language.text(item.0), x, statsTop + 9, column - 10, size: 9.5, weight: .semibold, color: muted)
                label(item.1, x, statsTop + 23, column - 10, size: 22, weight: .bold, rounded: true)
            }
            y = card.maxY + 12
        }

        private func drawCoverStats(_ totals: StrengthProgress.LifetimeTotals, families: [StrengthProgress.RankedFamily]) {
            let items = coverStats(totals, families: families)
            let gap: CGFloat = 10
            let tileWidth = (width - gap * CGFloat(items.count - 1)) / CGFloat(items.count)
            for (index, item) in items.enumerated() {
                let x = left + CGFloat(index) * (tileWidth + gap)
                glass(CGRect(x: x, y: y, width: tileWidth, height: 64), radius: 16)
                label(language.text(item.0), x + 15, y + 12, tileWidth - 30, size: 10, weight: .semibold, color: muted)
                label(item.1, x + 15, y + 27, tileWidth - 30, size: 24, weight: .bold, rounded: true)
            }
            y += 72
        }

        func volume(_ kg: Double, partial: Bool = false) -> String {
            LiftedMassComparison.formattedMass(kg, locale: locale, partial: partial)
        }

        // MARK: Rankings

        func drawRankings(_ rows: [StrengthProgress.RankedFamily]) {
            // The volume column is wide enough to keep a figure and its unit on one line.
            let columns: [(title: String, x: CGFloat, width: CGFloat)] = [
                ("Exercise", 40, 174), ("Sessions", 217, 58), ("Recorded reps", 278, 60),
                ("Load per rep", 341, 72), ("Lifted volume", 416, 139.28),
            ]
            let mostSessions = CGFloat(max(1, rows.map(\.sessionCount).max() ?? 1))
            var division: StrengthProgress.BodyRegion?
            func divisionHeading(_ region: StrengthProgress.BodyRegion) {
                dot(CGPoint(x: left + 6, y: y + 10), radius: 4.5, fill: regionColors(region).1, ring: 0)
                label(language.text(region.rawValue), left + 18, y, width - 18, size: 15, weight: .heavy)
                y += 28
            }
            func heading() {
                begin("Most trained exercises", subtitle: language.text("Each completed workout counts once per exercise family."))
                if rows.contains(where: { $0.totals.missingVolume || $0.totals.missingReps }) {
                    label("* " + language.text("Incomplete records"), left, y - 8, width, size: 9.5, color: muted)
                    y += 8
                }
                let titles = columns.map { wrapped(language.text($0.title), width: $0.width - 6, size: 9, weight: .bold) }
                let height = CGFloat(titles.map(\.count).max() ?? 1) * 12 + 14
                glass(CGRect(x: left, y: y, width: width, height: height), radius: 14, opacity: 0.6)
                for (index, column) in columns.enumerated() {
                    for (line, part) in titles[index].enumerated() {
                        label(part, column.x + (index == 0 ? 14 : 0), y + 7 + CGFloat(line) * 12, column.width - (index == 0 ? 14 : 10),
                              size: 9, weight: .bold, color: muted, alignment: index == 0 ? .left : .right)
                    }
                }
                y += height + 12
                if let division { divisionHeading(division) }
            }
            typealias Row = (name: [String], values: [String], size: CGFloat, variant: Bool, sessions: Int)
            func layout(_ title: String, sessions: Int, totals: StrengthProgress.LifetimeTotals, variant: Bool) -> Row {
                let size: CGFloat = variant ? 10 : 12
                let average = totals.averageLoadKG.map { weight($0) + (totals.missingVolume ? "*" : "") }
                // Session counts are short, so names may run a little into that column before they wrap.
                return (wrapped(title, width: columns[0].width + 30 - (variant ? 26 : 14), size: size, weight: variant ? .regular : .semibold),
                        [String(sessions), recordedReps(totals) ?? "", average ?? "", liftedVolume(totals) ?? ""], size, variant, sessions)
            }
            func height(_ row: Row) -> CGFloat {
                CGFloat(row.name.count) * (row.size + 3) + (row.variant ? 3 : 15)
            }
            func draw(_ row: Row) {
                let rowTop = y
                let indent: CGFloat = row.variant ? 26 : 14
                let fontWeight: UIFont.Weight = row.variant ? .regular : .semibold
                if row.variant { fill(CGRect(x: left + 16, y: y + row.size / 2 + 2, width: 4, height: 4), series.withAlphaComponent(0.45), radius: 2) }
                for (line, part) in row.name.enumerated() {
                    label(part, columns[0].x + indent, rowTop + CGFloat(line) * (row.size + 3), columns[0].width + 32 - indent, size: row.size,
                          weight: fontWeight, color: row.variant ? muted : ink)
                }
                for (index, value) in row.values.enumerated() {
                    let column = columns[index + 1]
                    let numberWeight: UIFont.Weight = row.variant ? .regular : .bold
                    // A figure never wraps away from its unit: it steps down a size instead.
                    let size = [row.size, row.size - 1, row.size - 2, row.size - 3].first {
                        measure(value, size: $0, weight: numberWeight, rounded: true) <= column.width - 10
                    } ?? row.size - 3
                    label(value, column.x, rowTop + (row.size - size) * 0.7, column.width - 10, size: size, weight: numberWeight,
                          color: row.variant ? muted : ink, alignment: .right, rounded: true)
                }
                if !row.variant {
                    let track = CGRect(x: left + indent, y: rowTop + CGFloat(row.name.count) * (row.size + 3) + 4, width: 150, height: 4)
                    fill(track, ink.withAlphaComponent(0.06), radius: 2)
                    gradient(CGRect(x: track.minX, y: track.minY, width: max(4, track.width * CGFloat(row.sessions) / mostSessions), height: 4),
                             [glow, series], vertical: false, radius: 2)
                }
                y = rowTop + height(row)
            }

            heading()
            // Lower body first, then upper body; each division runs from the most to the least trained family.
            for region in [StrengthProgress.BodyRegion.lower, .upper, .core, .other] {
                let families = rows.filter { $0.region == region }
                guard !families.isEmpty else { continue }
                // A family with variants gets its own card; consecutive single-movement families share one.
                var groups: [[Row]] = []
                var singles: [Row] = []
                for family in families {
                    let head = layout(language.text(family.name), sessions: family.sessionCount, totals: family.totals, variant: false)
                    if family.showsVariants {
                        if !singles.isEmpty { groups.append(singles); singles = [] }
                        groups.append([head] + family.variants.map {
                            layout(language.text($0.name), sessions: $0.sessionCount, totals: $0.totals, variant: true)
                        })
                    } else {
                        singles.append(head)
                    }
                }
                if !singles.isEmpty { groups.append(singles) }
                division = region
                if y + 28 + 14 + (groups.first?.first.map(height) ?? 0) > bottom { heading() } else {
                    if y > top + 120 { y += 6 }
                    divisionHeading(region)
                }
                for group in groups {
                    var start = 0
                    while start < group.count {
                        var used: CGFloat = 14, end = start
                        while end < group.count, y + used + height(group[end]) <= bottom {
                            used += height(group[end])
                            end += 1
                        }
                        if end == start { heading(); continue }
                        glass(CGRect(x: left, y: y, width: width, height: used), radius: 16, opacity: 0.55)
                        y += 8
                        for row in group[start..<end] { draw(row) }
                        y += 14
                        start = end
                        if start < group.count { heading() }
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

        // MARK: Strength progress

        private struct ChartPoint {
            let date: Date
            let day: String
            let value: Double
            let reps: Int?
        }

        private func chartPoints(_ variant: StrengthProgress.ExerciseHistory) -> [ChartPoint] {
            let loaded = Dictionary(uniqueKeysWithValues: variant.points.map { ($0.sessionID, $0) })
            let points: [ChartPoint] = variant.sessions.compactMap { session in
                guard let date = APEXDateMath.date(from: session.date) else { return nil }
                let point = loaded[session.sessionID]
                if let set = session.heaviestSet, set.kg >= (point?.topWeight ?? 0) {
                    return ChartPoint(date: date, day: session.date, value: set.kg, reps: set.reps)
                }
                return point.map { ChartPoint(date: date, day: session.date, value: $0.topWeight, reps: $0.topReps) }
            }
            return points.count >= 2 && points.contains { $0.value > 0 } ? points : []
        }

        /// The heaviest load, then the most reps at it; the earliest session wins an exact tie.
        private func bestIndex(_ points: [ChartPoint]) -> Int? {
            points.indices.max { (points[$0].value, points[$0].reps ?? 0, -$0) < (points[$1].value, points[$1].reps ?? 0, -$1) }
        }

        func drawCharts(_ families: [StrengthProgress.RankedFamily]) {
            let charts = families.flatMap(\.variants).map { variant in
                let points = chartPoints(variant)
                let change = points.first.flatMap { first in points.last.map { $0.value - first.value } }
                return (variant: variant, points: points, change: change)
            }.sorted { lhs, rhs in
                let a = lhs.change.map(abs) ?? -1
                let b = rhs.change.map(abs) ?? -1
                if a != b { return a > b }
                if let left = lhs.change, let right = rhs.change, left != right { return left > right }
                let order = lhs.variant.name.compare(rhs.variant.name, options: .caseInsensitive, range: nil, locale: locale)
                return order == .orderedSame ? lhs.variant.key < rhs.variant.key : order == .orderedAscending
            }

            // Each exercise owns a page: its chart, records and working-leg or hand-load panel stay together.
            for (variant, points, change) in charts {
                let panel = legPanel(variant)
                let best = variant.sessions.filter { $0.bestSingleKG != nil }
                    .max { ($0.bestSingleKG ?? 0) < ($1.bestSingleKG ?? 0) }
                let single = best.flatMap { row in
                    row.bestSingleKG.map { [language.text("Best single"), weight($0), language.dateKey(row.date)].joined(separator: " · ") }
                }
                let hands = handLoadSections(variant)
                if !points.isEmpty {
                    beginPage("Strength progress")
                    drawExerciseHeader(variant, change: change)
                    let reserved = (panel.map { $0.height + 14 } ?? 0) + handLoadHeight(hands) + (single == nil ? 0 : 20) + 84
                    let height = min(280, max(150, bottom - y - reserved))
                    drawChartCard(points, height: height, single: single)
                    if let panel { drawLegPanel(panel) }
                    drawHandLoadSections(hands)
                    if panel == nil && hands.isEmpty { drawSessionLog(points) }
                } else if panel != nil || single != nil || (!hands.isEmpty && repEndpoints(variant) == nil) {
                    beginPage("Strength progress")
                    drawExerciseHeader(variant, change: nil)
                    if let single {
                        label(single, left, y, width, size: 11, weight: .semibold, color: green)
                        y += 20
                    }
                    if let panel { drawLegPanel(panel) }
                    if repEndpoints(variant) == nil { drawHandLoadSections(hands) }
                }
            }
            drawRepComparisons(charts.filter { $0.points.isEmpty }.map(\.variant))
        }

        private func regionColors(_ region: StrengthProgress.BodyRegion) -> (UIColor, UIColor) {
            switch region {
            case .lower: (mintWash, green)
            case .upper: (Self.rgb(0xEEEBFC), Self.rgb(0x5140B8))
            case .core: (amberWash, amberInk)
            case .other: (canvas, soft)
            }
        }

        private func regionChip(_ region: StrengthProgress.BodyRegion) {
            let text = language.text(region.rawValue)
            let (background, foreground) = regionColors(region)
            let chip = measure(text, size: 9.5, weight: .semibold) + 18
            let frame = CGRect(x: left, y: y, width: chip, height: 19)
            glass(frame, radius: 9.5, tint: background, opacity: 0.85)
            centered(text, in: frame, size: 9.5, weight: .semibold, color: foreground)
        }

        private func metaLine(_ variant: StrengthProgress.ExerciseHistory) -> [String] {
            let totals = [(language.text("Recorded reps"), recordedReps(variant.totals)),
                          (language.text("Lifted volume"), liftedVolume(variant.totals))]
                .compactMap { key, value in value.map { key + " " + $0 } }
            guard !totals.isEmpty else { return [] }
            let sessions = language.text("Sessions") + " " + String(variant.sessionCount)
            return wrapped(([language.text(report.period.rawValue), sessions] + totals).joined(separator: "   ·   "),
                           width: width - 150, size: 10.5, weight: .medium)
        }

        private func display(_ point: ChartPoint) -> String {
            let reps = point.reps.map { language.format("%d reps", $0) }
            guard point.value > 0 else { return ([reps].compactMap { $0 } + [language.text("Bodyweight")]).joined(separator: " · ") }
            return (reps.map { $0 + " × " } ?? "") + weight(point.value)
        }

        private func drawExerciseHeader(_ variant: StrengthProgress.ExerciseHistory, change: Double?) {
            let headerTop = y
            regionChip(variant.familyRegion)
            var badgeBottom = headerTop
            if let change {
                let delta = (change > 0 ? "+" : "") + weight(change)
                let badgeWidth = max(96, measure(delta, size: 21, weight: .heavy, rounded: true) + 34)
                let badge = CGRect(x: right - badgeWidth, y: headerTop, width: badgeWidth, height: 56)
                glass(badge, radius: 18, tint: change > 0 ? mint : .white, opacity: change > 0 ? 0.55 : 0.6)
                label(language.text("Change"), badge.minX, badge.minY + 8, badgeWidth, size: 9.5, weight: .semibold, color: muted, alignment: .center)
                label(delta, badge.minX, badge.minY + 22, badgeWidth, size: 21, weight: .heavy, color: change > 0 ? green : soft,
                      alignment: .center, rounded: true)
                badgeBottom = badge.maxY
            }
            y += 28
            let heading = chartHeading(variant)
            let size = fittingSize(heading, width: width - 150, sizes: [26, 23, 20, 18], weight: .heavy)
            for part in wrapped(heading, width: width - 150, size: size, weight: .heavy) {
                label(part, left, y, width - 150, size: size, weight: .heavy)
                y += size + 6
            }
            for part in metaLine(variant) {
                label(part, left, y, width - 150, size: 10.5, weight: .medium, color: muted)
                y += 15
            }
            y = max(y, badgeBottom) + 14
        }

        private func drawChartCard(_ points: [ChartPoint], height: CGFloat, single: String?) {
            guard let first = points.first, let last = points.last, let bestAt = bestIndex(points) else { return }
            let best = points[bestAt]
            // The axis runs to the report's last day, so an exercise not done lately shows the gap instead of looking cut off.
            let end = report.reportDates.flatMap { APEXDateMath.date(from: $0.upperBound) }.map { max($0, last.date) } ?? last.date
            let calendar = WorkoutChartCalendar(first: first.date, last: end)
            let field = CGRect(x: left, y: y, width: width, height: height)
            glass(field, radius: 24, opacity: 0.55)
            drawPlot(points, calendar: calendar, in: field, best: bestAt)
            y = field.maxY + 12
            func endpoint(_ title: String, _ index: Int) -> String {
                language.text(title) + " · #" + String(index + 1) + " · " + calendar.label(points[index].date, locale: locale)
            }
            let bestDate = best.date.formatted(Date.FormatStyle(locale: locale, timeZone: .gmt).year().month(.abbreviated).day())
            let tiles: [(String, String, UIColor, UIColor)] = [
                (endpoint("First", 0), display(first), .white, ink),
                (endpoint("Latest", points.count - 1), display(last), .white, ink),
                ("★ " + language.text("Best working load"), display(best) + "\n" + bestDate, amberWash, amberInk),
            ]
            let gap: CGFloat = 10
            let tileWidth = (width - gap * 2) / 3
            for (index, tile) in tiles.enumerated() {
                let x = left + CGFloat(index) * (tileWidth + gap)
                glass(CGRect(x: x, y: y, width: tileWidth, height: 58), radius: 16, tint: tile.2, opacity: index == 2 ? 0.82 : 0.6)
                label(tile.0, x + 13, y + 9, tileWidth - 26, size: 8.8, weight: .semibold, color: index == 2 ? amberInk : muted)
                let parts = tile.1.components(separatedBy: "\n")
                let fitted: CGFloat = measure(parts[0], size: 14, weight: .bold, rounded: true) > tileWidth - 26 ? 11.5 : 14
                label(parts[0], x + 13, y + 23 + (14 - fitted) / 2, tileWidth - 26, size: fitted, weight: .bold, color: tile.3, rounded: true)
                if parts.count > 1 { label(parts[1], x + 13, y + 40, tileWidth - 26, size: 8.8, weight: .medium, color: muted) }
            }
            y += 68
            if let single {
                label(single, left, y, width, size: 11, weight: .semibold, color: green)
                y += 20
            }
        }

        /// The recorded sessions behind the chart on a timeline that runs first to latest, left to right, like the chart.
        private func drawSessionLog(_ points: [ChartPoint]) {
            let available = bottom - y - 14
            guard available > 100, let bestAt = bestIndex(points) else { return }
            let columns = 3, rowHeight: CGFloat = 46
            let rows = min(3, Int((available - 54) / rowHeight), (points.count + columns - 1) / columns)
            guard rows > 0 else { return }
            // Never more than nine: a longer history is sampled evenly so the list still spans the whole period.
            let shown = AvatarReport.sessionSample(count: points.count, limit: rows * columns, keeping: bestAt).map { (offset: $0, element: points[$0]) }
            let usedRows = (shown.count + columns - 1) / columns
            let card = CGRect(x: left, y: y + 6, width: width, height: 50 + CGFloat(usedRows) * rowHeight)
            glass(card, radius: 22, opacity: 0.5)
            label(language.text("Sessions"), left + 20, card.minY + 14, 200, size: 12, weight: .bold)
            label(language.text("First") + "  →  " + language.text("Latest") + "   ·   " + language.format("%d sessions", points.count),
                  right - 300, card.minY + 15, 280, size: 10, weight: .medium, color: muted, alignment: .right)
            let columnWidth = (width - 40) / CGFloat(columns)
            let latestAt = points.count - 1
            for (slot, entry) in shown.enumerated() {
                let column = slot % columns
                let x = left + 20 + CGFloat(column) * columnWidth
                let top = card.minY + 42 + CGFloat(slot / columns) * rowHeight
                let isBest = entry.offset == bestAt, isLatest = entry.offset == latestAt
                // The rail carries the eye from one session to the next; an arrowhead closes each step.
                if slot < shown.count - 1 {
                    let railEnd = column == columns - 1 ? x + columnWidth - 26 : x + columnWidth - 4
                    fill(CGRect(x: x + 9, y: top + 3.6, width: railEnd - x - 9, height: 0.9), ink.withAlphaComponent(0.16))
                    let tip = UIBezierPath()
                    tip.move(to: CGPoint(x: railEnd, y: top + 4))
                    tip.addLine(to: CGPoint(x: railEnd - 5, y: top + 1.2))
                    tip.addLine(to: CGPoint(x: railEnd - 5, y: top + 6.8))
                    tip.close()
                    ink.withAlphaComponent(0.28).setFill()
                    tip.fill()
                }
                if isBest || isLatest {
                    fill(CGRect(x: x - 8, y: top + 10, width: columnWidth - 10, height: rowHeight - 14),
                         (isBest ? amberWash : mint).withAlphaComponent(isBest ? 0.85 : 0.5), radius: 10)
                }
                dot(CGPoint(x: x + 4, y: top + 4), radius: 4, fill: isBest ? amber : series, ring: 0)
                if !isBest && !isLatest { dot(CGPoint(x: x + 4, y: top + 4), radius: 2.2, fill: .white, ring: 0) }
                label("#" + String(entry.offset + 1) + " · " + language.dateKey(entry.element.day), x, top + 13, columnWidth - 22, size: 8.8,
                      weight: .medium, color: isBest ? amberInk : muted)
                label((isBest ? "★ " : "") + display(entry.element), x, top + 25, columnWidth - 22, size: 11.5, weight: .bold,
                      color: isBest ? amberInk : isLatest ? green : ink, rounded: true)
            }
            y = card.maxY + 8
        }

        /// Clean, evenly spaced load ticks in the viewer's unit, with headroom above the heaviest point.
        private func niceScale(_ peak: Double) -> (step: Double, top: Double) {
            guard peak > 0 else { return (1, 1) }
            let rough = peak / 3.5
            let magnitude = pow(10, floor(log10(rough)))
            let step = [1, 2, 2.5, 5, 10].first { rough / magnitude <= $0 }.map { $0 * magnitude } ?? 10 * magnitude
            var top = (peak / step).rounded(.up) * step
            if peak / top > 0.92 { top += step }
            return (step, top)
        }

        private func drawPlot(_ points: [ChartPoint], calendar: WorkoutChartCalendar, in field: CGRect, best: Int) {
            let plot = CGRect(x: field.minX + 58, y: field.minY + 34, width: field.width - 58 - 30, height: field.height - 34 - 36)
            let values = points.map { report.unit.value(fromKilograms: $0.value) }
            let (step, ceiling) = niceScale(values.max() ?? 0)
            var tick = 0.0
            while tick <= ceiling + step / 2 {
                let tickY = plot.maxY - CGFloat(tick / ceiling) * plot.height
                fill(CGRect(x: plot.minX, y: tickY - 0.35, width: plot.width, height: tick == 0 ? 1 : 0.7), ink.withAlphaComponent(tick == 0 ? 0.14 : 0.06))
                label(number(tick) + " " + report.unit.suffix, field.minX + 8, tickY - 6.5, 42, size: 8.5, color: muted,
                      alignment: .right, rounded: true)
                tick += step
            }
            for date in calendar.ticks {
                let x = plot.minX + calendar.position(date) * plot.width
                fill(CGRect(x: x - 0.35, y: plot.maxY, width: 0.7, height: 4), ink.withAlphaComponent(0.18))
                label(calendar.label(date, locale: locale), x - 36, plot.maxY + 10, 72, size: 8.5, color: muted, alignment: .center)
            }
            let positions = calendar.positions(for: points.map(\.date))
            let coordinates = zip(values, positions).map { value, position in
                CGPoint(x: plot.minX + position * plot.width, y: plot.maxY - CGFloat(value / ceiling) * plot.height)
            }
            drawCurve(coordinates, baseline: plot.maxY, in: plot)
            let latest = coordinates.count - 1
            if let last = coordinates.last, plot.maxX - last.x > 12, let day = points.last?.day {
                let dash = UIBezierPath()
                dash.move(to: CGPoint(x: last.x + 8, y: last.y))
                dash.addLine(to: CGPoint(x: plot.maxX, y: last.y))
                dash.lineWidth = 1.2
                dash.setLineDash([3, 4], count: 2, phase: 0)
                ink.withAlphaComponent(0.22).setStroke()
                dash.stroke()
                // Beside the dashed line when it fits after the latest point; otherwise in the card's top corner,
                // so it never covers the curve or the latest point.
                let note = language.format("No sessions since %@", language.dateKey(day))
                if plot.maxX - last.x - 16 >= measure(note, size: 8.5, weight: .semibold) {
                    let noteY = last.y + 22 > plot.maxY ? last.y - 17 : last.y + 6
                    label(note, plot.maxX - 220, noteY, 220, size: 8.5, weight: .semibold, color: muted, alignment: .right)
                } else {
                    label(note, field.maxX - 236, field.minY + 12, 220, size: 8.5, weight: .semibold, color: muted, alignment: .right)
                }
            }
            let dense = coordinates.count > 30
            for (index, point) in coordinates.enumerated() where index != best && index != latest {
                if dense {
                    dot(point, radius: 2.2, fill: series, ring: 0)
                } else {
                    dot(point, radius: 3.8, fill: series, ring: 0)
                    dot(point, radius: 2.2, fill: .white, ring: 0)
                }
            }
            dot(coordinates[best], radius: 14, fill: amber.withAlphaComponent(0.18), ring: 0)
            dot(coordinates[best], radius: 6.4, fill: amber, ring: 2.2)
            if best != latest {
                dot(coordinates[latest], radius: 11, fill: series.withAlphaComponent(0.16), ring: 0)
                dot(coordinates[latest], radius: 5, fill: series, ring: 2)
            }
            // Label the record and the latest session; everything else lives in the axis, tiles and session list.
            func pill(_ text: String, at point: CGPoint, fill color: UIColor, below: Bool) -> CGRect {
                let pillWidth = measure(text, size: 9, weight: .bold, rounded: true) + 16
                var frame = CGRect(x: point.x - pillWidth / 2, y: below ? point.y + 13 : point.y - 31, width: pillWidth, height: 18)
                frame.origin.x = min(max(frame.minX, plot.minX - 6), field.maxX - pillWidth - 8)
                if frame.minY < field.minY + 4 { frame.origin.y = point.y + 13 }
                glass(frame, radius: 9, tint: color, opacity: 0.95)
                centered(text, in: frame, size: 9, weight: .bold, color: .white, rounded: true)
                return frame
            }
            let recordText = "★ " + (points[best].value > 0 ? weight(points[best].value) : language.text("Bodyweight"))
            let record = pill(recordText, at: coordinates[best], fill: amber, below: false)
            if best != latest {
                let text = points[latest].value > 0 ? weight(points[latest].value) : language.text("Bodyweight")
                let probe = CGRect(x: coordinates[latest].x - 40, y: coordinates[latest].y - 31, width: 80, height: 18)
                _ = pill(text, at: coordinates[latest], fill: ink, below: probe.insetBy(dx: -4, dy: -2).intersects(record))
            }
        }

        private func dot(_ point: CGPoint, radius: CGFloat, fill color: UIColor, ring: CGFloat) {
            if ring > 0 {
                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(x: point.x - radius - ring, y: point.y - radius - ring,
                                            width: (radius + ring) * 2, height: (radius + ring) * 2)).fill()
            }
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)).fill()
        }

        private func repEndpoints(_ variant: StrengthProgress.ExerciseHistory) -> (StrengthProgress.SessionTotals, StrengthProgress.SessionTotals)? {
            let complete = variant.sessions.lazy.filter { !$0.totals.missingReps && $0.totals.reps > 0 }
            guard let first = complete.first, let last = complete.last, first.sessionID != last.sessionID else { return nil }
            return (first, last)
        }

        private func drawRepComparisons(_ variants: [StrengthProgress.ExerciseHistory]) {
            func heading() {
                begin("Reps per session", subtitle: "")
                glass(CGRect(x: left, y: y, width: width, height: 26), radius: 13, opacity: 0.6)
                for (key, x, width) in [("Exercise", 50, 240), ("First", 300, 110), ("Latest", 420, 120)] {
                    label(language.text(key), CGFloat(x), y + 7, CGFloat(width), size: 9.5, weight: .bold, color: muted)
                }
                y += 34
            }

            var started = false
            for variant in variants {
                guard let (first, last) = repEndpoints(variant) else { continue }
                let hands = handLoadSections(variant)
                let title = wrapped(chartHeading(variant), width: 240, size: 14, weight: .bold)
                let height = CGFloat(title.count) * 18 + 32 + handLoadHeight(hands)
                if !started || y + height > bottom { heading() }
                started = true
                glass(CGRect(x: left, y: y, width: width, height: max(CGFloat(title.count) * 18 + 24, 46) + 12), radius: 18, opacity: 0.55)
                y += 10
                let rowTop = y
                let change = last.totals.reps - first.totals.reps
                for (session, x) in [(first, CGFloat(300)), (last, CGFloat(420))] {
                    label(number(Double(session.totals.reps)), x, y, 70, size: 18, weight: .bold, rounded: true)
                    label(language.dateKey(session.date), x, y + 23, 110, size: 9.5, color: muted)
                }
                if change != 0 {
                    let text = (change > 0 ? "+" : "") + number(Double(change))
                    let chip = measure(text, size: 9, weight: .bold, rounded: true) + 12
                    let latestWidth = measure(number(Double(last.totals.reps)), size: 18, weight: .bold, rounded: true)
                    let frame = CGRect(x: 420 + latestWidth + 6, y: y + 4, width: chip, height: 15)
                    glass(frame, radius: 7.5, tint: change > 0 ? mint : .white, opacity: 0.75)
                    centered(text, in: frame, size: 9, weight: .bold, color: change > 0 ? green : soft, rounded: true)
                }
                for part in title {
                    if y + 20 > bottom { heading() }
                    label(part, left + 10, y, 240, size: 14, weight: .bold)
                    y += 18
                }
                label(language.text(variant.familyRegion.rawValue), left + 10, y + 1, 240, size: 10, weight: .medium,
                      color: regionColors(variant.familyRegion).1)
                y = max(y + 18, rowTop + 40)
                y += 10
                drawHandLoadSections(hands)
                y += 8
            }
        }

        // MARK: Push-up hand load

        private struct HandLoadCard {
            let session: UUID
            let date: String
            let fromBodyKG: Double?
            let bodyKG: Double?
            let addedKG: Double?
            let estimateKG: Double?
            let atCurrentMass: Bool
            let position: StrengthProgress.PushUpLoadGuide.Position
        }

        /// One headline estimate per stage, with the reference heights kept to a quiet table beneath.
        private struct HandLoad {
            struct Stage {
                let title: String
                let card: HandLoadCard
                let estimate: Double
                let bodyPart: Double
                var isRecord = false
            }
            struct Table {
                let title: String
                let groups: [(title: String, columns: [String])]
                let rows: [(String, [String])]
            }
            var reference = ""
            var stages: [Stage] = []
            var tables: [Table] = []
            var bodyweightSets = 0
            var bodyweightReps = 0
            var isEmpty: Bool { stages.isEmpty && tables.isEmpty && bodyweightSets == 0 }
        }

        private func approximateWeight(_ kg: Double) -> String {
            "≈ " + number(report.unit.value(fromKilograms: kg).rounded()) + " " + report.unit.suffix
        }

        private func handLoadSections(_ variant: StrengthProgress.ExerciseHistory) -> HandLoad {
            var load = HandLoad()
            load.bodyweightSets = variant.sessions.reduce(0) { $0 + $1.bodyweightPushUpSets }
            load.bodyweightReps = variant.sessions.reduce(0) { $0 + $1.bodyweightPushUpReps }
            guard let guide = StrengthProgress.PushUpLoadGuide.shared else { return load }
            let rows: [HandLoadCard] = variant.sessions.compactMap { row in
                guard let set = row.pushUp else { return nil }
                let historical = report.bodyweightBySession[row.sessionID]
                let body = historical ?? report.currentBodyweight
                let kg = body.flatMap { mass -> Double? in
                    guard set.position == .floor || set.position == .levelFloorReference,
                          (10...500).contains(mass), (set.addedKG ?? 0) <= guide.maxStudiedAddedKg else { return nil }
                    return mass * guide.bodyweightFraction + (set.addedKG ?? 0) * guide.addedWeightFraction
                }
                return HandLoadCard(session: row.sessionID, date: row.date, fromBodyKG: body.map { $0 * guide.bodyweightFraction },
                                    bodyKG: body, addedKG: set.addedKG, estimateKG: kg,
                                    atCurrentMass: historical == nil && body != nil, position: set.position)
            }
            guard let last = rows.last else { return load }
            func endpoints(_ values: [HandLoadCard]) -> [(String, HandLoadCard)] {
                guard let first = values.first, let last = values.last else { return [] }
                return (first.session == last.session ? [] : [(language.text("First"), first)]) + [(language.text("Latest"), last)]
            }
            func heights(_ refs: [StrengthProgress.PushUpLoadGuide.Elevation], _ card: HandLoadCard, added: Double = 0) -> [String] {
                refs.map { reference in
                    // The level floor uses the same coefficient as the level-floor estimate on this page.
                    let fraction = reference.heightCm == 0 ? guide.bodyweightFraction : reference.bodyweightFraction
                    return approximateWeight((card.bodyKG ?? 0) * fraction + added * guide.addedWeightFraction)
                }
            }
            func stamp(_ name: String, _ card: HandLoadCard) -> String { name + " · " + language.dateKey(card.date) }
            let narrow = last.position == .narrowGrip
            if rows.contains(where: { $0.estimateKG != nil }) {
                var stages = endpoints(rows).compactMap { name, card in
                    card.estimateKG.map { HandLoad.Stage(title: name, card: card, estimate: $0, bodyPart: card.fromBodyKG ?? $0) }
                }
                let best = rows.filter { !$0.atCurrentMass && $0.position == .floor && $0.addedKG != nil && $0.estimateKG != nil }
                    .max { ($0.estimateKG ?? 0) < ($1.estimateKG ?? 0) }
                if let best, let estimate = best.estimateKG {
                    if let index = stages.firstIndex(where: { $0.card.session == best.session }) {
                        stages[index].isRecord = true
                    } else {
                        stages.append(HandLoad.Stage(title: language.text("Personal record"), card: best, estimate: estimate,
                                                     bodyPart: best.fromBodyKG ?? estimate, isRecord: true))
                    }
                }
                load.stages = stages
                if last.position == .levelFloorReference { load.reference = language.text("Level-floor reference") }
            }
            let references = rows.filter { $0.position != .floor && $0.bodyKG != nil }
            if narrow {
                load.reference = language.text("Narrow-grip reference · Half shoulder width")
                load.stages = endpoints(references).map { name, card in
                    let body = (card.bodyKG ?? 0) * guide.narrowGripBodyweightFraction
                    let added = (card.addedKG ?? 0) <= guide.maxStudiedAddedKg ? (card.addedKG ?? 0) * guide.addedWeightFraction : 0
                    return HandLoad.Stage(title: name, card: card, estimate: body + added, bodyPart: body)
                }
            } else {
                let base = endpoints(references)
                let loaded = endpoints(references.filter { ($0.addedKG ?? 0) > 0 && ($0.addedKG ?? 0) <= guide.maxStudiedAddedKg })
                if !base.isEmpty {
                    func cm(_ value: Double) -> Int { Int(value.rounded()) }
                    let heightsCm = (guide.feetElevatedReferences.map { cm($0.heightCm) } + guide.feetElevatedStaticReferences.map { cm($0.heightCm) })
                        .reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }.sorted()
                    var groups = [(title: language.text("Without backpack"), columns: base.map { stamp($0.0, $0.1) })]
                    if !loaded.isEmpty {
                        groups.append((language.text("With backpack"),
                                       loaded.map { stamp($0.0, $0.1) + " · " + language.text("Added weight") + " · " + weight($0.1.addedKG ?? 0) }))
                    }
                    let rows = heightsCm.map { height -> (String, [String]) in
                        let plain = guide.feetElevatedReferences.firstIndex { cm($0.heightCm) == height }
                        let backpack = guide.feetElevatedStaticReferences.firstIndex { cm($0.heightCm) == height }
                        let values = base.map { stage in plain.map { heights(guide.feetElevatedReferences, stage.1)[$0] } ?? "—" }
                            + loaded.map { stage in
                                backpack.map { heights(guide.feetElevatedStaticReferences, stage.1, added: stage.1.addedKG ?? 0)[$0] } ?? "—"
                            }
                        return (language.format("%@ cm", String(height)), values)
                    }
                    load.tables.append(HandLoad.Table(
                        title: language.text("Feet elevated · Peak load from bodyweight") + " · " + language.text("Reference heights"),
                        groups: groups, rows: rows))
                }
            }
            return load
        }

        private func handLoadHeight(_ load: HandLoad) -> CGFloat {
            load.isEmpty ? 0 : handLoadContent(load, top: 0, draw: false) + 10
        }

        /// Lays out (and optionally draws) the hand-load card; returns its height.
        @discardableResult
        private func handLoadContent(_ load: HandLoad, top: CGFloat, draw: Bool) -> CGFloat {
            let pad: CGFloat = 20, inner = width - pad * 2
            var cursor = top + 18
            let onlyCounts = load.stages.isEmpty && load.tables.isEmpty
            if draw {
                label(language.text(onlyCounts ? "Recorded reps" : "Estimated load at the hands"), left + pad, cursor + 1, inner - 200, size: 13,
                      weight: .heavy)
                if !load.reference.isEmpty {
                    label(load.reference, right - pad - 230, cursor + 3, 230, size: 9.5, weight: .semibold, color: green, alignment: .right)
                }
            }
            cursor += 30
            if !load.stages.isEmpty {
                let gap: CGFloat = 14
                let columnWidth = (inner - gap * CGFloat(load.stages.count - 1)) / CGFloat(load.stages.count)
                let scale = load.stages.map(\.estimate).max() ?? 1
                var lowest = cursor
                for (index, stage) in load.stages.enumerated() {
                    let x = left + pad + CGFloat(index) * (columnWidth + gap)
                    let card = stage.card
                    let added = card.addedKG ?? 0
                    let isLatest = stage.title == language.text("Latest")
                    let accent = stage.isRecord ? amberInk : isLatest ? green : ink
                    var line = cursor
                    if draw {
                        let title = stage.title + (stage.isRecord && stage.title != language.text("Personal record") ? " · " + language.text("Personal record") : "")
                        label((stage.isRecord ? "★ " : "") + title + " · " + language.dateKey(card.date), x, line, columnWidth, size: 9,
                              weight: .bold, color: stage.isRecord ? amberInk : muted)
                        label(approximateWeight(stage.estimate), x, line + 13, columnWidth, size: 26, weight: .heavy, color: accent, rounded: true)
                        label(language.text(added > 0 ? "With backpack" : "Without backpack"), x, line + 48, columnWidth, size: 10, weight: .semibold, color: soft)
                        let track = CGRect(x: x, y: line + 66, width: columnWidth, height: 8)
                        fill(track, ink.withAlphaComponent(0.06), radius: 4)
                        let total = track.width * CGFloat(stage.estimate / scale)
                        let bodyWidth = total * CGFloat(min(1, stage.bodyPart / max(stage.estimate, 0.1)))
                        gradient(CGRect(x: x, y: track.minY, width: max(8, bodyWidth), height: 8), [glow, series], vertical: false, radius: 4)
                        if total - bodyWidth > 1 {
                            gradient(CGRect(x: x + bodyWidth + 1.5, y: track.minY, width: max(4, total - bodyWidth - 1.5), height: 8),
                                     [Self.rgb(0xFFC53D), amber], vertical: false, radius: 4)
                        }
                        if index > 0, load.stages.first?.title == language.text("First"), isLatest {
                            let change = stage.estimate - load.stages[0].estimate
                            if abs(report.unit.value(fromKilograms: change)) >= 0.5 {
                                let text = (change > 0 ? "+" : "−") + approximateWeight(abs(change)).replacingOccurrences(of: "≈ ", with: "")
                                let chip = measure(text, size: 9.5, weight: .bold, rounded: true) + 14
                                let valueWidth = measure(approximateWeight(stage.estimate), size: 26, weight: .heavy, rounded: true)
                                let frame = CGRect(x: x + valueWidth + 8, y: line + 22, width: chip, height: 18)
                                glass(frame, radius: 9, tint: change > 0 ? mint : .white, opacity: 0.8)
                                centered(text, in: frame, size: 9.5, weight: .bold, color: change > 0 ? green : soft, rounded: true)
                            }
                        }
                    }
                    line += 82
                    var notes: [(String, UIColor?)] = []
                    if added > 0 {
                        notes.append((language.text("Without backpack") + " · " + approximateWeight(stage.bodyPart), series))
                        notes.append((language.text("Added weight") + " · " + weight(added), amber))
                    } else {
                        notes.append((language.text(card.addedKG == nil ? "Added weight not recorded" : "Bodyweight only"), nil))
                    }
                    if let body = card.bodyKG {
                        notes.append((language.text(card.atCurrentMass ? "At current bodyweight" : "Bodyweight") + " · " + weight(body), nil))
                    }
                    for (text, swatch) in notes {
                        if draw {
                            if let swatch { fill(CGRect(x: x, y: line + 4, width: 6, height: 6), swatch, radius: 3) }
                            label(text, x + (swatch == nil ? 0 : 10), line, columnWidth - 10, size: 9, color: soft)
                        }
                        line += 13
                    }
                    lowest = max(lowest, line)
                }
                cursor = lowest + 8
            }
            for table in load.tables {
                if draw { fill(CGRect(x: left + pad, y: cursor, width: inner, height: 0.8), UIColor.white.withAlphaComponent(0.95)) }
                cursor += 9
                let titleLines = wrapped(table.title, width: inner, size: 9, weight: .bold)
                for part in titleLines {
                    if draw { label(part, left + pad, cursor, inner, size: 9, weight: .bold, color: green) }
                    cursor += 13
                }
                let labelWidth: CGFloat = 54
                let columnCount = table.groups.reduce(0) { $0 + $1.columns.count }
                let columnWidth = (inner - labelWidth) / CGFloat(max(1, columnCount))
                var column = 0
                var headerHeight: CGFloat = 0
                for group in table.groups {
                    let x = left + pad + labelWidth + CGFloat(column) * columnWidth
                    if draw {
                        label(group.title, x, cursor, columnWidth * CGFloat(group.columns.count) - 8, size: 9, weight: .bold, color: soft)
                        fill(CGRect(x: x, y: cursor + 13, width: columnWidth * CGFloat(group.columns.count) - 10, height: 0.8), ink.withAlphaComponent(0.1))
                    }
                    for (offset, title) in group.columns.enumerated() {
                        let lines = wrapped(title, width: columnWidth - 8, size: 8.5, weight: .semibold)
                        if draw {
                            for (line, part) in lines.enumerated() {
                                label(part, x + CGFloat(offset) * columnWidth, cursor + 17 + CGFloat(line) * 11, columnWidth - 8,
                                      size: 8.5, weight: .semibold, color: muted)
                            }
                        }
                        headerHeight = max(headerHeight, 17 + CGFloat(lines.count) * 11)
                    }
                    column += group.columns.count
                }
                cursor += headerHeight + 3
                for (name, values) in table.rows {
                    if draw {
                        label(name, left + pad, cursor, labelWidth, size: 10, weight: .semibold, color: soft)
                        for (index, value) in values.enumerated() {
                            label(value, left + pad + labelWidth + CGFloat(index) * columnWidth, cursor, columnWidth - 8, size: 10.5,
                                  weight: .bold, color: ink, rounded: true)
                        }
                    }
                    cursor += 15
                }
                cursor += 4
            }
            if load.bodyweightSets > 0 {
                let text = language.text("Bodyweight only") + "   ·   " + language.text("Sets") + " · " + number(Double(load.bodyweightSets))
                    + "   ·   " + language.format("%d reps", load.bodyweightReps)
                if draw {
                    let chip = min(inner, measure(text, size: 10, weight: .semibold) + 24)
                    glass(CGRect(x: left + pad, y: cursor + 2, width: chip, height: 24), radius: 12, opacity: 0.7)
                    label(text, left + pad + 12, cursor + 7, chip - 24, size: 10, weight: .semibold, color: soft)
                }
                cursor += 32
            }
            return cursor + 10 - top
        }

        private func drawHandLoadSections(_ load: HandLoad) {
            guard !load.isEmpty else { return }
            let height = handLoadContent(load, top: 0, draw: false)
            if y + 6 + height > bottom { continuePage() }
            let frame = CGRect(x: left, y: y + 6, width: width, height: height)
            glass(frame, radius: 24, tint: mint, opacity: 0.28)
            handLoadContent(load, top: frame.minY, draw: true)
            y = frame.maxY + 6
        }

        // MARK: Working leg

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
                let loadKG: Double?
                let combined: String?
                let bodyNote: String?
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
            var height: CGFloat { record == nil ? 234 : 296 }
        }

        private func legPanel(_ variant: StrengthProgress.ExerciseHistory) -> LegPanel? {
            let id = variant.key.hasPrefix("movement:") ? String(variant.key.dropFirst(9)) : ExerciseCatalog.movementID(matchingName: variant.name)
            // Before, after and the record all come from sessions with a recorded working load, like the chart.
            let eligible = variant.sessions.filter { $0.heaviestSet != nil }
            guard let id, var support = Self.legGuide[id], let earliest = report.earlierFirst[variant.key] ?? eligible.first,
                  let latest = eligible.last else { return nil }
            let words = Set(variant.name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            if !words.isDisjoint(with: ["or", "assisted", "supported", "machine", "smith", "cable", "band"]) { support = .externalOnly }
            func body(_ row: StrengthProgress.SessionTotals) -> (kg: Double, date: String?)? {
                if let kg = report.bodyweightBySession[row.sessionID] { return (kg, nil) }
                return report.laterBodyweightBySession[row.sessionID].map { ($0.kg, $0.date) }
            }
            func combined(_ row: StrengthProgress.SessionTotals) -> Double? {
                guard support != .externalOnly, let kg = row.heaviestSet?.kg, let body = body(row) else { return nil }
                return body.kg + kg
            }
            func entry(_ row: StrengthProgress.SessionTotals) -> LegPanel.Entry {
                let total = combined(row)
                let estimate: String? = total.flatMap { all in
                    guard support == .rearFootElevated else { return nil }
                    let units = report.unit.value(fromKilograms: all * 0.8436)
                    return "≈ " + number(units.rounded()) + " " + report.unit.suffix
                }
                let bodyNote = total == nil ? nil : body(row).map { measured in
                    language.text("Bodyweight") + " · " + weight(measured.kg) + (measured.date.map { " · " + language.dateKey($0) } ?? "")
                }
                return .init(date: language.dateKey(row.date), load: row.heaviestSet.map { weight($0.kg) } ?? language.text("Not recorded"),
                             loadKG: row.heaviestSet?.kg, combined: total.map(weight), bodyNote: bodyNote, estimate: estimate,
                             recordedReps: row.heaviestSet == nil ? row.totals.recordedReps.map { language.format("%d reps", $0) } : nil)
            }
            // A personal record is the heaviest working load (then most reps); bodyweight changes cannot set one.
            let peak = eligible.max { lhs, rhs in
                let a = lhs.heaviestSet.map { ($0.kg, $0.reps) } ?? (0, 0)
                let b = rhs.heaviestSet.map { ($0.kg, $0.reps) } ?? (0, 0)
                return a < b
            }
            let record = peak.flatMap { row in
                row.heaviestSet.map { set in
                    LegPanel.Record(added: weight(set.kg), combined: combined(row).map(weight),
                                    performance: language.format("%d reps", set.reps) + " · " + language.dateKey(row.date))
                }
            }
            return LegPanel(movement: id, before: entry(earliest), after: entry(latest),
                            estimateLabel: language.text("Front foot · estimated"), record: record)
        }

        private func drawLegPanel(_ panel: LegPanel) {
            if y + 14 + panel.height > bottom { continuePage() }
            y += 14
            let frame = CGRect(x: left, y: y, width: width, height: panel.height)
            glass(frame, radius: 26, tint: mint, opacity: 0.3)
            label(language.text("Working leg"), left + 18, y + 14, 280, size: 16, weight: .heavy)
            if let joined = report.joinedDate {
                label(language.text("Joined FITR MAX") + " · " + language.dateKey(joined), left + 290, y + 18, width - 308,
                      size: 9, color: muted, alignment: .right)
            }
            let illustration = Bundle.main.url(forResource: panel.movement, withExtension: "webp", subdirectory: "leg-anatomy")
                .flatMap { UIImage(contentsOfFile: $0.path) }
            let tileTop = y + 46, tileHeight: CGFloat = 172, arrowGap: CGFloat = 36
            let tileWidth = (width - 28 - arrowGap) / 2
            for (index, entry) in [panel.before, panel.after].enumerated() {
                let x = left + 14 + CGFloat(index) * (tileWidth + arrowGap)
                let tile = CGRect(x: x, y: tileTop, width: tileWidth, height: tileHeight)
                glass(tile, radius: 18, tint: index == 0 ? .white : mint, opacity: index == 0 ? 0.74 : 0.62)
                label(language.text(index == 0 ? "Before" : "After").uppercased(with: locale), x + 14, tile.minY + 12, tileWidth - 28,
                      size: 11, weight: .heavy, color: green)
                label(entry.date, x + 14, tile.minY + 28, tileWidth - 28, size: 15, weight: .semibold)
                if let illustration {
                    let scale = min(60 / illustration.size.width, 88 / illustration.size.height)
                    let size = CGSize(width: illustration.size.width * scale, height: illustration.size.height * scale)
                    illustration.draw(in: CGRect(x: x + 44 - size.width / 2, y: tile.minY + 104 - size.height / 2,
                                                 width: size.width, height: size.height))
                }
                let textX = x + 88, textWidth = tileWidth - 100
                label(language.text("Added weight"), textX, tile.minY + 52, textWidth, size: 10, weight: .semibold, color: muted)
                label(entry.load, textX, tile.minY + 65, textWidth, size: 21, weight: .bold, rounded: true)
                if let combined = entry.combined {
                    label(language.text("Body + load"), textX, tile.minY + 94, textWidth, size: 10, weight: .semibold, color: muted)
                    label(combined, textX, tile.minY + 107, textWidth, size: 21, weight: .bold, color: green, rounded: true)
                }
                if let reps = entry.recordedReps {
                    label(language.text("Recorded reps") + " · " + reps, textX, tile.minY + 98, textWidth, size: 10.5, weight: .semibold)
                }
                // Under the total: the bodyweight it was built from, then the front-foot estimate.
                var noteY = tile.minY + 134
                for note in [entry.bodyNote, entry.estimate.map { panel.estimateLabel + " " + $0 }].compactMap({ $0 }) {
                    for part in wrapped(note, width: textWidth, size: 8.5).prefix(2) {
                        label(part, textX, noteY, textWidth, size: 8.5, color: muted)
                        noteY += 11
                    }
                }
            }
            let center = CGPoint(x: left + 14 + tileWidth + arrowGap / 2, y: tileTop + tileHeight / 2)
            let arrow = CGRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28)
            glass(arrow, radius: 14, opacity: 0.9)
            centered("→", in: arrow, size: 14, weight: .bold, color: green)
            if let before = panel.before.loadKG, let after = panel.after.loadKG, after != before {
                let text = (after > before ? "+" : "") + weight(after - before)
                let chip = measure(text, size: 8.5, weight: .bold, rounded: true) + 10
                let frame = CGRect(x: center.x - chip / 2, y: center.y + 17, width: chip, height: 15)
                glass(frame, radius: 7.5, opacity: 0.9)
                centered(text, in: frame, size: 8.5, weight: .bold, color: green, rounded: true)
            }
            if let record = panel.record {
                let card = CGRect(x: left + 14, y: tileTop + tileHeight + 12, width: width - 28, height: 52)
                glass(card, radius: 18, tint: amberWash, opacity: 0.86)
                let heading = language.text("Personal record").uppercased(with: locale)
                let headingLines = wrapped(heading, width: 200, size: 13, weight: .heavy)
                for (line, part) in headingLines.enumerated() {
                    label(part, card.minX + 18, card.minY + 9 + CGFloat(line) * 15, 200, size: 13, weight: .heavy, color: amberInk)
                }
                label(record.performance, card.minX + 18, card.minY + (headingLines.count > 1 ? 37 : 27), 200, size: 10.5, color: soft)
                let metrics = [(language.text("Added weight"), Optional(record.added), amberInk), (language.text("Body + load"), record.combined, green)]
                for (index, metric) in metrics.enumerated() {
                    guard let value = metric.1 else { continue }
                    let x = card.minX + 222 + CGFloat(index) * 132
                    label(metric.0, x, card.minY + 7, 126, size: 10, weight: .semibold, color: muted)
                    label(value, x, card.minY + 20, 126, size: 20, weight: .bold, color: metric.2, rounded: true)
                }
            }
            y = frame.maxY
        }

        private func chartHeading(_ variant: StrengthProgress.ExerciseHistory) -> String {
            let parts = variant.titleParts(language)
            if let family = variant.familyName {
                let full = variant.name.lowercased()
                let equipmentName = full.hasPrefix("weighted ") ? String(full.dropFirst("weighted ".count)) : full
                for (equipment, label) in [("dumbbell", "With Dumbbells"), ("barbell", "With a Barbell"), ("kettlebell", "With a Kettlebell")] {
                    let name = equipment + " " + family.lowercased()
                    if equipmentName == name || equipmentName == name + "s" {
                        return language.text(family) + " · " + language.text(label)
                    }
                }
            }
            let full = language.text(variant.name)
            return parts.variation.map { $0 == full ? full : parts.main + " · " + $0 } ?? parts.main
        }

        // MARK: Nutrition

        private typealias Copy = (title: String, line: String)

        func drawNutrition(_ nutrition: NutritionReport) {
            begin("Nutrition", subtitle: language.dateKey(nutrition.from) + " – " + language.dateKey(nutrition.to) + "   ·   "
                  + language.format("%d of %d days logged", nutrition.loggedDays, nutrition.periodDays)
                  + (nutrition.partialDays > 0 ? "   ·   " + language.format("%d partly logged", nutrition.partialDays) : ""))
            let gap: CGFloat = 10
            drawScoreHero(nutrition)
            y += gap
            if nutrition.loggedDays > 0 {
                drawMacroRings(nutrition)
                y += gap
                if let calories = nutrition.macros.first(where: { $0.kind == .calories }) {
                    drawCaloriesBar(calories, loggedDays: nutrition.loggedDays)
                    y += gap
                }
            }
            let insights = insightCards(nutrition)
            if !insights.isEmpty {
                drawInsights(insights)
                y += gap
            }
            drawSupplementRow(nutrition)
        }

        private func drawScoreHero(_ nutrition: NutritionReport) {
            let pad: CGFloat = 22
            let copy = verdictCopy(nutrition.verdict)
            let scored = nutrition.score != nil
            let textX = scored ? left + 262 : left + pad
            let textWidth = right - pad - textX
            let title = language.text(copy.title)
            let titleSize = fittingSize(title, width: textWidth, sizes: [18, 16, 14.5], weight: .bold)
            let titleLines = wrapped(title, width: textWidth, size: titleSize, weight: .bold)
            let lines = wrapped(language.text(copy.line), width: textWidth, size: 10.5)
            let blockHeight = CGFloat(titleLines.count) * (titleSize + 5) + 4 + CGFloat(lines.count) * 15
            let card = CGRect(x: left, y: y, width: width, height: max(116, blockHeight + 36))
            glass(card, radius: 24, opacity: 0.6)
            let earned = nutrition.stars >= 4
            let wash = raster(card.size, scale: 2) { cg in
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: card.size), cornerRadius: 24).addClip()
                radial(cg, at: CGPoint(x: 40, y: 10), radius: 260, color: glow, alpha: 0.22)
                radial(cg, at: CGPoint(x: card.width * 0.42, y: card.height + 20), radius: 200, color: earned ? amber : Pages.rgb(0x7CC3F5), alpha: 0.2)
            }
            wash.draw(in: card)
            if let score = nutrition.score {
                label(language.text("Consistency score").uppercased(with: locale), left + pad, y + 18, 220, size: 9.5, weight: .bold, color: green, kern: 0.6)
                let big = font(52, .heavy, rounded: true), small = font(15, .semibold, rounded: true)
                let figure = String(score)
                label(figure, left + pad, y + 29, 160, size: 52, weight: .heavy, rounded: true)
                label("/ 100", left + pad + measure(figure, size: 52, weight: .heavy, rounded: true) + 6, y + 29 + big.ascender - small.ascender,
                      80, size: 15, weight: .semibold, color: muted, rounded: true)
                for index in 0..<5 {
                    drawStar(CGRect(x: left + pad + CGFloat(index) * 21, y: y + 89, width: 17, height: 17), earned: index < nutrition.stars)
                }
                if earned { drawRosette(CGRect(x: left + 168, y: card.midY - 36, width: 58, height: 72)) }
                fill(CGRect(x: textX - 22, y: y + 22, width: 0.8, height: card.height - 44), ink.withAlphaComponent(0.09))
            }
            var cursor = card.midY - blockHeight / 2
            for part in titleLines {
                label(part, textX, cursor, textWidth, size: titleSize, weight: .bold)
                cursor += titleSize + 5
            }
            cursor += 4
            for line in lines {
                label(line, textX, cursor, textWidth, size: 10.5, color: soft)
                cursor += 15
            }
            y = card.maxY
        }

        private func verdictCopy(_ verdict: NutritionReport.Verdict) -> Copy {
            switch verdict {
            case .baseline: return ("Building your baseline", "Log your meals on 7 days with your targets set and your consistency score appears here.")
            case .dialedIn: return ("Dialled in", "You hit your targets day after day. This is the consistency that turns training into results.")
            case .onTarget: return ("On target", "Most of your days land right where they should. A few more steady days and you are dialled in.")
            case .proteinPro: return ("Protein pro", "Your protein is covered almost every day, the part that matters most for muscle. Calories and carbs are your next easy gain.")
            case .onTheRise: return ("On the rise", "Your last two weeks beat your earlier days by a clear margin. Keep this rhythm and your score keeps climbing.")
            case .slippingLately: return ("Time for a reset", "Your last two weeks drifted from the rhythm you had before. You have done it already, so getting back is familiar ground.")
            case .weekendDrift: return ("Weekday strong", "Your weekdays are on point. Bringing weekends a little closer is the quickest way to raise your score.")
            case .solidBase: return ("Solid base", "You are on target more often than not. Tightening one or two meals a day lifts you into the top tier.")
            case .gettingThere: return ("Getting there", "About half your days hit the mark. Every extra on-target day moves your score up.")
            case .findingRhythm: return ("Finding your rhythm", "The habit is forming. Pick one target to hit every day and build from there.")
            case .needsAttention: return ("Room to grow", "Hitting your targets more often gives your training the fuel it needs to show. Start with protein at every meal.")
            }
        }

        private func macroColors(_ kind: NutritionReport.Kind) -> (start: UIColor, end: UIColor, deep: UIColor) {
            switch kind {
            case .protein: return (series, glow, Pages.rgb(0x005443))
            case .carbs: return (Pages.rgb(0x2F7BEA), Pages.rgb(0x7CC8F8), Pages.rgb(0x1A3F98))
            case .fat: return (amber, Pages.rgb(0xFFCF5C), Pages.rgb(0x9A5B00))
            case .calories: return (violet, Pages.rgb(0xB7A6FF), Pages.rgb(0x41329E))
            }
        }

        private func macroName(_ kind: NutritionReport.Kind) -> String {
            switch kind {
            case .calories: return "Calories"
            case .protein: return "Protein"
            case .carbs: return "Carbs"
            case .fat: return "Fat"
            }
        }

        private func drawMacroRings(_ nutrition: NutritionReport) {
            let kinds: [NutritionReport.Kind] = [.protein, .carbs, .fat]
            let gap: CGFloat = 12, height: CGFloat = 160, diameter: CGFloat = 88
            let tileWidth = (width - gap * 2) / 3
            for (index, kind) in kinds.enumerated() {
                guard let macro = nutrition.macros.first(where: { $0.kind == kind }) else { continue }
                let tile = CGRect(x: left + CGFloat(index) * (tileWidth + gap), y: y, width: tileWidth, height: height)
                glass(tile, radius: 22, opacity: 0.6)
                let ring = CGRect(x: tile.midX - diameter / 2, y: tile.minY + 12, width: diameter, height: diameter)
                let ratio = macro.target.map { $0 > 0 ? macro.average / $0 : 0 }
                drawRing(in: ring, ratio: ratio ?? 0, line: 10, colors: macroColors(kind))
                centered(number(macro.average.rounded()) + " g", in: ring, size: 18, weight: .bold, color: ink, rounded: true)
                var cursor = ring.maxY + 8
                centered(language.text(macroName(kind)), in: CGRect(x: tile.minX + 10, y: cursor, width: tile.width - 20, height: 16),
                         size: 12.5, weight: .bold, color: ink)
                cursor += 18
                if let target = macro.target {
                    centered(language.format("Target %d g", Int(target.rounded())), in: CGRect(x: tile.minX + 10, y: cursor, width: tile.width - 20, height: 13),
                             size: 9.5, weight: .medium, color: muted)
                    cursor += 14
                    let rate = Double(macro.metDays) / Double(max(1, nutrition.loggedDays))
                    centered(language.format("On target %d of %d days", macro.metDays, nutrition.loggedDays),
                             in: CGRect(x: tile.minX + 10, y: cursor, width: tile.width - 20, height: 13),
                             size: 9.5, weight: .semibold, color: rate >= 0.7 ? green : amberInk)
                }
            }
            y += height
        }

        /// A gradient gauge with a soft glow; a full ring is the target, and anything over it laps again in a deeper tone.
        private func drawRing(in frame: CGRect, ratio: Double, line: CGFloat, colors: (start: UIColor, end: UIColor, deep: UIColor)) {
            let pad: CGFloat = 12
            let canvas = frame.insetBy(dx: -pad, dy: -pad)
            let image = raster(canvas.size) { cg in
                guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
                let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let radius = (frame.width - line) / 2
                func arc(_ fraction: Double) -> CGPath {
                    UIBezierPath(arcCenter: center, radius: radius, startAngle: -.pi / 2,
                                 endAngle: -.pi / 2 + 2 * .pi * CGFloat(fraction), clockwise: true).cgPath
                }
                cg.setLineCap(.round)
                cg.setLineWidth(line)
                cg.setStrokeColor(ink.withAlphaComponent(0.07).cgColor)
                cg.addPath(UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath)
                cg.strokePath()
                let first = min(1, max(0, ratio))
                guard first > 0.005 else { return }
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 9, color: colors.start.withAlphaComponent(0.5).cgColor)
                cg.setStrokeColor(colors.start.cgColor)
                cg.addPath(arc(first))
                cg.strokePath()
                cg.restoreGState()
                cg.saveGState()
                cg.addPath(arc(first))
                cg.replacePathWithStrokedPath()
                cg.clip()
                if let shading = CGGradient(colorsSpace: space, colors: [colors.end.cgColor, colors.start.cgColor] as CFArray, locations: [0, 1]) {
                    cg.drawLinearGradient(shading, start: CGPoint(x: center.x + radius, y: center.y - radius),
                                          end: CGPoint(x: center.x - radius, y: center.y + radius), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
                cg.restoreGState()
                // A sliver over the target reads as a glitch, so the second lap starts at 3 %.
                let lap = min(1, ratio - 1)
                guard lap >= 0.03 else { return }
                cg.saveGState()
                cg.setShadow(offset: .zero, blur: 4, color: UIColor.black.withAlphaComponent(0.25).cgColor)
                cg.setStrokeColor(colors.deep.cgColor)
                cg.setLineWidth(line * 0.62)
                cg.addPath(arc(lap))
                cg.strokePath()
                cg.restoreGState()
            }
            image.draw(in: canvas)
        }

        private func drawCaloriesBar(_ calories: NutritionReport.Macro, loggedDays: Int) {
            let strip = CGRect(x: left, y: y, width: width, height: 50)
            glass(strip, radius: 18, opacity: 0.6)
            let pad: CGFloat = 18
            label(language.text("Calories"), left + pad, y + 8, 150, size: 12.5, weight: .bold)
            let value = number(calories.average.rounded()) + " " + language.text("kcal")
            if let target = calories.target, target > 0 {
                let rate = Double(calories.metDays) / Double(max(1, loggedDays))
                label(language.format("On target %d of %d days", calories.metDays, loggedDays), left + pad, y + 27, 150,
                      size: 9.5, weight: .semibold, color: rate >= 0.7 ? green : amberInk)
                label(value, right - pad - 150, y + 6, 150, size: 17, weight: .bold, alignment: .right, rounded: true)
                label(language.format("Target %d kcal", Int(target.rounded())), right - pad - 150, y + 28, 150, size: 9.5,
                      weight: .medium, color: muted, alignment: .right)
                let colors = macroColors(.calories)
                let track = CGRect(x: left + 170, y: strip.midY - 4.5, width: width - 170 - 150 - pad - 18, height: 9)
                // The track runs to 125 % of the target so going over stays visible instead of clipping.
                let scale = 1.25, ratio = min(scale, max(0, calories.average / target))
                let mark = track.minX + track.width / scale
                fill(track, ink.withAlphaComponent(0.07), radius: 4.5)
                let reach = track.width * ratio / scale
                if reach > 0 {
                    gradient(CGRect(x: track.minX, y: track.minY, width: max(9, min(reach, mark - track.minX)), height: track.height),
                             [colors.start, colors.end], vertical: false, radius: 4.5)
                }
                if ratio > 1 {
                    fill(CGRect(x: mark - 4.5, y: track.minY, width: track.minX + reach - mark + 4.5, height: track.height), colors.deep, radius: 4.5)
                }
                fill(CGRect(x: mark - 0.75, y: track.minY - 4, width: 1.5, height: track.height + 8), ink.withAlphaComponent(0.55), radius: 0.75)
            } else {
                label(value, right - pad - 150, y + 14, 150, size: 17, weight: .bold, alignment: .right, rounded: true)
            }
            y = strip.maxY
        }

        private enum Insight {
            case focus(NutritionReport.Focus)
            case strength(NutritionReport.Kind, surplus: Bool)
        }

        private func insightCards(_ nutrition: NutritionReport) -> [Insight] {
            let protein = nutrition.macros.first { $0.kind == .protein }
            let surplus = (protein?.overDays ?? 0) * 2 >= max(1, nutrition.loggedDays)
            let strengths = nutrition.strengths.sorted { ($0 == .protein ? 0 : 1) < ($1 == .protein ? 0 : 1) }
            // An earned win leads, then the next gain; whatever is left fills the second card.
            let wins = strengths.map { Insight.strength($0, surplus: $0 == .protein && surplus) }
            let gains = nutrition.focus.map(Insight.focus)
            return Array((wins.prefix(1) + gains + wins.dropFirst()).prefix(2))
        }

        private func insightCopy(_ insight: Insight) -> Copy {
            switch insight {
            case .focus(.proteinLow): return ("Protein is your next gain", "Reaching your protein target consistently gives your muscles the material to recover and grow.")
            case .focus(.caloriesLow): return ("Fuel the work", "Without enough energy, recovery and muscle gain slow down. Eating closer to your target keeps both moving.")
            case .focus(.caloriesHigh): return ("Steer your calories", "Staying near your calorie target keeps your progress pointed at your goal.")
            case .focus(.loggingGaps): return ("Log a few more days", "More logged days make your score a truer picture of how you eat.")
            case .strength(.protein, surplus: true): return ("Protein more than covered", "Your protein is more than covered. Your muscles have everything they need from it.")
            case .strength(.protein, surplus: false): return ("Protein covered", "Enough protein day after day is what lets your training build muscle.")
            case .strength(.calories, _): return ("Energy on target", "Your calories match your goal, so your progress stays on course.")
            case .strength(.carbs, _): return ("Carbs on point", "Steady carbs keep your training fuelled and your sessions strong.")
            case .strength(.fat, _): return ("Fats covered", "Steady fat intake keeps your meals satisfying and your energy even.")
            }
        }

        private func drawInsights(_ insights: [Insight]) {
            let gap: CGFloat = 12, pad: CGFloat = 16, glyph: CGFloat = 30
            let lone = insights.count == 1
            let cardWidth = lone ? width : (width - gap) / 2
            // A lone card is wide enough to set its sentence beside the glyph, under the title.
            let indent = lone ? glyph + 11 : 0
            let copies = insights.map(insightCopy)
            let bodies = copies.map { wrapped(language.text($0.line), width: cardWidth - pad * 2 - indent, size: 10) }
            let lines = CGFloat(bodies.map(\.count).max() ?? 0) * 14
            let titleWidth = cardWidth - glyph - pad * 2 - 11
            let titleSize = copies.map { fittingSize(language.text($0.title), width: titleWidth, sizes: [12.5, 11.5, 10.5], weight: .bold) }.min() ?? 12.5
            let height = lone ? max(72, pad + 24 + lines + pad - 2) : max(88, pad + glyph + 8 + lines + pad - 6)
            for (index, insight) in insights.enumerated() {
                let card = CGRect(x: left + CGFloat(index) * (cardWidth + gap), y: y, width: cardWidth, height: height)
                let reward: Bool
                if case .strength = insight { reward = true } else { reward = false }
                glass(card, radius: 20, tint: reward ? amberWash : .white, opacity: reward ? 0.82 : 0.6)
                let badge = CGRect(x: card.minX + pad, y: card.minY + pad, width: glyph, height: glyph)
                if reward {
                    gradient(badge, [Pages.rgb(0xFFE7A8), Pages.rgb(0xFFC94D)], radius: glyph / 2)
                    drawStar(badge.insetBy(dx: 7, dy: 7), earned: true, fill: .white)
                } else {
                    gradient(badge, [glow, series], radius: glyph / 2)
                    drawArrowGlyph(badge.insetBy(dx: 9, dy: 8))
                }
                label(language.text(copies[index].title), badge.maxX + 11, (lone ? card.minY + pad - 1 : badge.midY - 9) + (12.5 - titleSize) / 2, titleWidth,
                      size: titleSize, weight: .bold, color: reward ? amberInk : ink)
                var cursor = lone ? card.minY + pad + 21 : badge.maxY + 8
                for line in bodies[index] {
                    label(line, card.minX + pad + indent, cursor, card.width - pad * 2 - indent, size: 10, color: soft)
                    cursor += 14
                }
            }
            y += height
        }

        /// Creatine and water side by side at one height; either takes the full width alone. Each card measures, then draws.
        private func drawSupplementRow(_ nutrition: NutritionReport) {
            var cards: [(CGRect, Bool) -> CGFloat] = []
            if let creatine = nutrition.creatine { cards.append { self.creatineCard(creatine, in: $0, draw: $1) } }
            if nutrition.waterLitres > 0, let comparison = WaterVolumeComparison.caption(litres: nutrition.waterLitres) {
                cards.append { self.waterCard(nutrition, comparison: comparison, in: $0, draw: $1) }
            }
            guard !cards.isEmpty else { return }
            let gap: CGFloat = 12
            let cardWidth = (width - gap * CGFloat(cards.count - 1)) / CGFloat(cards.count)
            let slots = cards.indices.map { CGRect(x: left + CGFloat($0) * (cardWidth + gap), y: y, width: cardWidth, height: bottom - y) }
            let height = min(bottom - y, max(132, zip(cards, slots).map { $0.0($0.1, false) }.max() ?? 0))
            for (card, slot) in zip(cards, slots) {
                _ = card(CGRect(x: slot.minX, y: y, width: slot.width, height: height), true)
            }
            y += height
        }

        private func badgeCopy(_ badge: NutritionReport.Creatine.Badge) -> Copy {
            switch badge {
            case .freshStart: return ("Fresh start", "Creatine works by keeping your muscle stores topped up, so every daily dose from here counts.")
            case .champ: return ("Creatine champ", "Your muscle stores stay topped up, exactly how creatine pays off.")
            case .lockedIn: return ("Locked in", "Taken almost every day, so your muscle stores stay topped up.")
            case .onARoll: return ("On a roll", "Your current streak keeps your muscle stores topped up. Keep it going.")
            case .comeback: return ("Comeback", "Your last two weeks are back on track. Creatine pays off when taken every day, so this streak is what counts.")
            case .lapsed: return ("Ready to restart", "Creatine works by keeping your muscle stores topped up, so a daily dose from today brings it back.")
            case .weekendGaps: return ("Weekend gaps", "Your weekdays are steady. Taking it at weekends too keeps your muscle stores topped up.")
            case .almostDaily: return ("Almost daily", "A few more daily doses keep your muscle stores fully topped up.")
            case .stopStart: return ("Stop and start", "Creatine pays off as a daily habit. Linking a few days in a row keeps your stores topped up.")
            case .buildTheStreak: return ("Build the streak", "Creatine pays off when taken every day. Pair it with something you already do daily.")
            }
        }

        private func creatineCard(_ creatine: NutritionReport.Creatine, in card: CGRect, draw: Bool) -> CGFloat {
            let reward: Set<NutritionReport.Creatine.Badge> = [.champ, .lockedIn, .onARoll, .comeback]
            let isReward = reward.contains(creatine.badge)
            let pad: CGFloat = 16, diameter: CGFloat = 50
            let copy = badgeCopy(creatine.badge)
            let inner = card.width - pad * 2
            let stats = wrapped(language.format("Taken on %d of %d days · longest streak %d days", creatine.takenDays, creatine.trackedDays,
                                                creatine.longestStreak), width: inner, size: 9.5, weight: .medium)
            let fixed = pad + diameter + 8 + CGFloat(stats.count) * 13 + 6 + pad - 4
            let sentence = wrapped(language.text(copy.line), width: inner, size: 10)
            // A sentence is shown whole or not at all; the page edge never cuts one off.
            let body = fixed + CGFloat(sentence.count) * 14 <= card.height ? sentence : []
            guard draw else { return fixed + CGFloat(body.count) * 14 }
            glass(card, radius: 20, tint: isReward ? amberWash : .white, opacity: isReward ? 0.82 : 0.6)
            let ring = CGRect(x: card.maxX - pad - diameter, y: card.minY + pad - 2, width: diameter, height: diameter)
            drawRing(in: ring, ratio: Double(creatine.score) / 100, line: 7,
                     colors: isReward ? macroColors(.fat) : macroColors(.protein))
            centered(String(creatine.score), in: ring, size: 15, weight: .bold, color: ink, rounded: true)
            let textWidth = ring.minX - card.minX - pad - 8
            label(language.text("Creatine").uppercased(with: locale), card.minX + pad, card.minY + pad, textWidth, size: 9.5, weight: .bold,
                  color: isReward ? amberInk : green, kern: 0.6)
            var titleX = card.minX + pad
            if isReward {
                drawStar(CGRect(x: titleX, y: card.minY + pad + 18, width: 15, height: 15), earned: true)
                titleX += 20
            }
            let badgeTitle = language.text(copy.title)
            let badgeSize = fittingSize(badgeTitle, width: ring.minX - titleX - 8, sizes: [15, 13.5, 12], weight: .bold)
            label(badgeTitle, titleX, card.minY + pad + 15 + (15 - badgeSize) / 2, ring.minX - titleX - 8, size: badgeSize, weight: .bold,
                  color: isReward ? amberInk : ink)
            var cursor = card.minY + pad + diameter + 8
            for line in stats {
                label(line, card.minX + pad, cursor, inner, size: 9.5, weight: .medium, color: muted)
                cursor += 13
            }
            cursor += 6
            for line in body {
                label(line, card.minX + pad, cursor, inner, size: 10, color: soft)
                cursor += 14
            }
            return card.height
        }

        private func litres(_ value: Double) -> String {
            value.formatted(.number.locale(locale).precision(.fractionLength(value < 100 ? 1 : 0))) + " L"
        }

        private func waterCard(_ nutrition: NutritionReport, comparison: WaterVolumeComparison.Comparison, in card: CGRect, draw: Bool) -> CGFloat {
            let pad: CGFloat = 16, tank = CGSize(width: 50, height: 78)
            let blue = Pages.rgb(0x1F6FD6)
            let next = WaterVolumeComparison.next(after: nutrition.waterLitres)
            let tankFrame = CGRect(x: card.maxX - pad - tank.width, y: card.minY + pad, width: tank.width, height: tank.height)
            let textWidth = tankFrame.minX - card.minX - pad - 12
            let caption = wrapped(comparison.caption, width: textWidth, size: 10.5, weight: .semibold)
            let notes = (next.map { [language.format("Next: %@", $0.name.contains(where: \.isNumber) ? $0.name : $0.name + " · " + litres($0.litres))] } ?? [])
                + [language.format("Logged on %d days", nutrition.waterDays)]
            let noteLines = notes.flatMap { wrapped($0, width: card.width - pad * 2, size: 9.5, weight: .medium) }
            let fixed = pad + max(tank.height + 8, 50) + 6 + CGFloat(noteLines.count) * 13 + pad - 4
            let textBlock = max(tank.height + 8, 50 + CGFloat(caption.count) * 14.5)
            let needed = pad + textBlock + 6 + CGFloat(noteLines.count) * 13 + pad - 4
            let shown = needed <= card.height ? caption : []
            guard draw else { return shown.isEmpty ? fixed : needed }
            glass(card, radius: 20, opacity: 0.6)
            // The figure is the period's drinks; water in food is counted on the daily gauge, not here.
            label(language.text("Drinks").uppercased(with: locale), card.minX + pad, card.minY + pad, textWidth, size: 9.5, weight: .bold,
                  color: blue, kern: 0.6)
            let figure = litres(nutrition.waterLitres)
            let figureSize = fittingSize(figure, width: textWidth, sizes: [26, 22, 18], weight: .bold)
            label(figure, card.minX + pad, card.minY + pad + 15 + (26 - figureSize) / 2, textWidth, size: figureSize, weight: .bold,
                  color: ink, rounded: true)
            var cursor = card.minY + pad + 50
            for line in shown {
                label(line, card.minX + pad, cursor, textWidth, size: 10.5, weight: .semibold, color: ink)
                cursor += 14.5
            }
            let progress = next.map { min(1, max(0, nutrition.waterLitres / $0.litres)) } ?? 1
            drawTank(in: tankFrame, level: progress)
            cursor = max(cursor, tankFrame.maxY + 8) + 6
            for line in noteLines {
                label(line, card.minX + pad, cursor, card.width - pad * 2, size: 9.5, weight: .medium, color: muted)
                cursor += 13
            }
            return card.height
        }

        /// A glass tank filled to `level` (0...1) with a wave-topped blue gradient.
        private func drawTank(in frame: CGRect, level: Double) {
            let pad: CGFloat = 8
            let canvas = frame.insetBy(dx: -pad, dy: -pad)
            let image = raster(canvas.size) { cg in
                guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
                let body = CGRect(x: pad, y: pad, width: frame.width, height: frame.height)
                let vessel = UIBezierPath(roundedRect: body, cornerRadius: 12)
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: Pages.rgb(0x1F6FD6).withAlphaComponent(0.25).cgColor)
                cg.setFillColor(UIColor.white.withAlphaComponent(0.75).cgColor)
                cg.addPath(vessel.cgPath)
                cg.fillPath()
                cg.restoreGState()
                cg.saveGState()
                cg.addPath(vessel.cgPath)
                cg.clip()
                // Headroom at both ends keeps the wave visible for an almost empty or almost full tank.
                let surface = body.maxY - body.height * (0.08 + 0.8 * CGFloat(min(1, max(0, level))))
                func wave(phase: CGFloat, amplitude: CGFloat) -> CGPath {
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: body.minX, y: body.maxY))
                    for step in 0...24 {
                        let x = body.minX + body.width * CGFloat(step) / 24
                        path.addLine(to: CGPoint(x: x, y: surface + amplitude * sin(CGFloat(step) / 24 * 2 * .pi + phase)))
                    }
                    path.addLine(to: CGPoint(x: body.maxX, y: body.maxY))
                    path.close()
                    return path.cgPath
                }
                cg.setFillColor(Pages.rgb(0x7CC8F8).withAlphaComponent(0.55).cgColor)
                cg.addPath(wave(phase: .pi, amplitude: 2.6))
                cg.fillPath()
                cg.addPath(wave(phase: 0, amplitude: 2.2))
                cg.clip()
                if let shading = CGGradient(colorsSpace: space, colors: [Pages.rgb(0x6CC4F7).cgColor, Pages.rgb(0x1F6FD6).cgColor] as CFArray,
                                            locations: [0, 1]) {
                    cg.drawLinearGradient(shading, start: CGPoint(x: 0, y: surface - 3), end: CGPoint(x: 0, y: body.maxY), options: [])
                }
                cg.restoreGState()
                cg.setFillColor(UIColor.white.withAlphaComponent(0.55).cgColor)
                cg.fill(CGRect(x: body.minX + 7, y: body.minY + 10, width: 3, height: body.height - 26))
                cg.addPath(UIBezierPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 11.5).cgPath)
                cg.setLineWidth(1)
                cg.setStrokeColor(Pages.rgb(0x1F6FD6).withAlphaComponent(0.28).cgColor)
                cg.strokePath()
            }
            image.draw(in: canvas)
        }

        /// A five-point star as a vector path; earned stars carry the amber gradient, unearned ones a faint ink.
        private func drawStar(_ frame: CGRect, earned: Bool, fill color: UIColor? = nil) {
            let path = starPath(center: CGPoint(x: frame.midX, y: frame.midY + frame.height * 0.04), radius: frame.width / 2)
            if let color {
                color.setFill()
                path.fill()
                return
            }
            guard earned else {
                ink.withAlphaComponent(0.08).setFill()
                path.fill()
                return
            }
            let cg = context.cgContext
            cg.saveGState()
            path.addClip()
            gradient(frame, [Pages.rgb(0xFFD66B), amber])
            cg.restoreGState()
        }

        private func starPath(center: CGPoint, radius outer: CGFloat) -> UIBezierPath {
            let path = UIBezierPath()
            for point in 0..<10 {
                let radius = point.isMultiple(of: 2) ? outer : outer * 0.45
                let angle = -CGFloat.pi / 2 + CGFloat(point) * .pi / 5
                let vertex = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                point == 0 ? path.move(to: vertex) : path.addLine(to: vertex)
            }
            path.close()
            return path
        }

        private func drawArrowGlyph(_ frame: CGRect) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: frame.midX, y: frame.minY))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + frame.height * 0.48))
            path.addLine(to: CGPoint(x: frame.midX + frame.width * 0.17, y: frame.minY + frame.height * 0.48))
            path.addLine(to: CGPoint(x: frame.midX + frame.width * 0.17, y: frame.maxY))
            path.addLine(to: CGPoint(x: frame.midX - frame.width * 0.17, y: frame.maxY))
            path.addLine(to: CGPoint(x: frame.midX - frame.width * 0.17, y: frame.minY + frame.height * 0.48))
            path.addLine(to: CGPoint(x: frame.minX, y: frame.minY + frame.height * 0.48))
            path.close()
            UIColor.white.setFill()
            path.fill()
        }

        /// A reward rosette: a scalloped amber medal with a star, hung from two ribbon tails.
        private func drawRosette(_ frame: CGRect) {
            let image = raster(frame.size) { cg in
                guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
                let size = frame.size
                let center = CGPoint(x: size.width / 2, y: size.width / 2 + 2)
                let outer = size.width / 2 - 4
                for (dx, tint) in [(-1.0, Pages.rgb(0xD9822B)), (1.0, Pages.rgb(0xC46F1E))] {
                    let tail = UIBezierPath()
                    let x = center.x + CGFloat(dx) * outer * 0.38
                    tail.move(to: CGPoint(x: x - 8, y: center.y + outer * 0.5))
                    tail.addLine(to: CGPoint(x: x + 8, y: center.y + outer * 0.5))
                    tail.addLine(to: CGPoint(x: x + 8 + CGFloat(dx) * 4, y: size.height - 2))
                    tail.addLine(to: CGPoint(x: x + CGFloat(dx) * 4, y: size.height - 8))
                    tail.addLine(to: CGPoint(x: x - 8 + CGFloat(dx) * 4, y: size.height - 2))
                    tail.close()
                    cg.setFillColor(tint.cgColor)
                    cg.addPath(tail.cgPath)
                    cg.fillPath()
                }
                let scallops = 16
                let medal = UIBezierPath()
                for step in 0...(scallops * 2) {
                    let angle = -CGFloat.pi / 2 + CGFloat(step) * .pi / CGFloat(scallops)
                    let radius = step.isMultiple(of: 2) ? outer : outer * 0.88
                    let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                    step == 0 ? medal.move(to: point) : medal.addLine(to: point)
                }
                medal.close()
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: amber.withAlphaComponent(0.55).cgColor)
                cg.setFillColor(amber.cgColor)
                cg.addPath(medal.cgPath)
                cg.fillPath()
                cg.restoreGState()
                cg.saveGState()
                cg.addPath(medal.cgPath)
                cg.clip()
                if let shading = CGGradient(colorsSpace: space, colors: [Pages.rgb(0xFFE08A).cgColor, amber.cgColor, Pages.rgb(0xC77A00).cgColor] as CFArray,
                                            locations: [0, 0.55, 1]) {
                    cg.drawLinearGradient(shading, start: CGPoint(x: center.x - outer, y: center.y - outer),
                                          end: CGPoint(x: center.x + outer, y: center.y + outer), options: [])
                }
                cg.restoreGState()
                let face = UIBezierPath(arcCenter: center, radius: outer * 0.66, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
                cg.saveGState()
                cg.addPath(face.cgPath)
                cg.clip()
                if let shading = CGGradient(colorsSpace: space, colors: [Pages.rgb(0xFFF1C4).cgColor, Pages.rgb(0xFFC94D).cgColor] as CFArray, locations: [0, 1]) {
                    cg.drawLinearGradient(shading, start: CGPoint(x: center.x, y: center.y - outer), end: CGPoint(x: center.x, y: center.y + outer), options: [])
                }
                cg.restoreGState()
                let star = starPath(center: CGPoint(x: center.x, y: center.y + 1), radius: outer * 0.42)
                cg.setFillColor(Pages.rgb(0xB86E00).cgColor)
                cg.addPath(star.cgPath)
                cg.fillPath()
            }
            image.draw(in: frame)
        }

        // MARK: Avatar scores

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
            let dates = [datedRows.first?.row.date, datedRows.last?.row.date].compactMap { $0 }.map(language.dateKey)
            let subtitle = dates.first == dates.last ? (dates.first ?? "") : dates.joined(separator: " – ")
            begin("Avatar scores", subtitle: subtitle)
            let gap: CGFloat = 12
            let cardWidth = (width - gap) / 2
            let rowsNeeded = CGFloat((recorded.count + 1) / 2)
            let cardHeight = min(150, (bottom - y - gap * (rowsNeeded - 1)) / rowsNeeded)
            for (index, metric) in recorded.enumerated() {
                let (title, path, value) = metric
                let x = left + CGFloat(index % 2) * (cardWidth + gap)
                let cardTop = y + CGFloat(index / 2) * (cardHeight + gap)
                glass(CGRect(x: x, y: cardTop, width: cardWidth, height: cardHeight), radius: 22, opacity: 0.55)
                label(language.text(title), x + 16, cardTop + 14, cardWidth - 100, size: 11, weight: .semibold, color: soft)
                label(number(Double(AvatarIndex.shown(value))) + " / 100", x + 16, cardTop + 31, cardWidth - 32, size: 22, weight: .bold, rounded: true)
                let track = CGRect(x: x + 16, y: cardTop + 64, width: cardWidth - 32, height: 5)
                fill(track, ink.withAlphaComponent(0.07), radius: 2.5)
                gradient(CGRect(x: track.minX, y: track.minY, width: max(5, track.width * CGFloat(min(100, max(0, value)) / 100)), height: 5),
                         [glow, series, violet], vertical: false, radius: 2.5)
                let series = datedRows.compactMap { row, time -> (Double, Double)? in
                    let score = row[keyPath: path]
                    return score.isFinite ? (span > 0 ? (time - start) / span : 0.5, score) : nil
                }
                if let first = series.first?.1, let last = series.last?.1, series.count >= 2 {
                    let change = last - first
                    let text = (change > 0 ? "+" : "") + number(change)
                    let chip = measure(text, size: 9.5, weight: .bold, rounded: true) + 14
                    let frame = CGRect(x: x + cardWidth - 16 - chip, y: cardTop + 13, width: chip, height: 18)
                    glass(frame, radius: 9, tint: change > 0 ? mint : .white, opacity: 0.7)
                    centered(text, in: frame, size: 9.5, weight: .bold, color: change > 0 ? green : soft, rounded: true)
                    let bounds = CGRect(x: x + 16, y: cardTop + 80, width: cardWidth - 32, height: max(16, cardHeight - 96))
                    let low = series.map(\.1).min() ?? 0, high = series.map(\.1).max() ?? 100
                    let padding = max(2, (high - low) * 0.15)
                    let floor = max(0, low - padding), ceiling = min(100, high + padding)
                    let points = series.map { fraction, score in
                        CGPoint(x: bounds.minX + fraction * bounds.width,
                                y: bounds.maxY - (ceiling > floor ? (score - floor) / (ceiling - floor) : 0.5) * bounds.height)
                    }
                    sparkline(points, baseline: bounds.maxY)
                }
            }
            y += rowsNeeded * (cardHeight + gap)
        }

        private func sparkline(_ points: [CGPoint], baseline: CGFloat) {
            guard let last = points.last, let minX = points.first?.x else { return }
            let top = points.map(\.y).min() ?? baseline
            drawCurve(points, baseline: baseline, in: CGRect(x: minX, y: top, width: max(1, last.x - minX), height: max(1, baseline - top)), lineWidth: 2.2)
            dot(last, radius: 9, fill: series.withAlphaComponent(0.16), ring: 0)
            dot(last, radius: 3.6, fill: series, ring: 1.8)
        }

        // MARK: Primitives

        /// Archivo Expanded ExtraBold (SIL OFL, bundled in ReportFonts) sets the cover name; everything else uses the system face.
        private static let displayFonts: Void = {
            for name in ["Archivo_Expanded-ExtraBold"] {
                guard let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "ReportFonts") else { continue }
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }()

        func font(_ size: CGFloat, _ weight: UIFont.Weight, rounded: Bool = false, display: Bool = false) -> UIFont {
            if display {
                _ = Self.displayFonts
                if let face = UIFont(name: "ArchivoExpanded-ExtraBold", size: size) { return face }
            }
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard rounded, let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }

        func wrapped(_ string: String, width: Double, size: CGFloat, weight: UIFont.Weight = .regular, rounded: Bool = false,
                     display: Bool = false) -> [String] {
            let text = NSAttributedString(string: string, attributes: [.font: font(size, weight, rounded: rounded, display: display)])
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

        func measure(_ string: String, size: CGFloat, weight: UIFont.Weight, rounded: Bool = false, kern: CGFloat = 0,
                     display: Bool = false) -> CGFloat {
            var attributes: [NSAttributedString.Key: Any] = [.font: font(size, weight, rounded: rounded, display: display)]
            if kern != 0 { attributes[.kern] = kern }
            return ceil((string as NSString).size(withAttributes: attributes).width)
        }

        func weight(_ kilograms: Double) -> String {
            number(report.unit.value(fromKilograms: kilograms)) + " " + report.unit.suffix
        }

        func number(_ value: Double) -> String {
            value.formatted(.number.locale(locale).precision(.fractionLength(0...1)))
        }

        func fill(_ rect: CGRect, _ color: UIColor, radius: CGFloat = 0) {
            color.setFill()
            (radius > 0 ? UIBezierPath(roundedRect: rect, cornerRadius: radius) : UIBezierPath(rect: rect)).fill()
        }

        func gradient(_ rect: CGRect, _ colors: [UIColor], vertical: Bool = true, radius: CGFloat = 0) {
            let cg = context.cgContext
            cg.saveGState()
            if radius > 0 { UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip() } else { cg.clip(to: rect) }
            if let shading = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil) {
                cg.drawLinearGradient(shading, start: CGPoint(x: rect.minX, y: rect.minY),
                                      end: vertical ? CGPoint(x: rect.minX, y: rect.maxY) : CGPoint(x: rect.maxX, y: rect.minY), options: [])
            }
            cg.restoreGState()
        }

        /// PDF shadings ignore alpha, so washes are mixed into the surface they sit on.
        private func blend(_ color: UIColor, over base: UIColor, _ amount: CGFloat) -> UIColor {
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            base.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return UIColor(red: r2 + (r1 - r2) * amount, green: g2 + (g1 - g2) * amount, blue: b2 + (b1 - b2) * amount, alpha: 1)
        }

        private func stroke(_ rect: CGRect, _ color: UIColor, radius: CGFloat, lineWidth: CGFloat = 0.8) {
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), cornerRadius: radius)
            path.lineWidth = lineWidth
            color.setStroke()
            path.stroke()
        }

        // MARK: Materials

        /// Renders effects PDF vector shading cannot carry (alpha gradients, glows) into an embedded bitmap.
        private func raster(_ size: CGSize, scale: CGFloat = 3, jpeg: Bool = false, _ draw: (CGContext) -> Void) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = jpeg
            let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
            guard jpeg, let data = image.jpegData(compressionQuality: 0.86), let compact = UIImage(data: data) else { return image }
            return compact
        }

        private func radial(_ cg: CGContext, at center: CGPoint, radius: CGFloat, color: UIColor, alpha: CGFloat) {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let shading = CGGradient(colorsSpace: space, colors: [color.withAlphaComponent(alpha).cgColor,
                                                                        color.withAlphaComponent(alpha * 0.45).cgColor,
                                                                        color.withAlphaComponent(0).cgColor] as CFArray,
                                           locations: [0, 0.45, 1]) else { return }
            cg.drawRadialGradient(shading, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }

        /// A soft aurora behind every page; the arrangement turns with the page so no two spreads repeat.
        private func drawAurora() {
            let size = AvatarReport.pageSize
            let lavender = Pages.rgb(0xC6B6FF), peach = Pages.rgb(0xFFD3A1), aqua = Pages.rgb(0x8EE6D0), sky = Pages.rgb(0xA9D8FF)
            let layouts: [[(CGFloat, CGFloat, CGFloat, UIColor, CGFloat)]] = [
                [(0.98, 0.04, 340, aqua, 0.7), (0.02, 0.36, 290, lavender, 0.55), (0.92, 0.72, 310, peach, 0.46), (0.15, 0.98, 320, sky, 0.5)],
                [(0.05, 0.06, 330, lavender, 0.55), (0.95, 0.32, 300, aqua, 0.66), (0.1, 0.74, 310, sky, 0.46), (0.9, 1.0, 300, peach, 0.46)],
                [(0.9, 0.1, 320, peach, 0.46), (0.06, 0.45, 310, aqua, 0.62), (0.96, 0.66, 290, lavender, 0.52), (0.32, 1.02, 320, sky, 0.44)],
            ]
            let blobs = layouts[(page - 1) % layouts.count]
            let image = raster(size, scale: 1, jpeg: true) { cg in
                paper.setFill()
                cg.fill(CGRect(origin: .zero, size: size))
                for (x, y, radius, color, alpha) in blobs {
                    radial(cg, at: CGPoint(x: size.width * x, y: size.height * y), radius: radius, color: color, alpha: alpha)
                }
            }
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        /// Frosted glass: a translucent pane with a bright rim, a top sheen and a faint lift off the page.
        private func glass(_ rect: CGRect, radius: CGFloat = 20, tint: UIColor = .white, opacity: CGFloat = 0.58, dark: Bool = false) {
            for step in 1...3 {
                let spread = CGFloat(step) * 1.6
                fill(rect.insetBy(dx: -spread, dy: -spread).offsetBy(dx: 0, dy: spread * 0.9),
                     ink.withAlphaComponent(dark ? 0.06 : 0.022), radius: radius + spread)
            }
            fill(rect, tint.withAlphaComponent(opacity), radius: radius)
            stroke(rect, UIColor.white.withAlphaComponent(dark ? 0.22 : 0.92), radius: radius, lineWidth: 1)
            fill(CGRect(x: rect.minX + radius, y: rect.minY + 1.2, width: max(0, rect.width - radius * 2), height: 0.9),
                 UIColor.white.withAlphaComponent(dark ? 0.32 : 1))
        }

        /// Monotone cubic interpolation: smooth, and never overshoots a recorded value.
        private func smoothPath(_ points: [CGPoint]) -> UIBezierPath {
            let path = UIBezierPath()
            guard let first = points.first else { return path }
            path.move(to: first)
            let n = points.count
            guard n > 2 else {
                points.dropFirst().forEach { path.addLine(to: $0) }
                return path
            }
            var slope = [CGFloat](repeating: 0, count: n - 1), tangent = [CGFloat](repeating: 0, count: n)
            for i in 0..<(n - 1) {
                let dx = points[i + 1].x - points[i].x
                slope[i] = dx > 0 ? (points[i + 1].y - points[i].y) / dx : 0
            }
            tangent[0] = slope[0]
            tangent[n - 1] = slope[n - 2]
            for i in 1..<(n - 1) { tangent[i] = slope[i - 1] * slope[i] <= 0 ? 0 : (slope[i - 1] + slope[i]) / 2 }
            for i in 0..<(n - 1) {
                guard slope[i] != 0 else { tangent[i] = 0; tangent[i + 1] = 0; continue }
                let a = tangent[i] / slope[i], b = tangent[i + 1] / slope[i], h = a * a + b * b
                if h > 9 {
                    let t = 3 / sqrt(h)
                    tangent[i] = t * a * slope[i]
                    tangent[i + 1] = t * b * slope[i]
                }
            }
            for i in 0..<(n - 1) {
                let dx = (points[i + 1].x - points[i].x) / 3
                path.addCurve(to: points[i + 1],
                              controlPoint1: CGPoint(x: points[i].x + dx, y: points[i].y + tangent[i] * dx),
                              controlPoint2: CGPoint(x: points[i + 1].x - dx, y: points[i + 1].y - tangent[i + 1] * dx))
            }
            return path
        }

        /// A glowing gradient curve over a translucent fill, rendered once and placed as artwork.
        private func drawCurve(_ points: [CGPoint], baseline: CGFloat, in frame: CGRect, lineWidth: CGFloat = 3) {
            guard points.count >= 2, let first = points.first, let last = points.last else { return }
            let pad: CGFloat = 16
            let canvasRect = frame.insetBy(dx: -pad, dy: -pad)
            let local = points.map { CGPoint(x: $0.x - canvasRect.minX, y: $0.y - canvasRect.minY) }
            let floor = baseline - canvasRect.minY
            let image = raster(canvasRect.size) { cg in
                let curve = smoothPath(local)
                guard let area = curve.copy() as? UIBezierPath, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
                area.addLine(to: CGPoint(x: local[local.count - 1].x, y: floor))
                area.addLine(to: CGPoint(x: local[0].x, y: floor))
                area.close()
                let topY = local.map(\.y).min() ?? 0
                cg.saveGState()
                cg.addPath(area.cgPath)
                cg.clip()
                if let wash = CGGradient(colorsSpace: space, colors: [series.withAlphaComponent(0.34).cgColor, glow.withAlphaComponent(0.14).cgColor,
                                                                      glow.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.55, 1]) {
                    cg.drawLinearGradient(wash, start: CGPoint(x: 0, y: topY), end: CGPoint(x: 0, y: floor), options: [])
                }
                cg.restoreGState()
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: 4), blur: 10, color: series.withAlphaComponent(0.42).cgColor)
                cg.addPath(curve.cgPath)
                cg.setLineWidth(lineWidth)
                cg.setStrokeColor(series.cgColor)
                cg.strokePath()
                cg.restoreGState()
                cg.saveGState()
                cg.addPath(curve.cgPath)
                cg.setLineWidth(lineWidth + 0.4)
                cg.replacePathWithStrokedPath()
                cg.clip()
                if let ink = CGGradient(colorsSpace: space, colors: [glow.cgColor, series.cgColor, violet.cgColor] as CFArray, locations: [0, 0.55, 1]) {
                    cg.drawLinearGradient(ink, start: CGPoint(x: local[0].x, y: 0), end: CGPoint(x: local[local.count - 1].x, y: 0), options: [])
                }
                cg.restoreGState()
            }
            image.draw(in: canvasRect)
            _ = (first, last)
        }

        /// Centers a single line optically: the cap height, not the line box, sits on the frame's middle.
        private func centered(_ text: String, in rect: CGRect, size: CGFloat, weight: UIFont.Weight, color: UIColor, rounded: Bool = false) {
            let face = font(size, weight, rounded: rounded)
            label(text, rect.minX, rect.midY + face.capHeight / 2 - face.ascender, rect.width, size: size, weight: weight, color: color,
                  alignment: .center, rounded: rounded)
        }

        /// The largest of the given sizes that keeps a title on one line, or the smallest when none does.
        private func fittingSize(_ text: String, width: CGFloat, sizes: [CGFloat], weight: UIFont.Weight, display: Bool = false) -> CGFloat {
            sizes.first { measure(text, size: $0, weight: weight, display: display) <= width } ?? sizes.last ?? 20
        }

        private func link(_ url: URL, _ rect: CGRect) {
            context.setURL(url, for: context.cgContext.convertToDeviceSpace(rect))
        }

        func label(_ string: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat,
                   size: CGFloat = 13, weight: UIFont.Weight = .regular, color: UIColor? = nil,
                   alignment: NSTextAlignment = .left, rounded: Bool = false, kern: CGFloat = 0, display: Bool = false) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byTruncatingTail
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font(size, weight, rounded: rounded, display: display), .foregroundColor: color ?? ink, .paragraphStyle: paragraph,
            ]
            if kern != 0 { attributes[.kern] = kern }
            (string as NSString).draw(in: CGRect(x: x, y: y, width: width, height: size * 1.65), withAttributes: attributes)
        }
    }
}

private extension UIColor {
    var darker: UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return UIColor(hue: hue, saturation: saturation, brightness: brightness * 0.86, alpha: alpha)
    }
}
