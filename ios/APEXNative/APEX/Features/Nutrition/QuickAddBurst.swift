/*
 * Quick-add confirmation. Tapping + logs the remembered portion without
 * opening anything, so the tap needs to be unmistakably felt and seen: the
 * button kicks, a ring snaps outward and a short burst of stardust throws
 * off it. Respects Reduce Motion, which falls back to a calm check.
 */
import SwiftUI

struct QuickAddBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: Int

    private struct Mote: Identifiable {
        let id: Int
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let delay: Double
    }

    @State private var fired = false

    private var motes: [Mote] {
        (0..<10).map { index in
            let jitter = Double((index * 37) % 17) / 17
            return Mote(
                id: index,
                angle: (Double(index) / 10) * 2 * .pi + jitter * 0.35,
                distance: 26 + CGFloat(jitter) * 16,
                size: 3.5 + CGFloat((index % 3)) * 1.4,
                delay: jitter * 0.06
            )
        }
    }

    var body: some View {
        ZStack {
            if reduceMotion {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(APEXColor.amberDeep)
                    .opacity(fired ? 1 : 0)
            } else {
                Circle()
                    .stroke(APEXColor.amber.opacity(0.55), lineWidth: 2.5)
                    .frame(width: 44, height: 44)
                    .scaleEffect(fired ? 1.65 : 0.55)
                    .opacity(fired ? 0 : 0.9)

                ForEach(motes) { mote in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [APEXColor.amber, APEXColor.amberDeep.opacity(0.75)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: mote.size, height: mote.size)
                        .offset(
                            x: fired ? cos(mote.angle) * mote.distance : 0,
                            y: fired ? sin(mote.angle) * mote.distance : 0
                        )
                        .opacity(fired ? 0 : 1)
                        .scaleEffect(fired ? 0.4 : 1)
                        .animation(
                            .easeOut(duration: 0.62).delay(mote.delay),
                            value: fired
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            guard trigger > 0 else { return }
            fired = false
            withAnimation(.easeOut(duration: 0.55)) { fired = true }
        }
    }
}

/* The row itself kicks so the feedback reads even mid-scroll. */
struct QuickAddKick: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: Int
    @State private var kicking = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(kicking && !reduceMotion ? 1.14 : 1)
            .rotationEffect(.degrees(kicking && !reduceMotion ? 8 : 0))
            .animation(.spring(response: 0.26, dampingFraction: 0.42), value: kicking)
            .onChange(of: trigger) { _, _ in
                guard trigger > 0 else { return }
                kicking = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(190))
                    kicking = false
                }
            }
    }
}

extension View {
    func quickAddKick(trigger: Int) -> some View {
        modifier(QuickAddKick(trigger: trigger))
    }
}
