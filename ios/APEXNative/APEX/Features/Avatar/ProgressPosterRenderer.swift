import CoreGraphics
import SwiftUI
import UIKit

/*
 * The exported progress card, drawn in Core Graphics to the web canvas's own
 * geometry rather than an approximation of it.
 *
 * Every number here comes from src/lib/progressComparison.ts: the 1080x1350
 * canvas, the 62pt outer radius, the 48pt photo block inset 36 from the edge,
 * the two scrims, the violet and cyan glows, the lit divider, and the
 * baselines each line of type sits on. Matching them is the difference
 * between a card that looks designed and one that looks generated.
 */
enum ProgressPosterRenderer {
    private static let canvas = CGSize(width: 1080, height: 1350)
    private static let ground = UIColor(red: 0.031, green: 0.039, blue: 0.071, alpha: 1) // #080a12
    private static let shade = UIColor(red: 0.012, green: 0.020, blue: 0.047, alpha: 1) // #03050c

    struct Input {
        var before: UIImage
        var after: UIImage
        var beforeMoment: String
        var afterMoment: String
        var beforePose: String
        var afterPose: String
        var views: ProgressPhotoEngine.ComparisonViews
        var content: ProgressComparison.PosterContent
        var torsoLayout: Bool
        var athleteName: String
        var daysApart: Int
        var workouts: Int
        var averageLoadDeltaKG: Double?
        var matchedExercises: Int
        var loadedSets: Int
        var beforeWeightKG: Double?
        var afterWeightKG: Double?
    }

