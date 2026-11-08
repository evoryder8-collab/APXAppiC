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

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { report in
            await report.pdfData()
        }
        .suggestedFileName([AppBrand.name, "Avatar"].joined(separator: "-") + ".pdf")
    }

    @MainActor
    func pdfData() -> Data {
        let scores = snapshots.filter { $0.userID == ownerID }.sorted { $0.date < $1.date }
        let exercises = StrengthProgress.exerciseHistory(ownerID: ownerID, sessions: sessions, logs: logs)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            let pages = Pages(context: context, report: self)
            pages.drawScores(scores)
            pages.drawRankings(exercises)
            pages.drawCharts(exercises.filter { !$0.points.isEmpty }.prefix(5))
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

        func drawRankings(_ rows: [StrengthProgress.ExerciseHistory]) {
            func heading() {
                begin("Most trained exercises", subtitle: language.text("Each completed workout counts once per exercise."))
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
                let lines = wrapped(language.text(row.name), width: 390, size: 13)
                let rowHeight = 12 + 17 * CGFloat(lines.count)
                if y + min(rowHeight, 730 - 194) > 730 { heading() }
                line(38, y, 574, y, color: rule)
                label(String(index + 1), 38, y + 6, 32, size: 12, weight: .bold, color: green)
                label(String(row.sessionCount), 478, y + 6, 96, size: 13, weight: .semibold, alignment: .right)
                for nameLine in lines {
                    if y + 24 > 730 { heading() }
                    label(nameLine, 76, y + 6, 395, size: 13)
                    y += 17
                }
                y += 12
            }
        }

        func drawCharts(_ rows: ArraySlice<StrengthProgress.ExerciseHistory>) {
            let subtitle = language.text("Heaviest recorded set per session, in workout order")
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
                let plot = CGRect(x: 105, y: y + 52, width: 456, height: 98)
                for tick in 0...2 {
                    let fraction = CGFloat(tick) / 2
                    let tickY = plot.maxY - fraction * plot.height
                    label(weight(highest * fraction), 38, tickY - 7, 58, size: 10, color: muted, alignment: .right)
                    line(plot.minX, tickY, plot.maxX, tickY, color: rule)
                }
                let coordinates = points.enumerated().map { offset, point in
                    let x = points.count == 1 ? plot.midX : plot.minX + CGFloat(offset) * plot.width / CGFloat(points.count - 1)
                    return CGPoint(x: x, y: plot.maxY - point.topWeight / highest * plot.height)
                }
                trace(coordinates)
                if points.count == 1 {
                    label(first.date, plot.minX, plot.maxY + 8, plot.width, size: 10, color: muted, alignment: .center)
                } else {
                    label(first.date, plot.minX, plot.maxY + 8, 180, size: 10, color: muted)
                    label(last.date, 374, plot.maxY + 8, 187, size: 10, color: muted, alignment: .right)
                }
                func set(_ point: StrengthProgress.Point) -> String {
                    weight(point.topWeight) + (point.topReps.map { " × \($0) " + language.text("reps") } ?? "")
                }
                let change = last.topWeight - first.topWeight
                let summary = [(language.text("First"), set(first)), (language.text("Latest"), set(last)),
                               (language.text("Change"), points.count == 1 ? "—" : (change > 0 ? "+" : "") + weight(change))]
                for (metric, item) in summary.enumerated() {
                    let x = 38 + CGFloat(metric) * 182
                    label(item.0, x, y + 187, 174, size: 11, color: muted)
                    label(item.1, x, y + 205, 174, size: 15, weight: .semibold)
                }
                if points.count == 1 {
                    label(language.text("One recorded session"), 38, y + 232, 536, size: 11, color: muted)
                }
                line(38, y + 260, 574, y + 260, color: rule)
                y += 286
            }
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
