import CoreTransferable
import CoreText
import UIKit
import UniformTypeIdentifiers

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
            pages.drawScores(scores)
            pages.drawRankings(families)
            pages.drawCharts(families)
            if let trainingProfile { pages.drawTrainingProfile(trainingProfile) }
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

        func begin(_ section: String, subtitle: String) {
            context.beginPage()
            page += 1
            label(AppBrand.name, 38, 32, 200, size: 13, weight: .heavy, color: green)
            label(report.displayName, 260, 32, 314, size: 12, alignment: .right)
            line(38, 61, 574, 61, color: ink)
            label(language.text(section), 38, 85, 536, size: 30, weight: .bold)
            label(subtitle, 38, 128, 536, size: 12, color: muted)
            line(38, 748, 574, 748, color: rule)
            label(language.text("Avatar report"), 38, 758, 440, size: 10, color: muted)
            label(String(page), 508, 758, 66, size: 10, alignment: .right)
            y = 170
        }

        func drawScores(_ rows: [RPGSnapshot]) {
            let datedRows = rows.compactMap { row in
                APEXDateMath.date(from: row.date).map { (row: row, time: $0.timeIntervalSinceReferenceDate) }
            }
            let start = datedRows.first?.time ?? 0
            let span = (datedRows.last?.time ?? start) - start
            var subtitle = language.text("Building your baseline")
            if let first = rows.first?.date, let last = rows.last?.date {
                subtitle = first == last ? first : first + "  →  " + last
            }
            begin("Avatar scores", subtitle: subtitle)
            let metrics: [(String, String, KeyPath<RPGSnapshot, Double>)] = [
                ("overall", "Overall Fitness Level", \.overall), ("health", "Health", \.health),
                ("joint", "Joint Health Balance", \.joint), ("flexibility", "Body Flexibility", \.flexibility),
                ("endurance", "Endurance & VO₂ max", \.endurance), ("strength", "Strength", \.strength),
                ("upper", "Upper Body Strength", \.strengthUpper), ("lower", "Lower Body Strength", \.strengthLower),
            ]
            for (index, metric) in metrics.enumerated() {
                let (key, title, path) = metric
                let x: CGFloat = index.isMultiple(of: 2) ? 38 : 315
                let top = y + CGFloat(index / 2) * 139
                let card = CGRect(x: x, y: top, width: 259, height: 121)
                UIColor(white: 0.965, alpha: 1).setFill()
                UIBezierPath(roundedRect: card, cornerRadius: 10).fill()
                label(language.text(title), x + 13, top + 12, 233, size: 13, weight: .semibold)
                let current = rows.last?[keyPath: path] ?? report.partialScores[key]
                let value = current.flatMap { $0.isFinite ? number($0) + " / 100" : nil }
                label(value ?? "—", x + 13, top + 32, 233, size: 22, weight: .bold)
                let bounds = CGRect(x: x + 14, y: top + 68, width: 231, height: 36)
                line(bounds.minX, bounds.maxY, bounds.maxX, bounds.maxY, color: rule)
                let points = datedRows.compactMap { row, time -> CGPoint? in
                    guard row[keyPath: path].isFinite else { return nil }
                    let fraction = span > 0 ? (time - start) / span : 0.5
                    return CGPoint(x: bounds.minX + fraction * bounds.width,
                                   y: bounds.maxY - min(100, max(0, row[keyPath: path])) / 100 * bounds.height)
                }
                trace(points)
            }
        }

        func drawTrainingProfile(_ profile: TrainingProfile90) {
            begin("90-day training profile", subtitle: language.dateKey(profile.from) + " – " + language.dateKey(profile.to))
            label(language.text(profile.category), 38, y, 536, size: 23, weight: .bold, color: green)
            y += 48
            func metric(_ key: String, _ value: String) {
                for part in wrapped(language.text(key), width: 375, size: 14) {
                    label(part, 38, y, 375, size: 14)
                    y += 19
                }
                label(value, 425, y - 19, 149, size: 14, weight: .bold, alignment: .right)
                y += 12
            }
            for row in profile.metrics(language: language) { metric(row.key, row.value) }
            if let note = profile.note {
                for part in wrapped(language.text(note), width: 536, size: 12) {
                    label(part, 38, y, 536, size: 12, color: muted)
                    y += 17
                }
            }
            if let match = profile.matchedLoad {
                y += 25
                label(language.text("Matched working load"), 38, y, 536, size: 18, weight: .bold)
                y += 31
                let title = language.text(match.exercise) + " · " + language.format("%d reps", match.reps)
                for part in wrapped(title, width: 536, size: 14) {
                    if y > 687 { begin("Matched working load", subtitle: language.text(profile.category)) }
                    label(part, 38, y, 536, size: 14)
                    y += 19
                }
                if y > 597 { begin("Matched working load", subtitle: language.text(profile.category)) }
                y += 8
                metric("Previous 45 days", weight(match.earlierKG))
                metric("Last 45 days", weight(match.recentKG))
                for part in wrapped(language.text("Median session-best load at the same rep count."), width: 536, size: 12) {
                    label(part, 38, y, 536, size: 12, color: muted)
                    y += 17
                }
            }
        }

        func volume(_ kg: Double) -> String {
            LiftedMassComparison.formattedMass(kg, locale: language.language.locale)
        }

        func drawLifetimeTotals(_ rows: [StrengthProgress.RankedFamily]) {
            let totals = rows.reduce(into: StrengthProgress.LifetimeTotals()) { $0.add($1.totals) }
            label(language.text("All-time training totals"), 38, y, 536, size: 19, weight: .bold)
            y += 26
            let dates = rows.flatMap { $0.sessions.map(\.date) }
            if let first = dates.min(), let last = dates.max() {
                let range = first == last ? language.dateKey(first) : language.dateKey(first) + " – " + language.dateKey(last)
                label(range, 38, y, 536, size: 11, color: muted)
                y += 20
            }
            let metrics = [
                ("Performed sets", String(totals.sets)),
                ("Recorded reps", totals.recordedReps.map { number(Double($0)) + (totals.missingReps ? "*" : "") } ?? "—"),
                ("Lifted volume", totals.liftedVolumeKG.map { volume($0) + (totals.missingVolume ? "*" : "") } ?? "—")
            ]
            for (index, metric) in metrics.enumerated() {
                let x = 38 + CGFloat(index) * 182
                label(language.text(metric.0), x, y, 175, size: 11, color: muted)
                label(metric.1, x, y + 16, 175, size: 18, weight: .bold)
            }
            y += 46
            if let kg = totals.liftedVolumeKG {
                drawComparisons(object: LiftedMassComparison.caption(kilograms: kg),
                                hero: LiftedMassComparison.heroCaption(kilograms: kg))
            }
            let note = language.text("Known external load × recorded reps. Body mass, assistance and timed work are excluded from volume. Skipped sets are excluded from all totals.")
            for part in wrapped(note, width: 536, size: 10) {
                label(part, 38, y, 536, size: 10, color: muted)
                y += 14
            }
            y += 12
            line(38, y, 574, y, color: rule)
            y += 13
        }

        private func drawComparisons(object: LiftedMassComparison.Comparison?, hero: LiftedMassComparison.Comparison?) {
            guard object != nil || hero != nil else { return }
            let image = object?.artworkURL.flatMap { UIImage(contentsOfFile: $0.path) }
            let textX: CGFloat = image == nil ? 38 : 174
            let width = 574 - textX
            let start = y
            func linked(_ text: String, to source: URL, size: CGFloat, weight: UIFont.Weight, color: UIColor) {
                let top = y
                for part in wrapped(text, width: width, size: size, weight: weight) {
                    label(part, textX, y, width, size: size, weight: weight, color: color)
                    y += size + 4
                }
                context.setURL(source, for: CGRect(x: textX, y: top, width: width, height: y - top))
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
                let frame = CGRect(x: 38 + (side - size.width) / 2, y: start + (height - size.height) / 2,
                                   width: size.width, height: size.height)
                image.draw(in: frame)
                context.setURL(object.source, for: frame)
                y = start + height
            }
            y += 12
        }

        func drawRankings(_ rows: [StrengthProgress.RankedFamily]) {
            let columns: [(title: String, x: CGFloat, width: CGFloat)] = [
                ("Exercise", 38, 201), ("Sessions", 242, 62), ("Recorded reps", 307, 74),
                ("Load per rep", 384, 81), ("Lifted volume", 468, 106),
            ]
            func heading(includeTotals: Bool = false) {
                begin("Most trained exercises", subtitle: language.text("Each completed workout counts once per exercise family."))
                y = 154
                if includeTotals { drawLifetimeTotals(rows) }
                let explanation = language.text("Volume sums each recorded load × reps. An asterisk marks incomplete records.")
                    + " " + language.text("Load per rep averages only reps with a measured load.")
                for part in wrapped(explanation, width: 536, size: 10) {
                    label(part, 38, y, 536, size: 10, color: muted)
                    y += 14
                }
                y += 9
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
                let lines = wrapped(title, width: columns[0].width - indent - 4, size: size, weight: fontWeight)
                if y + min(500, CGFloat(lines.count) * (size + 3) + 8) > 730 { heading() }
                if !variant { line(38, y, 574, y, color: rule) }
                let reps = totals.recordedReps.map { String($0) + (totals.missingReps ? "*" : "") }
                let mark = totals.missingVolume ? "*" : ""
                let lifted = totals.liftedVolumeKG.map { volume($0) + mark }
                let average = totals.averageLoadKG.map { weight($0) + mark }
                let values = [String(sessions), reps ?? "—", average ?? "—", lifted ?? "—"]
                for (index, value) in values.enumerated() {
                    let column = columns[index + 1]
                    label(value, column.x, y + 3, column.width, size: size, weight: fontWeight,
                          color: variant ? muted : ink, alignment: .right)
                }
                for part in lines {
                    if y + size + 6 > 730 { heading() }
                    label(part, 38 + indent, y + 3, columns[0].width - indent, size: size,
                          weight: fontWeight, color: variant ? muted : ink)
                    y += size + 3
                }
                y += variant ? 3 : 6
            }

            heading(includeTotals: true)
            if rows.isEmpty {
                label(language.text("No exercises recorded yet."), 38, y + 8, 536)
                y += 34
            }
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

        private enum ChartMetric {
            case reps, volume, load

            var heading: String {
                switch self {
                case .reps: "Reps per session"
                case .volume: "Recorded volume per session"
                case .load: "Strength progress"
                }
            }

            var subtitle: String {
                switch self {
                case .reps: "Each point sums recorded reps across all variations in one completed workout."
                case .volume: "Split squats and lunges use the load and reps entered for each set once. Left and right sides are not recorded separately."
                case .load: "Heaviest recorded working load in each completed session."
                }
            }
        }

        private struct ChartPoint {
            let date: Date
            let value: Double
            var reps: Int? = nil
            var partial = false

            init?(date: String, value: Double?, reps: Int? = nil, partial: Bool = false) {
                guard let date = APEXDateMath.date(from: date), let value, value.isFinite, value > 0 else { return nil }
                self.date = date
                self.value = value
                self.reps = reps
                self.partial = partial
            }
        }

        func drawCharts(_ families: [StrengthProgress.RankedFamily]) {
            var drewChart = false
            for metric in [ChartMetric.reps, .volume, .load] {
                var firstInSection = true
                func chart(_ title: String, _ points: [ChartPoint]) {
                    guard !points.isEmpty else { return }
                    drawChart(title, points: points, metric: metric, firstInSection: firstInSection)
                    firstInSection = false
                    drewChart = true
                }
                for family in families {
                    switch metric {
                    case .reps:
                        chart(family.name, family.sessions.compactMap {
                            ChartPoint(date: $0.date, value: $0.totals.recordedReps.map(Double.init),
                                       partial: $0.totals.missingReps)
                        })
                    case .volume:
                        if family.key == "family:split_squat" || family.key == "family:lunge" {
                            chart(family.name, family.sessions.compactMap {
                                ChartPoint(date: $0.date, value: $0.totals.liftedVolumeKG, partial: $0.totals.missingVolume)
                            })
                        }
                    case .load:
                        for variant in family.variants {
                            chart(variant.name, variant.points.compactMap {
                                ChartPoint(date: $0.date, value: $0.topWeight, reps: $0.topReps)
                            })
                        }
                    }
                }
            }
            if !drewChart {
                if y + 100 > 730 { begin("Strength progress", subtitle: "") }
                else {
                    y += 28
                    label(language.text("Strength progress"), 38, y, 536, size: 20, weight: .bold)
                    y += 34
                }
                label(language.text("No recorded reps or working loads yet."), 38, y, 536, size: 13, color: muted)
            }
        }

        private func drawChart(_ name: String, points: [ChartPoint], metric: ChartMetric, firstInSection: Bool) {
            guard let first = points.first, let last = points.last,
                  let peak = points.max(by: { $0.value < $1.value }) else { return }
            let highest = peak.value
            let calendar = WorkoutChartCalendar(first: first.date, last: last.date)
            let title = wrapped(language.text(name), width: 530, size: 19, weight: .bold)
            func heading() {
                begin(metric.heading, subtitle: "")
                y = 128
                for part in wrapped(language.text(metric.subtitle), width: 536, size: 12) {
                    label(part, 38, y, 536, size: 12, color: muted)
                    y += 17
                }
                y = max(170, y + 10)
            }
            let chartHeight = 260 + CGFloat(title.count - 1) * 24
            if firstInSection || y + chartHeight > 730 { heading() }
            for titleLine in title {
                if y + 28 > 730 { heading() }
                label(titleLine, 38, y, 536, size: 19, weight: .bold)
                y += 24
            }
            y -= 24
            if y + 260 > 730 { heading() }
            func valueLabel(_ value: Double) -> String {
                switch metric {
                case .reps: number(value) + " " + language.text("reps")
                case .volume, .load: weight(value)
                }
            }
            let field = CGRect(x: 38, y: y + 33, width: 536, height: 141)
            UIColor(red: 0.96, green: 0.95, blue: 0.99, alpha: 1).setFill()
            UIBezierPath(roundedRect: field, cornerRadius: 12).fill()
            let plot = CGRect(x: 102, y: field.minY + 15, width: 436, height: 92)
            let midpoint = metric == .reps ? (highest / 2).rounded(.down) : highest / 2
            let ticks = midpoint > 0 ? [0, midpoint, highest] : [0, highest]
            for tick in ticks {
                let tickY = plot.maxY - CGFloat(tick / highest) * plot.height
                label(valueLabel(tick), 40, tickY - 7, 56, size: 10, color: muted, alignment: .right)
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
            func display(_ point: ChartPoint) -> String {
                valueLabel(point.value) + (point.partial ? "*" : "")
                    + (point.reps.map { " × \($0) " + language.text("reps") } ?? "")
            }
            let change = last.value - first.value
            let delta = (change > 0 ? "+" : "") + valueLabel(change)
            func endpoint(_ title: String, _ index: Int) -> String {
                let date = calendar.label(points[index].date, locale: language.language.locale)
                return language.text(title) + " · #" + String(index + 1) + " · " + date
            }
            let summary = [(endpoint("First", 0), display(first)), (endpoint("Latest", points.count - 1), display(last)),
                           (language.text("Change"), points.count == 1 || first.partial || last.partial ? "—" : delta)]
            for (metric, item) in summary.enumerated() {
                let x = 38 + CGFloat(metric) * 182
                let tint = metric == 2 ? UIColor(red: 0.97, green: 0.94, blue: 0.77, alpha: 1)
                                       : UIColor(white: 0.965, alpha: 1)
                tint.setFill()
                UIBezierPath(roundedRect: CGRect(x: x, y: y + 183, width: 172, height: 47), cornerRadius: 9).fill()
                label(item.0, x + 10, y + 186, 153, size: 10, color: muted)
                label(item.1, x + 10, y + 200, 153, size: 15, weight: .bold)
            }
            if points.count == 1 {
                label(language.text("One recorded session"), 38, y + 232, 536, size: 11, color: muted)
            }
            if points.count > 1 {
                let record = [language.text(metric == .load ? "Best working load" : "Best session"), display(peak),
                              peak.date.formatted(Date.FormatStyle(locale: language.language.locale, timeZone: .gmt).year().month(.abbreviated).day())].joined(separator: " · ")
                label(record, 38, y + 235, 536, size: 10, color: muted)
            }
            line(38, y + 260, 574, y + 260, color: rule)
            y += 286
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