    static func render(_ input: Input) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)

        return renderer.image { context in
            let cg = context.cgContext

            let outer = CGRect(x: 20, y: 20, width: 1040, height: 1310)
            cg.saveGState()
            UIBezierPath(roundedRect: outer, cornerRadius: 62).addClip()
            ground.setFill()
            cg.fill(outer)

            let photoX: CGFloat = 36
            let photoY: CGFloat = input.torsoLayout ? 92 : 36
            let photoWidth: CGFloat = 1008
            let photoHeight: CGFloat = input.torsoLayout ? 1120 : 1278
            let photo = CGRect(x: photoX, y: photoY, width: photoWidth, height: photoHeight)
            let paneWidth = photoWidth / 2

            cg.saveGState()
            UIBezierPath(roundedRect: photo, cornerRadius: 48).addClip()
            drawCover(
                input.before, view: input.views.left,
                in: CGRect(x: photoX, y: photoY, width: paneWidth, height: photoHeight)
            )
            drawCover(
                input.after, view: input.views.right,
                in: CGRect(x: photoX + paneWidth, y: photoY, width: paneWidth, height: photoHeight)
            )

            /* Two scrims, so white type stays readable over a bright bathroom
               and a dark kitchen without dimming the body between them. */
            linearShade(
                cg, in: CGRect(x: photoX, y: photoY, width: photoWidth, height: 330),
                stops: [(0, 0.94), (0.56, 0.56), (1, 0)]
            )
            let bottomHeight: CGFloat = input.content.stats ? 420 : 220
            linearShade(
                cg,
                in: CGRect(x: photoX, y: photoY + photoHeight - bottomHeight, width: photoWidth, height: bottomHeight),
                stops: [(0, 0), (0.44, 0.62), (1, 0.96)]
            )
            radialGlow(cg, centre: CGPoint(x: 930, y: 90), radius: 390,
                       colour: UIColor(red: 0.545, green: 0.361, blue: 0.965, alpha: 0.31), clip: photo)
            radialGlow(cg, centre: CGPoint(x: 120, y: 1240), radius: 370,
                       colour: UIColor(red: 0.133, green: 0.827, blue: 0.933, alpha: 0.19), clip: photo)
            cg.restoreGState()

            let border = UIBezierPath(roundedRect: photo, cornerRadius: 48)
            border.lineWidth = 2
            UIColor.white.withAlphaComponent(0.2).setStroke()
            border.stroke()

            /* The divider is lit in the middle and fades at both ends, which
               is what stops two photos reading as one wide image. */
            drawDivider(cg, x: photoX + paneWidth - 1, y: photoY, height: photoHeight)

            if input.content.stats {
                text("APEX • PRIVATE PROGRESS", at: CGPoint(x: 72, y: 88 - 21),
                     font: mono(21, .black), colour: UIColor(red: 0.773, green: 0.722, blue: 1, alpha: 1))
                if input.content.athlete, !input.athleteName.isEmpty {
                    text(input.athleteName, at: CGPoint(x: 72, y: 128 - 25),
                         font: display(25, .bold), colour: .white.withAlphaComponent(0.72))
                }
            }

            let labelY: CGFloat = input.content.stats ? 198 : 118
            let momentY: CGFloat = input.content.stats ? 228 : 148
            label("BEFORE", moment: input.beforeMoment, pose: input.beforePose,
                  x: photoX + 28, labelY: labelY, momentY: momentY,
                  alignment: .left, content: input.content)
            label("AFTER", moment: input.afterMoment, pose: input.afterPose,
                  x: photoX + photoWidth - 28, labelY: labelY, momentY: momentY,
                  alignment: .right, content: input.content)

            if input.content.stats {
                drawStats(input)
                if let before = input.beforeWeightKG, let after = input.afterWeightKG {
                    drawWeight(before: before, after: after)
                }
                if input.content.privateFooter {
                    text("CREATED PRIVATELY ON DEVICE", at: CGPoint(x: 72, y: 1287 - 14),
                         font: mono(14, .bold), colour: .white.withAlphaComponent(0.48))
                }
            }

            text("A P E X", at: CGPoint(x: 1008 - 300, y: 1289 - 25), width: 300,
                 font: display(25, .black), colour: .white, alignment: .right)
            cg.restoreGState()
        }
    }

    // MARK: - Drawing helpers

    private static func drawCover(
        _ image: UIImage,
        view: ProgressPhotoEngine.ComparisonView,
        in rect: CGRect
    ) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.clip(to: rect)
        let scale = max(rect.width / image.size.width, rect.height / image.size.height) * view.scale
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        /* The zoom and offset the person set on screen, carried through, so
           the export is the arrangement they actually chose. */
        let origin = CGPoint(
            x: rect.midX - size.width / 2 + view.x * rect.width / 100,
            y: rect.midY - size.height / 2 + view.y * rect.height / 100
        )
        image.draw(in: CGRect(origin: origin, size: size))
        context.restoreGState()
    }

    private static func linearShade(
        _ context: CGContext,
        in rect: CGRect,
        stops: [(CGFloat, CGFloat)]
    ) {
        let colours = stops.map { shade.withAlphaComponent($0.1).cgColor } as CFArray
        let locations = stops.map { $0.0 }
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: locations
        ) else { return }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
        context.restoreGState()
    }

    private static func radialGlow(
        _ context: CGContext,
        centre: CGPoint,
        radius: CGFloat,
        colour: UIColor,
        clip: CGRect
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [colour.cgColor, colour.withAlphaComponent(0).cgColor] as CFArray,
            locations: [0, 1]
        ) else { return }
        context.saveGState()
        context.clip(to: clip)
        context.drawRadialGradient(
            gradient, startCenter: centre, startRadius: 0,
            endCenter: centre, endRadius: radius, options: []
        )
        context.restoreGState()
    }

    private static func drawDivider(_ context: CGContext, x: CGFloat, y: CGFloat, height: CGFloat) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor.white.withAlphaComponent(0.08).cgColor,
                UIColor.white.withAlphaComponent(0.95).cgColor,
                UIColor.white.withAlphaComponent(0.08).cgColor,
            ] as CFArray,
            locations: [0, 0.5, 1]
        ) else { return }
        context.saveGState()
        context.clip(to: CGRect(x: x, y: y, width: 2, height: height))
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: x, y: y), end: CGPoint(x: x, y: y + height), options: []
        )
        context.restoreGState()
    }

    private static func label(
        _ title: String,
        moment: String,
        pose: String,
        x: CGFloat,
        labelY: CGFloat,
        momentY: CGFloat,
        alignment: NSTextAlignment,
        content: ProgressComparison.PosterContent
    ) {
        let width: CGFloat = 460
        let originX = alignment == .left ? x : x - width
        text(title, at: CGPoint(x: originX, y: labelY - 22), width: width,
             font: mono(22, .black), colour: .white, alignment: alignment)
        text(moment, at: CGPoint(x: originX, y: momentY - 16), width: width,
             font: mono(16, .bold), colour: .white.withAlphaComponent(0.78), alignment: alignment)
        if content.pose {
            text(pose, at: CGPoint(x: originX, y: 255 - 15), width: width,
                 font: mono(15, .bold), colour: .white.withAlphaComponent(0.58), alignment: alignment)
        }
    }

    private static func drawStats(_ input: Input) {
        let statsX: CGFloat = 60
        let statsY: CGFloat = 1018
        let statsWidth: CGFloat = 960
        let statsHeight: CGFloat = 176
        let box = CGRect(x: statsX, y: statsY, width: statsWidth, height: statsHeight)
        UIColor.white.withAlphaComponent(0.07).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 34).fill()

        let columns: [(String, String, String)] = [
            ("DAYS", "\(input.daysApart)", "BETWEEN"),
            ("WORKOUTS", "\(input.workouts)", "COMPLETED"),
            (
                "AVG LOAD / SET",
                input.averageLoadDeltaKG.map { "\($0 > 0 ? "+" : "")\(formatted($0)) KG" } ?? "-",
                "\(input.matchedExercises) MATCHED"
            ),
            ("WEIGHTED SETS", "\(input.loadedSets)", "LOGGED"),
        ]
        let columnWidth = statsWidth / CGFloat(columns.count)
        for (index, column) in columns.enumerated() {
            let x = statsX + CGFloat(index) * columnWidth + 26
            if index > 0 {
                UIColor.white.withAlphaComponent(0.12).setFill()
                UIRectFill(CGRect(x: statsX + CGFloat(index) * columnWidth, y: statsY + 26, width: 1, height: statsHeight - 52))
            }
            text(column.0, at: CGPoint(x: x, y: statsY + 42 - 13), width: columnWidth - 30,
                 font: mono(13, .bold), colour: .white.withAlphaComponent(0.55))
            text(column.1, at: CGPoint(x: x, y: statsY + 96 - 34), width: columnWidth - 30,
                 font: display(34, .black), colour: .white)
            text(column.2, at: CGPoint(x: x, y: statsY + 130 - 13), width: columnWidth - 30,
                 font: mono(13, .bold), colour: .white.withAlphaComponent(0.45))
        }
    }

    private static func drawWeight(before: Double, after: Double) {
        let delta = ((after - before) * 10).rounded() / 10
        let line = "BODY WEIGHT  \(formatted(before)) → \(formatted(after)) KG  (\(delta > 0 ? "+" : "")\(formatted(delta)) KG)"
        UIColor(red: 0.722, green: 0.655, blue: 1, alpha: 0.18).setFill()
        UIBezierPath(roundedRect: CGRect(x: 72, y: 1210, width: 560, height: 50), cornerRadius: 25).fill()
        text(line, at: CGPoint(x: 94, y: 1242 - 16), width: 520,
             font: mono(16, .black), colour: UIColor(red: 0.878, green: 0.851, blue: 1, alpha: 1))
    }

    private static func text(
        _ value: String,
        at origin: CGPoint,
        width: CGFloat = 600,
        font: UIFont,
        colour: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        (value as NSString).draw(
            in: CGRect(x: origin.x, y: origin.y, width: width, height: font.lineHeight + 8),
            withAttributes: [
                .font: font,
                .foregroundColor: colour,
                .paragraphStyle: paragraph,
            ]
        )
    }

    private static func mono(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func display(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Written to a temporary file so it can be shared, never uploaded.
    static func write(_ image: UIImage) -> URL? {
        guard let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apex-progress-\(Int(Date().timeIntervalSince1970)).png")
        return (try? data.write(to: url)) == nil ? nil : url
    }
}
