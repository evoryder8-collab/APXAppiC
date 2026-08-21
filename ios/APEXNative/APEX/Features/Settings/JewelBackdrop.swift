import SwiftUI

/// The ground the premium sheet stands on.
///
/// The rest of the app is bright glass, so this deliberately is not. A person
/// arrives here by tapping a diamond, and the sheet should feel like somewhere
/// they have gone rather than another card in the same stack. Dark, with light
/// moving through it the way it moves through a cut stone.
struct JewelBackdrop: View {
    var animated: Bool = true

    /* Deep indigo rather than black. Pure black under a translucent panel goes
       flat and grey; a hue underneath keeps the panels feeling like glass with
       something behind them. */
    private static let deep = Color(red: 0.043, green: 0.047, blue: 0.106)
    private static let near = Color(red: 0.086, green: 0.075, blue: 0.180)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Self.near, Self.deep],
                startPoint: .top,
                endPoint: .bottom
            )

            TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated)) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    context.addFilter(.blur(radius: 70))
                    /* Three beams at different speeds. Refraction is what a
                       diamond does to light, so the colour arrives in bands
                       that cross rather than as a single wash. */
                    for beam in Self.beams {
                        let phase = animated
                            ? (elapsed / beam.period + beam.offset) * .pi * 2
                            : beam.offset
                        let x = (beam.origin.x + 0.30 * CGFloat(sin(phase))) * size.width
                        let y = (beam.origin.y + 0.22 * CGFloat(cos(phase * 0.7))) * size.height
                        let radius = size.width * beam.spread
                        context.fill(
                            Ellipse().path(in: CGRect(
                                x: x - radius, y: y - radius * 0.55,
                                width: radius * 2, height: radius * 1.1
                            )),
                            with: .radialGradient(
                                Gradient(colors: [beam.colour.opacity(0.55), beam.colour.opacity(0)]),
                                center: CGPoint(x: x, y: y),
                                startRadius: 0,
                                endRadius: radius
                            )
                        )
                    }
                }
                .blendMode(.plusLighter)
            }

            /* A fine grain over the whole thing. Large flat gradients band on
               OLED, and a little noise is what stops the sky looking stepped. */
            Canvas { context, size in
                for _ in 0..<1_400 {
                    let point = CGPoint(
                        x: .random(in: 0...size.width),
                        y: .random(in: 0...size.height)
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(origin: point, size: CGSize(width: 1, height: 1))),
                        with: .color(.white.opacity(.random(in: 0.01...0.05)))
                    )
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private struct Beam {
        let colour: Color
        let origin: CGPoint
        let spread: CGFloat
        let period: Double
        let offset: Double
    }

    private static let beams: [Beam] = [
        Beam(colour: APEXColor.violet, origin: CGPoint(x: 0.22, y: 0.16), spread: 0.85, period: 17, offset: 0),
        Beam(colour: APEXColor.cyan, origin: CGPoint(x: 0.80, y: 0.34), spread: 0.75, period: 21, offset: 1.4),
        Beam(colour: APEXColor.amber, origin: CGPoint(x: 0.55, y: 0.86), spread: 0.65, period: 26, offset: 2.9),
    ]
}

/// A panel on the jewel ground: translucent, with a lit edge.
struct FacetPanel<Content: View>: View {
    var radius: CGFloat = 26
    var padding: CGFloat = 19
    /// The recommended tier gets a brighter edge, so the eye is told where to
    /// look without a badge shouting "most popular".
    var lifted: Bool = false
    /// Chosen by a tap, as opposed to merely recommended. Gets a ring the
    /// recommendation does not, so the two states cannot be confused.
    var selected: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                /* A dark base first, then the sheen. Lightening alone left the
                   text contrast depending on where a beam happened to be, and
                   the beams move, so a line that was readable a second ago
                   stopped being readable. The base holds the floor and the
                   sheen supplies the glass. */
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.black.opacity(0.34))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(.white.opacity(lifted ? 0.10 : 0.055))
                    }
            }
            .overlay {
                /* The edge catches light along one diagonal, the way a facet
                   does. A uniform border would read as a box. */
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: lifted
                                ? [.white.opacity(0.65), APEXColor.cyan.opacity(0.35), .white.opacity(0.10)]
                                : [.white.opacity(0.28), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: lifted ? 1.2 : 0.8
                    )
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(APEXColor.cyan, lineWidth: 1.6)
                        .shadow(color: APEXColor.cyan.opacity(0.7), radius: 10)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: lifted ? 26 : 16, y: lifted ? 12 : 8)
    }
}
