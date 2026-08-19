import SwiftUI

/*
 * The alignment guides drawn over the camera, ported coordinate for
 * coordinate from the web's ProgressCamera so a photo framed on one client
 * lines up with a photo framed on the other.
 *
 * The guides exist because a comparison is only honest when the two images
 * were taken the same way. Standing on the same line, at the same height, in
 * the same frame is what turns two photographs into evidence.
 */

/// Full-body outline, drawn in the web's 240x560 space.
struct FullBodyGuideShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = min(rect.width / 240, rect.height / 560)
        let dx = rect.midX - 120 * scale
        let dy = rect.midY - 280 * scale
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * scale, y: dy + y * scale)
        }

        path.addEllipse(in: CGRect(
            x: dx + 92 * scale, y: dy + 20 * scale,
            width: 56 * scale, height: 56 * scale
        ))

        // Left arm, outer edge then down to the hand.
        path.move(to: point(91, 92))
        path.addCurve(to: point(44, 149), control1: point(64, 100), control2: point(47, 118))
        path.addLine(to: point(36, 258))

        // Right arm.
        path.move(to: point(149, 92))
        path.addCurve(to: point(196, 149), control1: point(176, 100), control2: point(193, 118))
        path.addLine(to: point(204, 258))

        // Left flank into the hip.
        path.move(to: point(91, 92))
        path.addCurve(to: point(80, 243), control1: point(96, 130), control2: point(93, 186))
        path.addLine(to: point(70, 314))

        // Right flank into the hip.
        path.move(to: point(149, 92))
        path.addCurve(to: point(160, 243), control1: point(144, 130), control2: point(147, 186))
        path.addLine(to: point(170, 314))

        // Waist.
        path.move(to: point(80, 243))
        path.addCurve(to: point(120, 258), control1: point(90, 253), control2: point(105, 258))
        path.addCurve(to: point(160, 243), control1: point(135, 258), control2: point(150, 253))

        // Legs and feet.
        path.move(to: point(80, 314))
        path.addLine(to: point(64, 501))
        path.move(to: point(160, 314))
        path.addLine(to: point(176, 501))
        path.move(to: point(64, 501))
        path.addLine(to: point(46, 525))
        path.move(to: point(176, 501))
        path.addLine(to: point(194, 525))
        return path
    }
}

/// The vertical centre line a stance is squared against.
struct FullBodyCentreLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = min(rect.width / 240, rect.height / 560)
        let dx = rect.midX - 120 * scale
        let dy = rect.midY - 280 * scale
        path.move(to: CGPoint(x: dx + 120 * scale, y: dy + 84 * scale))
        path.addLine(to: CGPoint(x: dx + 120 * scale, y: dy + 507 * scale))
        return path
    }
}

/// The floor line the feet return to every time.
struct FullBodyFloorLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = min(rect.width / 240, rect.height / 560)
        let dx = rect.midX - 120 * scale
        let dy = rect.midY - 280 * scale
        path.move(to: CGPoint(x: dx + 28 * scale, y: dy + 525 * scale))
        path.addLine(to: CGPoint(x: dx + 212 * scale, y: dy + 525 * scale))
        return path
    }
}

/// Torso outline, drawn in the web's 340x430 space.
struct TorsoGuideShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = min(rect.width / 340, rect.height / 430)
        let dx = rect.midX - 170 * scale
        let dy = rect.midY - 215 * scale
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * scale, y: dy + y * scale)
        }

        path.addEllipse(in: CGRect(
            x: dx + 128 * scale, y: dy + 16 * scale,
            width: 84 * scale, height: 84 * scale
        ))

        path.move(to: point(122, 126))
        path.addCurve(to: point(33, 201), control1: point(77, 135), control2: point(46, 160))
        path.addLine(to: point(18, 292))

        path.move(to: point(218, 126))
        path.addCurve(to: point(307, 201), control1: point(263, 135), control2: point(294, 160))
        path.addLine(to: point(322, 292))

        path.move(to: point(122, 126))
        path.addCurve(to: point(104, 314), control1: point(129, 178), control2: point(124, 242))

        path.move(to: point(218, 126))
        path.addCurve(to: point(236, 314), control1: point(211, 178), control2: point(216, 242))

        path.move(to: point(104, 314))
        path.addCurve(to: point(170, 334), control1: point(125, 328), control2: point(147, 334))
        path.addCurve(to: point(236, 314), control1: point(193, 334), control2: point(215, 328))
        return path
    }
}

struct TorsoCentreLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = min(rect.width / 340, rect.height / 430)
        let dx = rect.midX - 170 * scale
        let dy = rect.midY - 215 * scale
        path.move(to: CGPoint(x: dx + 170 * scale, y: dy + 102 * scale))
        path.addLine(to: CGPoint(x: dx + 170 * scale, y: dy + 346 * scale))
        return path
    }
}

/// The rounded box that keeps head, shoulders and waist in frame.
struct TorsoBoundsShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 340, rect.height / 430)
        let dx = rect.midX - 170 * scale
        let dy = rect.midY - 215 * scale
        return Path(roundedRect: CGRect(
            x: dx + 20 * scale, y: dy + 12 * scale,
            width: 300 * scale, height: 370 * scale
        ), cornerRadius: 54 * scale)
    }
}
