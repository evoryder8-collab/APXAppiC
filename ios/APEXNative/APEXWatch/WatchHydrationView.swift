import SwiftUI

struct WatchHydrationView: View {
    @EnvironmentObject private var hydration: WatchHydrationStore

    private let aqua = Color(red: 0.08, green: 0.80, blue: 0.92)

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("APEX WATER")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.secondary)

                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.10), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: hydration.progress)
                        .stroke(
                            AngularGradient(colors: [.purple, aqua, .mint], center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.snappy, value: hydration.progress)

                    VStack(spacing: 0) {
                        Text(hydration.liters.formatted(.number.precision(.fractionLength(2))))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("of 2.75 L")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 116, height: 116)

                HStack(spacing: 7) {
                    quickAdd(250)
                    quickAdd(300)
                    quickAdd(500)
                }

                if let message = hydration.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(aqua)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 6)
        }
        .task {
            await hydration.start()
        }
    }

    private func quickAdd(_ milliliters: Int) -> some View {
        Button {
            Task { await hydration.add(milliliters: Double(milliliters)) }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "drop.fill")
                    .font(.caption2)
                Text("\(milliliters)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(aqua.opacity(0.70))
        .disabled(hydration.isSaving)
        .accessibilityLabel("Add \(milliliters) milliliters of water")
    }
}
