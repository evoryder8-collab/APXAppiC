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

    private let blobs: [Blob] = [
        Blob(color: APEXColor.violet, radius: 300, origin: CGPoint(x: 0.18, y: 0.16),
             drift: CGSize(width: 0.16, height: 0.10), period: 19, phase: 0),
        Blob(color: APEXColor.cyan, radius: 340, origin: CGPoint(x: 0.86, y: 0.24),
             drift: CGSize(width: -0.18, height: 0.13), period: 23, phase: 1.1),
        Blob(color: APEXColor.amber, radius: 260, origin: CGPoint(x: 0.74, y: 0.82),
             drift: CGSize(width: -0.12, height: -0.15), period: 27, phase: 2.3),
        Blob(color: APEXColor.violet, radius: 240, origin: CGPoint(x: 0.16, y: 0.88),
             drift: CGSize(width: 0.20, height: -0.09), period: 31, phase: 3.4),
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
                    let rect = CGRect(
                        x: x - blob.radius, y: y - blob.radius,
                        width: blob.radius * 2, height: blob.radius * 2
                    )
                    context.fill(
                        Circle().path(in: rect),
                        with: .radialGradient(
                            Gradient(colors: [blob.color.opacity(0.34), blob.color.opacity(0)]),
                            center: CGPoint(x: x, y: y),
                            startRadius: 0,
                            endRadius: blob.radius
                        )
                    )
                }
            }
        }
        .background(APEXColor.canvas)
        .drawingGroup()
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

extension View {
    /// The staggered entrance, so the screen assembles instead of appearing.
    func rise(_ appeared: Bool, delay: Double) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 22)
            .animation(.smooth(duration: 0.75).delay(delay), value: appeared)
    }
}
