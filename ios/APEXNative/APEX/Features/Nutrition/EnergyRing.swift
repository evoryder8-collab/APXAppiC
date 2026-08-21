import SwiftUI

/// The calorie ring, drawn as a lit instrument.
///
/// The number in the middle is what people read, so everything here works to
/// support it: a recessed groove for the track so the ring has a floor, a
/// stroke that emits rather than merely being coloured, and a head at the
/// leading edge that sits above the arc with its own shadow, so the eye lands
/// on where the day has actually reached.
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

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            /* The stroke straddles the path, so the shapes are inset by half a
               line width. Without this the arc overflows its frame and every
               position computed from the frame, the head and the ticks alike,
               lands half a line width inside the line it is meant to sit on.
               That is what made the head look dropped on rather than attached. */
            let inset = lineWidth / 2
            let radius = (side - lineWidth) / 2

            ZStack {
                centreWash(side: side)
                groove(inset: inset)
                ticks(radius: radius)
                emission(inset: inset)
                stroke(inset: inset)
                if !reduceMotion, clamped > 0.05 {
                    TravellingSpark(progress: shown, lineWidth: lineWidth, inset: inset)
                }
                head(radius: radius)
                center
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            guard !reduceMotion else { drawn = true; return }
            withAnimation(.spring(response: 1.15, dampingFraction: 0.8).delay(0.12)) {
                drawn = true
            }
        }
        .onChange(of: progress) { _, _ in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { drawn = true }
        }
        .accessibilityElement(children: .combine)
    }

    private var gradient: AngularGradient {
        AngularGradient(colors: accent, center: .center)
    }

    private var arc: some Shape {
        Circle().trim(from: 0, to: shown)
    }

    /// A faint tint in the middle, so the centre is not a hole. Warms as the
    /// day fills, which is the one place colour is allowed to carry meaning.
    private func centreWash(side: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        (accent.first ?? .clear).opacity(0.10 * shown + 0.02),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: side * 0.42
                )
            )
    }

    /// The track, lit from the top left so it reads as a groove cut into the
    /// card rather than a grey ring painted on it.
    private func groove(inset: CGFloat) -> some View {
        ZStack {
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [APEXColor.ink.opacity(0.10), APEXColor.ink.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: lineWidth
                )
            /* A hairline highlight on the lower edge: the far wall of a groove
               catches light where the near wall shades. */
            Circle()
                .strokeBorder(.white.opacity(0.55), lineWidth: 0.8)
                .padding(inset - 0.4)
                .blur(radius: 0.5)
                .mask {
                    LinearGradient(
                        colors: [.clear, .white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
    }

    /// The bloom under the stroke: what makes the line emit.
    private func emission(inset: CGFloat) -> some View {
        ZStack {
            arc
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth * 1.9, lineCap: .round))
                .padding(inset)
                .blur(radius: lineWidth * 0.95)
                .opacity(0.45)
            arc
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth * 1.15, lineCap: .round))
                .padding(inset)
                .blur(radius: lineWidth * 0.35)
                .opacity(0.55)
        }
        .rotationEffect(.degrees(-90))
    }

    /// The line itself, with a brighter core so it has a top surface.
    private func stroke(inset: CGFloat) -> some View {
        ZStack {
            arc
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .padding(inset)

            /* A narrower, lighter line riding the centre. A single flat stroke
               reads as tape; this gives the band a curved top. */
            arc
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: lineWidth * 0.34, lineCap: .round)
                )
                .padding(inset)
                .blendMode(.plusLighter)
        }
        .rotationEffect(.degrees(-90))
    }

    /// Ticks on the track, at the same radius as the stroke centreline.
    ///
    /// The ones the arc has passed light up. A gauge whose scale ignores its
    /// own needle is a picture of an instrument; one whose scale responds is an
    /// instrument, and it gives the ring a second, quieter reading of the same
    /// number for anyone who does not want to judge an angle.
    private func ticks(radius: CGFloat) -> some View {
        let passed = shown * 60
        return ForEach(0..<60, id: \.self) { tick in
            let isMajor = tick % 5 == 0
            let lit = Double(tick) < passed
            Capsule()
                .fill(lit
                      ? (accent.first ?? APEXColor.amber).opacity(isMajor ? 0.9 : 0.5)
                      : APEXColor.ink.opacity(isMajor ? 0.20 : 0.09))
                .frame(
                    width: isMajor ? 1.4 : 1,
                    height: lit ? (isMajor ? 7 : 4.5) : (isMajor ? 5 : 3)
                )
                .offset(y: -radius)
                .rotationEffect(.degrees(Double(tick) / 60 * 360))
                .animation(
                    .spring(response: 0.9, dampingFraction: 0.8)
                        /* Lit in sequence rather than all at once, so the scale
                           fills the way the arc draws. */
                        .delay(Double(tick) / 60 * 0.5),
                    value: shown
                )
        }
    }

    /// The leading edge: a lit cap sitting above the arc.
    private func head(radius: CGFloat) -> some View {
        let angle = Angle.degrees(shown * 360 - 90)
        let colour = accent.first ?? .white
        return ZStack {
            /* Halo first, widest and softest. */
            Circle()
                .fill(colour)
                .frame(width: lineWidth * 2.4, height: lineWidth * 2.4)
                .blur(radius: lineWidth * 0.8)
                .opacity(0.7)

            /* A shadow directly under the cap. This is the detail that makes
               the head sit on the ring rather than float beside it, and it is
               what separates head from tail once the arc closes on itself. */
            Circle()
                .fill(.black.opacity(0.22))
                .frame(width: lineWidth * 0.96, height: lineWidth * 0.96)
                .blur(radius: 2.5)
                .offset(y: 1.5)

            Circle()
                .fill(colour)
                .frame(width: lineWidth * 0.94, height: lineWidth * 0.94)

            /* The specular point, offset up and left like a lit sphere. */
            Circle()
                .fill(.white)
                .frame(width: lineWidth * 0.42, height: lineWidth * 0.42)
                .offset(x: -lineWidth * 0.1, y: -lineWidth * 0.1)
                .blur(radius: 0.6)
        }
        .offset(
            x: radius * cos(CGFloat(angle.radians)),
            y: radius * sin(CGFloat(angle.radians))
        )
        .animation(.spring(response: 1.15, dampingFraction: 0.8), value: shown)
    }
}

/// A highlight that runs the filled length and starts again.
private struct TravellingSpark: View {
    let progress: Double
    let lineWidth: CGFloat
    let inset: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            /* Most of the cycle is spent dark, so this catches the eye now and
               then rather than shimmering continuously. */
            let cycle = (elapsed / 3.6).truncatingRemainder(dividingBy: 1)
            let head = cycle * progress
            let tail = max(0, head - 0.12)

            Circle()
                .trim(from: tail, to: head)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0), .white.opacity(0.9), .white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth * 0.62, lineCap: .round)
                )
                .padding(inset)
                .rotationEffect(.degrees(-90))
                .blur(radius: 2.5)
                .blendMode(.plusLighter)
                .opacity(cycle > 0.80 ? (1 - cycle) / 0.20 : 1)
        }
        .allowsHitTesting(false)
    }
}
