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
            if let trainingProfile, trainingProfile.classifiedWorkouts > 0 {
                pages.drawTrainingProfile(trainingProfile)
            }
            if !families.isEmpty {
                pages.drawLifetimeTotals(families)
                pages.drawCharts(families)
                pages.drawRankings(families)
            }
            pages.drawScores(scores)
            if pages.page == 0 {
                pages.begin("Avatar report", subtitle: pages.language.text("Building your baseline"))
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
            label(language.text("Avatar report"), 38, 758, 440, size: 10, color: muted)
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
                let card = CGRect(x: x, y: top, width: 259, height: 121)
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
            label(language.text("90-day training profile"), 58, top + 15, 496, size: 12, weight: .semibold, color: mint)
            y = top + 32
            for part in title {
                label(part, 58, y, 496, size: 32, weight: .bold, color: .white)
                y += 39
            }
            label(language.dateKey(profile.from) + " – " + language.dateKey(profile.to),
                  58, y + 3, 496, size: 12, color: mint)
            y = top + height + 16
            let metrics = profile.metrics(language: language).filter { $0.value != "0" || $0.key == "Workouts per week" }
            let summary = metrics.map { language.text($0.key) + " " + $0.value }.joined(separator: "   ·   ")
            paragraph(summary, size: 12)
            if let note = profile.note { paragraph(language.text(note), size: 11, color: muted) }
            if let match = profile.matchedLoad {
                y += 4
                paragraph(language.text("Matched working load") + " · " + language.text(match.exercise) + " · "
                          + language.format("%d reps", match.reps), size: 12)
                paragraph(language.text("Previous 45 days") + " " + weight(match.earlierKG) + "   →   "
                          + language.text("Last 45 days") + " " + weight(match.recentKG), size: 12, color: green)
                paragraph(language.text("Median session-best load at the same rep count."), size: 10, color: muted)
            }
            y += 16
        }

        private func paragraph(_ text: String, size: CGFloat, color: UIColor? = nil) {
            for part in wrapped(text, width: 536, size: size) {
                label(part, 38, y, 536, size: size, color: color)
                y += size + 5
            }
        }

        func volume(_ kg: Double) -> String {
            LiftedMassComparison.formattedMass(kg, locale: language.language.locale)
        }

        func drawLifetimeTotals(_ rows: [StrengthProgress.RankedFamily]) {
            let totals = rows.reduce(into: StrengthProgress.LifetimeTotals()) { $0.add($1.totals) }
            if page == 0 || y > 420 { beginPage() }
            label(language.text("All-time training totals"), 38, y, 536, size: 21, weight: .bold)
            y += 31
            let dates = rows.flatMap { $0.sessions.map(\.date) }.filter { APEXDateMath.date(from: $0) != nil }
            if let first = dates.min(), let last = dates.max() {
                let range = first == last ? language.dateKey(first) : language.dateKey(first) + " – " + language.dateKey(last)
                label(range, 38, y, 536, size: 11, color: muted)
                y += 20
            }
            let metrics: [(String, String?)] = [
                ("Performed sets", String(totals.sets)),
                ("Recorded reps", recordedReps(totals)),
                ("Lifted volume", liftedVolume(totals))
            ]
            for (index, metric) in metrics.enumerated() {
                guard let value = metric.1 else { continue }
                let x = 38 + CGFloat(index) * 182
                label(language.text(metric.0), x, y, 175, size: 11, color: muted)
                label(value, x, y + 16, 175, size: 18, weight: .bold)
            }
            y += 46
            if let kg = totals.liftedVolumeKG {
                drawComparisons(object: LiftedMassComparison.caption(kilograms: kg),
                                hero: LiftedMassComparison.heroCaption(kilograms: kg))
            }
            let note = language.text("Known external load × recorded reps. Body mass, assistance and timed work are excluded from volume. Skipped sets are excluded from all totals.")
            paragraph(note, size: 10, color: muted)
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
            func heading() {
                begin("Most trained exercises", subtitle: language.text("Each completed workout counts once per exercise family."))
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
                let reps = recordedReps(totals)
                let mark = totals.missingVolume ? "*" : ""
                let lifted = liftedVolume(totals)
                let average = totals.averageLoadKG.map { weight($0) + mark }
                let values = [String(sessions), reps ?? "", average ?? "", lifted ?? ""]
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
            totals.liftedVolumeKG.map { volume($0) + (totals.missingVolume ? "*" : "") }
        }

        private struct ChartPoint {
            let date: Date
            let value: Double
            let reps: Int?

            init?(_ point: StrengthProgress.Point) {
                guard let date = APEXDateMath.date(from: point.date), point.topWeight.isFinite, point.topWeight > 0 else { return nil }
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
                    guard points.count >= 2 else { continue }
                    drawChart(variant, points: points, firstInSection: firstInSection)
                    firstInSection = false
                }
            }
        }

        private func drawChart(_ variant: StrengthProgress.ExerciseHistory, points: [ChartPoint], firstInSection: Bool) {
            guard let first = points.first, let last = points.last,
                  let peak = points.max(by: { $0.value < $1.value }) else { return }
            let highest = peak.value
            let calendar = WorkoutChartCalendar(first: first.date, last: last.date)
            let title = wrapped(language.text(variant.name), width: 530, size: 19, weight: .bold)
            let totals = [(language.text("Recorded reps"), recordedReps(variant.totals)),
                          (language.text("Lifted volume"), liftedVolume(variant.totals))]
                .compactMap { key, value in value.map { key + " " + $0 } }
            let totalLines = totals.isEmpty ? [] : wrapped(language.text("All time") + "   ·   " + totals.joined(separator: "   ·   "),
                                                         width: 536, size: 11, weight: .semibold)
            let height = 248 + CGFloat(title.count - 1) * 24 + CGFloat(totalLines.count) * 16
            func heading() {
                begin("Strength progress", subtitle: language.text("Heaviest recorded working load in each completed session."))
            }
            if firstInSection || y + height > 730 { heading() }
            for titleLine in title {
                if y + 28 > 730 { heading() }
                label(titleLine, 38, y, 536, size: 19, weight: .bold)
                y += 24
            }
            y -= 24
            if y + 248 + CGFloat(totalLines.count) * 16 > 730 { heading() }
            let field = CGRect(x: 38, y: y + 33, width: 536, height: 141)
            UIColor(red: 0.96, green: 0.95, blue: 0.99, alpha: 1).setFill()
            UIBezierPath(roundedRect: field, cornerRadius: 12).fill()
            let plot = CGRect(x: 102, y: field.minY + 15, width: 436, height: 92)
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
            func display(_ point: ChartPoint) -> String {
                weight(point.value)
                    + (point.reps.map { " × \($0) " + language.text("reps") } ?? "")
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
            label(record, 38, y + 233, 536, size: 10, color: muted)
            y += 248
            for part in totalLines {
                label(part, 38, y, 536, size: 11, weight: .semibold)
                y += 16
            }
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
