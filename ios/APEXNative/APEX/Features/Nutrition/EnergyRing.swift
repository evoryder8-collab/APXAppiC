import SwiftUI

/// The calorie ring, drawn as a charged instrument rather than a donut.
///
/// The number in the middle is the thing people actually read, so everything
/// here works to make the arc support it: a bloom under the stroke so the line
/// emits rather than merely being coloured, a bright head at the leading edge
/// so the eye lands on where the day has got to, and ticks on the empty track
/// so the remaining distance is legible as a quantity instead of a gap.
struct EnergyRing<Center: View>: View {
    /// 0 to 1. Values past 1 are clamped, because a ring that laps itself
    /// stops meaning anything.
    let progress: Double
    var lineWidth: CGFloat = 15
    var accent: [Color] = [APEXColor.amber, APEXColor.cyan, APEXColor.amber]
    @ViewBuilder var center: Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    private var clamped: Double { min(max(progress, 0), 1) }

    /* A hair of arc even at zero, so the ring never looks broken or unloaded. */
    private var shown: Double { drawn ? max(clamped, 0.012) : 0.012 }

    private var gradient: AngularGradient {
        AngularGradient(colors: accent, center: .center)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = (side - lineWidth) / 2

            ZStack {
                track(side: side)

                /* The bloom: the same arc, thicker and blurred, sitting under
                   the stroke. This is what makes the line read as emitting
                   light rather than as a coloured band.

                   Rotated as a view rather than as a shape, so the angular
                   gradient turns with it. Rotating only the shape left the
                   gradient fixed to the circle, and a short arc then began
                   halfway through the colour ramp, which is why the first
                   degrees came out muddy instead of amber. */
                arc
                    .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth * 1.5, lineCap: .round))
                    .blur(radius: lineWidth * 0.75)
                    .opacity(0.55)
                    .rotationEffect(.degrees(-90))

                arc
                    .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                /* A pulse travelling the filled length, so the ring feels
                   alive without anything moving position. Slow, and only over
                   the part that is filled, so it reads as charge rather than
                   as a loading spinner. */
                if !reduceMotion, clamped > 0.04 {
                    TravellingSpark(progress: shown, lineWidth: lineWidth, colour: accent.first ?? .white)
                }

                head(radius: radius)

                center
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            /* Drawn on arrival rather than snapping into place: the arc is the
               summary of the day, and watching it fill is what tells you it
               was measured rather than printed. */
            guard !reduceMotion else { drawn = true; return }
            withAnimation(.spring(response: 1.1, dampingFraction: 0.82).delay(0.1)) {
                drawn = true
            }
        }
        .onChange(of: progress) { _, _ in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { drawn = true }
        }
        .accessibilityElement(children: .combine)
    }

    private var arc: some Shape {
        Circle().trim(from: 0, to: shown)
    }

    /// The unfilled part, ticked so the distance left reads as a quantity.
    private func track(side: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(APEXColor.ink.opacity(0.06), lineWidth: lineWidth)

            ForEach(0..<60, id: \.self) { tick in
                Capsule()
                    .fill(APEXColor.ink.opacity(tick % 5 == 0 ? 0.16 : 0.07))
                    .frame(width: 1, height: tick % 5 == 0 ? 5 : 3)
                    .offset(y: -(side - lineWidth) / 2)
                    .rotationEffect(.degrees(Double(tick) / 60 * 360))
            }
        }
    }

    /// The bright point at the leading edge.
    private func head(radius: CGFloat) -> some View {
        let angle = Angle.degrees(shown * 360 - 90)
        return ZStack {
            Circle()
                .fill(.white)
                .frame(width: lineWidth * 0.52, height: lineWidth * 0.52)
            Circle()
                .fill(accent.first ?? .white)
                .frame(width: lineWidth * 1.6, height: lineWidth * 1.6)
                .blur(radius: lineWidth * 0.5)
                .opacity(0.75)
        }
        .offset(
            x: radius * cos(CGFloat(angle.radians)),
            y: radius * sin(CGFloat(angle.radians))
        )
        .animation(.spring(response: 1.1, dampingFraction: 0.82), value: shown)
    }
}

/// A soft highlight that runs around the filled arc and starts again.
private struct TravellingSpark: View {
    let progress: Double
    let lineWidth: CGFloat
    let colour: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            /* Most of the cycle is spent dark, so this catches the eye now and
               then rather than shimmering constantly. */
            let cycle = (elapsed / 3.4).truncatingRemainder(dividingBy: 1)
            let head = cycle * progress
            let tail = max(0, head - 0.10)

            Circle()
                .trim(from: tail, to: head)
                .stroke(
                    LinearGradient(
                        colors: [colour.opacity(0), .white.opacity(0.85), colour.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth * 0.7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .blur(radius: 2)
                .blendMode(.plusLighter)
                .opacity(cycle > 0.82 ? (1 - cycle) / 0.18 : 1)
        }
        .allowsHitTesting(false)
    }
}
