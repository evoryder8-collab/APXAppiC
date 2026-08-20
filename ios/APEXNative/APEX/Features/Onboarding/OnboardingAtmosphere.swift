import SwiftUI

/// The moving parts the first-run screens share.
///
/// Kept in one place so the welcome screen and the questionnaire feel like the
/// same product rather than two people's work, and so the expensive one is
/// written once and tuned once.

// MARK: - Atmosphere

/// Slow drifting colour, drawn rather than stacked.
///
/// Six blurred blobs as separate views would be six offscreen passes; one
/// Canvas is a single pass, which is the difference between a smooth entrance
/// and a stuttering one on an older phone.
struct AuroraField: View {
    let animated: Bool

    private struct Blob {
        let color: Color
        let radius: CGFloat
        let origin: CGPoint
        let drift: CGSize
        let period: Double
        let phase: Double
    }

    /* Drift is a quarter wider than it first was, and the periods are shorter,
       so the movement is legible without ever becoming a thing you watch. The
       radii breathe on their own cycle, which is what stops four circles on
       fixed paths from reading as four circles on fixed paths. */
    private let blobs: [Blob] = [
        Blob(color: APEXColor.violet, radius: 300, origin: CGPoint(x: 0.18, y: 0.16),
             drift: CGSize(width: 0.20, height: 0.13), period: 15, phase: 0),
        Blob(color: APEXColor.cyan, radius: 340, origin: CGPoint(x: 0.86, y: 0.24),
             drift: CGSize(width: -0.23, height: 0.16), period: 18, phase: 1.1),
        Blob(color: APEXColor.amber, radius: 260, origin: CGPoint(x: 0.74, y: 0.82),
             drift: CGSize(width: -0.15, height: -0.19), period: 21, phase: 2.3),
        Blob(color: APEXColor.violet, radius: 240, origin: CGPoint(x: 0.16, y: 0.88),
             drift: CGSize(width: 0.25, height: -0.11), period: 25, phase: 3.4),
        Blob(color: APEXColor.cyan, radius: 210, origin: CGPoint(x: 0.50, y: 0.50),
             drift: CGSize(width: 0.17, height: 0.21), period: 29, phase: 4.6),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.addFilter(.blur(radius: 60))
                for blob in blobs {
                    let angle = animated ? (time / blob.period + blob.phase) * .pi * 2 : blob.phase
                    let x = (blob.origin.x + blob.drift.width * CGFloat(sin(angle))) * size.width
                    let y = (blob.origin.y + blob.drift.height * CGFloat(cos(angle * 0.8))) * size.height
                    /* Each blob swells and shrinks slightly out of step with its
                       own travel, so the colour behind the screen feels like it
                       is alive rather than being panned across. */
                    let breath = animated ? 1 + 0.14 * CGFloat(sin(angle * 0.55 + blob.phase)) : 1
                    let radius = blob.radius * breath
                    let rect = CGRect(
                        x: x - radius, y: y - radius,
                        width: radius * 2, height: radius * 2
                    )
                    context.fill(
                        Circle().path(in: rect),
                        with: .radialGradient(
                            Gradient(colors: [blob.color.opacity(0.42), blob.color.opacity(0)]),
                            center: CGPoint(x: x, y: y),
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
            }
        }
        .background(APEXColor.canvas)
        .drawingGroup()
    }
}

/// A halo that breathes, behind the mark.
///
/// Two rings rather than one, expanding on slightly different cycles, because a
/// single circle pulsing on its own is a heartbeat monitor and this should read
/// as light.
struct BreathingGlow: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ring(scale: 1 + 0.10 * sin(elapsed / 3.1 * .pi * 2),
                     opacity: 0.30 + 0.10 * sin(elapsed / 3.1 * .pi * 2),
                     size: 250, colour: APEXColor.violet)
                ring(scale: 1 + 0.07 * sin(elapsed / 4.4 * .pi * 2 + 1.2),
                     opacity: 0.22 + 0.08 * sin(elapsed / 4.4 * .pi * 2 + 1.2),
                     size: 190, colour: APEXColor.cyan)
            }
        }
    }

    private func ring(scale: Double, opacity: Double, size: CGFloat, colour: Color) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [colour.opacity(opacity), .clear],
                    center: .center, startRadius: 2, endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 14)
            .scaleEffect(active ? scale : 1)
    }
}

/// A single diagonal pass of light, once.
struct ShimmerSweep: View {
    let active: Bool
    @State private var travelled = false

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, .white.opacity(0.95), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: proxy.size.width * 0.55)
            .rotationEffect(.degrees(18))
            .offset(x: travelled ? proxy.size.width * 1.25 : -proxy.size.width * 0.7)
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
        .onChange(of: active) { _, isActive in
            guard isActive, !travelled else { return }
            withAnimation(.easeInOut(duration: 1.5).delay(0.55)) { travelled = true }
        }
    }
}

/// Buttons that answer the finger.
struct PressShrink: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.22), value: configuration.isPressed)
    }
}

/// A slow vertical drift, out of phase per element.
///
/// The point is that no two things rise and fall together: a whole screen
/// moving as one block reads as a bug, while a few degrees of independence
/// reads as depth.
struct Floating: ViewModifier {
    let index: Int
    let active: Bool
    @State private var start = Date()

    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(start)
                let phase = Double(index) * 0.7
                let period = 4.6 + Double(index % 3) * 0.9
                content.offset(y: CGFloat(sin(elapsed / period * .pi * 2 + phase)) * 2.6)
            }
        } else {
            content
        }
    }
}

extension View {
    func floating(index: Int, active: Bool = true) -> some View {
        modifier(Floating(index: index, active: active))
    }

    /// The staggered entrance, so the screen assembles instead of appearing.
    func rise(_ appeared: Bool, delay: Double) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 22)
            .animation(.smooth(duration: 0.75).delay(delay), value: appeared)
    }
}
