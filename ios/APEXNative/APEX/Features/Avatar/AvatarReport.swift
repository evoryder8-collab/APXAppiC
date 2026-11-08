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
        let exercises = StrengthProgress.exerciseHistory(ownerID: ownerID, sessions: sessions, logs: logs)
        let families = StrengthProgress.rankedFamilies(exercises)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            let pages = Pages(context: context, report: self)
            pages.drawScores(scores)
            pages.drawRankings(families)
            pages.drawCharts(families.flatMap(\.variants).filter { !$0.points.isEmpty }.prefix(5))
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

        func drawRankings(_ rows: [StrengthProgress.RankedFamily]) {
            func heading() {
                begin("Most trained exercises", subtitle: language.text("Each completed workout counts once per exercise family."))
                label(language.text("Exercise"), 76, y, 335, size: 11, weight: .bold, color: muted)
                label(language.text("Sessions"), 422, y, 152, size: 11, weight: .bold, color: muted, alignment: .right)
                y += 24
            }
            heading()
            if rows.isEmpty {
                label(language.text("No exercises recorded yet."), 38, y + 8, 536)
                y += 34
            }
            for (index, row) in rows.enumerated() {
                let title = language.text(row.name) + " · " + language.text(row.region.rawValue)
                let lines = wrapped(title, width: 390, size: 13)
                let detail = row.variants.map {
                    language.text($0.name) + " (" + String($0.sessionCount) + ")"
                }.joined(separator: " · ")
                let detailLines = row.showsVariants ? wrapped(detail, width: 390, size: 10) : []
                let rowHeight = 12 + 17 * CGFloat(lines.count) + 13 * CGFloat(detailLines.count)
                if y + min(rowHeight, 730 - 194) > 730 { heading() }
                line(38, y, 574, y, color: rule)
                label(String(index + 1), 38, y + 6, 32, size: 12, weight: .bold, color: green)
                label(String(row.sessionCount), 478, y + 6, 96, size: 13, weight: .semibold, alignment: .right)
                for nameLine in lines {
                    if y + 24 > 730 { heading() }
                    label(nameLine, 76, y + 6, 395, size: 13)
                    y += 17
                }
                for detailLine in detailLines {
                    if y + 20 > 730 { heading() }
                    label(detailLine, 76, y + 4, 395, size: 10, color: muted)
                    y += 13
                }
                y += 12
            }
        }

        func drawCharts(_ rows: ArraySlice<StrengthProgress.ExerciseHistory>) {
            let subtitle = language.text("Heaviest recorded working load in each completed session.")
            if rows.isEmpty {
                if y + 100 > 730 { begin("Strength progress", subtitle: subtitle) }
                else {
                    y += 28
                    label(language.text("Strength progress"), 38, y, 536, size: 20, weight: .bold)
                    y += 34
                }
                label(language.text("No loaded sessions recorded yet."), 38, y, 536, size: 13, color: muted)
                return
            }
            for (index, row) in rows.enumerated() {
                let points = row.points.filter { $0.topWeight.isFinite && $0.topWeight > 0 }
                guard let first = points.first, let last = points.last,
                      let highest = points.map(\.topWeight).max() else { continue }
                let title = wrapped(language.text(row.name), width: 530, size: 19, weight: .bold)
                let chartHeight = 260 + CGFloat(title.count - 1) * 24
                if index == 0 || y + chartHeight > 730 { begin("Strength progress", subtitle: subtitle) }
                for titleLine in title {
                    if y + 28 > 730 { begin("Strength progress", subtitle: subtitle) }
                    label(titleLine, 38, y, 536, size: 19, weight: .bold)
                    y += 24
                }
                y -= 24
                if y + 260 > 730 { begin("Strength progress", subtitle: subtitle) }
                guard let calendar = WorkoutChartCalendar(from: first.date, to: last.date) else { continue }
                let field = CGRect(x: 38, y: y + 33, width: 536, height: 141)
                UIColor(red: 0.96, green: 0.95, blue: 0.99, alpha: 1).setFill()
                UIBezierPath(roundedRect: field, cornerRadius: 12).fill()
                let plot = CGRect(x: 102, y: field.minY + 15, width: 436, height: 92)
                for tick in 0...2 {
                    let fraction = CGFloat(tick) / 2
                    let tickY = plot.maxY - fraction * plot.height
                    label(weight(highest * fraction), 40, tickY - 7, 56, size: 10, color: muted, alignment: .right)
                    line(plot.minX, tickY, plot.maxX, tickY, color: rule)
                }
                for tick in calendar.ticks {
                    let x = plot.minX + calendar.position(tick) * plot.width
                    line(x, plot.minY, x, plot.maxY, color: rule.withAlphaComponent(0.65))
                    label(calendar.label(tick, locale: language.language.locale), x - 34,
                          plot.maxY + 7, 68, size: 9, color: muted, alignment: .center)
                }
                let coordinates = points.compactMap { point -> CGPoint? in
                    guard let date = APEXDateMath.date(from: point.date) else { return nil }
                    return CGPoint(x: plot.minX + calendar.position(date) * plot.width,
                                   y: plot.maxY - point.topWeight / highest * plot.height)
                }
                drawLoadTrace(coordinates, baseline: plot.maxY)
                func set(_ point: StrengthProgress.Point) -> String {
                    weight(point.topWeight) + (point.topReps.map { " × \($0) " + language.text("reps") } ?? "")
                }
                let change = last.topWeight - first.topWeight
                let summary = [(language.text("First"), set(first)), (language.text("Latest"), set(last)),
                               (language.text("Change"), points.count == 1 ? "—" : (change > 0 ? "+" : "") + weight(change))]
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
                if points.count > 1, let peak = points.first(where: { $0.topWeight == highest }),
                   let date = APEXDateMath.date(from: peak.date) {
                    let record = [language.text("Best working load"), set(peak),
                                  date.formatted(Date.FormatStyle(locale: language.language.locale, timeZone: .gmt).year().month(.abbreviated).day())].joined(separator: " · ")
                    label(record, 38, y + 235, 536, size: 10, color: muted)
                }
                line(38, y + 260, 574, y + 260, color: rule)
                y += 286
            }
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
