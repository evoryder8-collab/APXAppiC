import CoreGraphics
import SwiftUI
import UIKit

/*
 * The exported progress card, drawn in Core Graphics.
 *
 * The web draws this on a canvas; the layout is the same because the output
 * is the thing people keep and share: a dark frame, the two photos meeting in
 * the middle, BEFORE and AFTER with their moments, and the APEX wordmark.
 *
 * Minimal exports carry only APEX, the two labels and each photo's date and
 * time. Detailed adds the stats. Nothing is uploaded to produce it: the card
 * is rendered on device from photos already on device.
 */
enum ProgressPosterRenderer {
    /// Rendered at 2x the on-screen card so the PNG stays sharp when shared.
    private static let width: CGFloat = 1080
    private static let height: CGFloat = 1350

    static func render(
        before: UIImage,
        after: UIImage,
        beforeMoment: String,
        afterMoment: String,
        views: ProgressPhotoEngine.ComparisonViews,
        content: ProgressComparison.PosterContent,
        daysApart: Int,
        workouts: Int
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)

        return renderer.image { context in
            let cg = context.cgContext
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)

            UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1).setFill()
            cg.fill(bounds)

            let inset: CGFloat = 34
            let frame = bounds.insetBy(dx: inset, dy: inset)
            let clip = UIBezierPath(roundedRect: frame, cornerRadius: 44)
            cg.saveGState()
            clip.addClip()

            let half = CGRect(x: frame.minX, y: frame.minY, width: frame.width / 2, height: frame.height)
            draw(before, in: half, view: views.left, context: cg)
            let rightHalf = CGRect(x: frame.midX, y: frame.minY, width: frame.width / 2, height: frame.height)
            draw(after, in: rightHalf, view: views.right, context: cg)

            /* A soft top and bottom scrim so the labels stay readable over a
               bright photo without dimming the body itself. */
            scrim(in: frame, context: cg)
            cg.restoreGState()

            label("BEFORE", moment: beforeMoment, in: half, alignment: .left, content: content)
            label("AFTER", moment: afterMoment, in: rightHalf, alignment: .right, content: content)

            if content.stats {
                stats(daysApart: daysApart, workouts: workouts, in: frame)
            }

            wordmark(in: frame)
        }
    }

    private static func draw(
        _ image: UIImage,
        in rect: CGRect,
        view: ProgressPhotoEngine.ComparisonView,
        context: CGContext
    ) {
        context.saveGState()
        context.clip(to: rect)
        /* Cover the half, then apply the zoom and offset the person set on
           screen, so the export is the arrangement they actually chose. */
        let scale = max(rect.width / image.size.width, rect.height / image.size.height) * view.scale
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(
            x: rect.midX - size.width / 2 + view.x * rect.width / 100,
            y: rect.midY - size.height / 2 + view.y * rect.height / 100
        )
        image.draw(in: CGRect(origin: origin, size: size))
        context.restoreGState()
    }

    private static func scrim(in rect: CGRect, context: CGContext) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor.black.withAlphaComponent(0.55).cgColor,
                UIColor.clear.cgColor,
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.6).cgColor,
            ] as CFArray,
            locations: [0, 0.22, 0.72, 1]
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
    }

    private static func label(
        _ title: String,
        moment: String,
        in rect: CGRect,
        alignment: NSTextAlignment,
        content: ProgressComparison.PosterContent
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let padding: CGFloat = 30
        let box = rect.insetBy(dx: padding, dy: 0)

        (title as NSString).draw(
            in: CGRect(x: box.minX, y: box.minY + 34, width: box.width, height: 34),
            withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 21, weight: .black),
                .foregroundColor: UIColor.white,
                .kern: 2.4,
                .paragraphStyle: paragraph,
            ]
        )
        (moment as NSString).draw(
            in: CGRect(x: box.minX, y: box.minY + 68, width: box.width, height: 28),
            withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.72),
                .paragraphStyle: paragraph,
            ]
        )
    }

    private static func stats(daysApart: Int, workouts: Int, in rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        let text = "\(daysApart) DAYS · \(workouts) WORKOUTS"
        (text as NSString).draw(
            in: CGRect(x: rect.minX + 30, y: rect.maxY - 62, width: rect.width - 220, height: 30),
            withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.82),
                .kern: 1.6,
                .paragraphStyle: paragraph,
            ]
        )
    }

    private static func wordmark(in rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        ("A P E X" as NSString).draw(
            in: CGRect(x: rect.maxX - 240, y: rect.maxY - 66, width: 210, height: 36),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .black),
                .foregroundColor: UIColor.white,
                .kern: 3.2,
                .paragraphStyle: paragraph,
            ]
        )
    }

    /// Written to a temporary file so it can be shared, never uploaded.
    static func write(_ image: UIImage) -> URL? {
        guard let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apex-progress-\(Int(Date().timeIntervalSince1970)).png")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
