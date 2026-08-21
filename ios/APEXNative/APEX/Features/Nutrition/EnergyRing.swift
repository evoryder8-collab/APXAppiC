import SwiftUI

/// The calorie ring.
///
/// Drawn entirely in one Canvas rather than as a stack of shapes. The first
/// version positioned a highlight over the arc's end using SwiftUI offsets
/// while the arc itself was a stroked shape, so the two lived in different
/// coordinate systems and the highlight never sat on the cap. Worse, the trim
/// and the offset animated independently, so they drifted apart while moving.
///
/// Here the cap and its highlight come from the same angle in the same draw,
/// so they cannot disagree. The whole ring is also one view instead of about
/// seventy, which is what keeps it cheap enough to animate.
struct EnergyRing<Center: View>: View {
    /// 0 to 1. Values past 1 are clamped, because a ring that laps itself
    /// stops meaning anything.
    let progress: Double
    var lineWidth: CGFloat = 15
    var accent: Color = APEXColor.amber
    var accentFar: Color = APEXColor.cyan
    @ViewBuilder var center: Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    private var target: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            RingCanvas(
                progress: drawn ? target : 0,
                lineWidth: lineWidth,
                accent: accent,
                accentFar: accentFar
            )
            center
        }
        .onAppear {
            guard !reduceMotion else { drawn = true; return }
            withAnimation(.spring(response: 1.15, dampingFraction: 0.82).delay(0.12)) {
                drawn = true
            }
        }
        .onChange(of: progress) { _, _ in
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { drawn = true }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One draw pass: groove, scale, arc and cap.
///
/// `Animatable` on the progress is what lets a Canvas animate at all. SwiftUI
/// interpolates the value and re-runs the draw, so every element is computed
/// from the same number on every frame and nothing can lag behind anything
/// else.
private struct RingCanvas: View, Animatable {
    var progress: Double
    let lineWidth: CGFloat
    let accent: Color
    let accentFar: Color

    /* Nonisolated because View is main-actor isolated while Animatable is not,
       and the animation system reads this off the main actor. Safe here: it is
       a stored Double on a value type, so there is no shared state to race. */
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// A hair of arc even at zero, so the ring never looks unloaded.
    private var shown: Double { max(progress, 0.012) }

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: false) { context, size in
            let side = min(size.width, size.height)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            /* One radius for everything: the stroke's centreline, the ticks and
               the cap all measure from here, which is the whole point of doing
               this in a single pass. */
            let radius = (side - lineWidth) / 2

            groove(in: &context, centre: centre, radius: radius)
            ticks(in: &context, centre: centre, radius: radius)

            let sweep = Angle.degrees(360 * shown)
            let path = arcPath(centre: centre, radius: radius, sweep: sweep)
            let shading = GraphicsContext.Shading.conicGradient(
                Gradient(colors: [accent, accentFar, accent]),
                center: centre,
                angle: .degrees(-90)
            )

            /* Bloom: the arc again, wider and blurred, under the line. One
               layer rather than the two the previous version used, because a
               blur is the expensive part of this draw and a second pass bought
               almost nothing visible. */
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: lineWidth * 0.7))
                layer.opacity = 0.5
                layer.stroke(
                    path,
                    with: shading,
                    style: StrokeStyle(lineWidth: lineWidth * 1.5, lineCap: .round)
                )
            }

            context.stroke(
                path,
                with: shading,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )

            /* A lighter line riding the centre of the band, so it reads as a
               curved surface rather than as tape. */
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.45), .white.opacity(0.08)]),
                    startPoint: CGPoint(x: centre.x, y: centre.y - radius),
                    endPoint: CGPoint(x: centre.x, y: centre.y + radius)
                ),
                style: StrokeStyle(lineWidth: lineWidth * 0.3, lineCap: .round)
            )

            cap(in: &context, centre: centre, radius: radius, sweep: sweep)
        }
        /* Deliberately no drawingGroup. Canvas already renders through Metal,
           so wrapping it only adds an offscreen buffer and a copy on every
           animated frame. It is a useful modifier for a deep stack of ordinary
           views, which is exactly what this stopped being. */
    }

    // MARK: - Parts

    private func arcPath(centre: CGPoint, radius: CGFloat, sweep: Angle) -> Path {
        Path { path in
            path.addArc(
                center: centre,
                radius: radius,
                startAngle: .degrees(-90),
                endAngle: .degrees(-90) + sweep,
                clockwise: false
            )
        }
    }

    /// The track, shaded like a channel cut into the card.
    private func groove(in context: inout GraphicsContext, centre: CGPoint, radius: CGFloat) {
        let circle = Path(ellipseIn: CGRect(
            x: centre.x - radius, y: centre.y - radius,
            width: radius * 2, height: radius * 2
        ))
        context.stroke(
            circle,
            with: .linearGradient(
                Gradient(colors: [APEXColor.ink.opacity(0.11), APEXColor.ink.opacity(0.03)]),
                startPoint: CGPoint(x: centre.x - radius, y: centre.y - radius),
                endPoint: CGPoint(x: centre.x + radius, y: centre.y + radius)
            ),
            lineWidth: lineWidth
        )
    }

    /// The scale. Ticks the arc has passed take the accent, so the ring gives a
    /// second reading of the same number for anyone who would rather not judge
    /// an angle.
    private func ticks(in context: inout GraphicsContext, centre: CGPoint, radius: CGFloat) {
        let passed = shown * 60
        for tick in 0..<60 {
            let major = tick % 5 == 0
            let lit = Double(tick) < passed
            let angle = Double(tick) / 60 * 2 * .pi - .pi / 2
            let length: CGFloat = lit ? (major ? 7 : 4.5) : (major ? 5 : 3)
            let width: CGFloat = major ? 1.4 : 1

            var mark = Path(roundedRect: CGRect(
                x: -width / 2, y: -length / 2, width: width, height: length
            ), cornerRadius: width / 2)
            mark = mark.applying(
                CGAffineTransform(rotationAngle: angle + .pi / 2)
                    .concatenating(CGAffineTransform(
                        translationX: centre.x + radius * cos(angle),
                        y: centre.y + radius * sin(angle)
                    ))
            )
            context.fill(
                mark,
                with: .color(lit
                             ? accent.opacity(major ? 0.9 : 0.5)
                             : APEXColor.ink.opacity(major ? 0.20 : 0.09))
            )
        }
    }

    /// The leading edge.
    ///
    /// Filled at exactly the point the arc's round cap already occupies, and
    /// shaded from a white core outward, so the bright point is the centre of
    /// the cap by construction rather than by adjustment.
    private func cap(in context: inout GraphicsContext, centre: CGPoint, radius: CGFloat, sweep: Angle) {
        let angle = -Double.pi / 2 + sweep.radians
        let point = CGPoint(
            x: centre.x + radius * cos(angle),
            y: centre.y + radius * sin(angle)
        )

        /* Halo first, so it sits under the cap. */
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: lineWidth * 0.55))
            layer.opacity = 0.75
            layer.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - lineWidth, y: point.y - lineWidth,
                    width: lineWidth * 2, height: lineWidth * 2
                )),
                with: .color(accent)
            )
        }

        let capRect = CGRect(
            x: point.x - lineWidth / 2, y: point.y - lineWidth / 2,
            width: lineWidth, height: lineWidth
        )
        context.fill(
            Path(ellipseIn: capRect),
            with: .radialGradient(
                Gradient(colors: [.white, .white.opacity(0.9), accent]),
                center: point,
                startRadius: 0,
                endRadius: lineWidth / 2
            )
        )
    }
}
