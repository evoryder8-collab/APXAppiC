import SwiftUI
import WatchKit

struct WatchHydrationAmountControl: View {
  @Binding var milliliters: Int
  let hapticsEnabled: Bool
  let onAddWater: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isEnabled) private var isEnabled
  @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 32.0
  @GestureState private var gestureIsActive = false
  @State private var scrub: WatchHydrationAmountAdjustment?
  @State private var lastHapticTime = -Double.infinity
  @State private var amountFrame = CGRect.zero

  var body: some View {
    ScrollView {
      VStack(spacing: 6) {
        VStack(spacing: 3) {
          HStack(spacing: 4) {
            amountButton(increasing: false)
            VStack(spacing: 0) {
              Text(milliliters, format: .number.grouping(.never))
                .font(.system(size: amountSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(milliliters)))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
              Text(verbatim: "mL")
                .font(.caption2.bold())
                .foregroundStyle(.cyan)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Water amount", tableName: "WatchAmount"))
            .accessibilityValue(Text("\(milliliters) mL", tableName: "WatchAmount"))
            .accessibilityHint(Text("Adjusts in steps of 10 mL.", tableName: "WatchAmount"))
            .accessibilityAdjustableAction { direction in
              switch direction {
              case .increment: changeAmount(by: 10)
              case .decrement: changeAmount(by: -10)
              @unknown default: break
              }
            }
            .accessibilityIdentifier("watch.water.custom.amount")
            amountButton(increasing: true)
          }
          HStack(alignment: .center, spacing: 5) {
            ForEach(0..<11) { tick in
              Capsule()
                .fill(tick == 5 ? Color.cyan : Color.white.opacity(0.20))
                .frame(width: tick == 5 ? 3 : 2, height: tick == 5 ? 8 : (tick % 2 == 0 ? 6 : 4))
            }
          }
          .accessibilityHidden(true)

          Text("Swipe to adjust", tableName: "WatchAmount")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
          LinearGradient(
            colors: [.cyan.opacity(0.20), .indigo.opacity(0.15)], startPoint: .topLeading,
            endPoint: .bottomTrailing),
          in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 22)
            .stroke(.cyan.opacity(gestureIsActive ? 0.7 : 0.25), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onGeometryChange(for: CGRect.self) { proxy in
          proxy.frame(in: .named("watch.amount.scrub"))
        } action: { frame in
          amountFrame = frame
        }

        Button(action: onAddWater) {
          Text("Add \(milliliters) mL", tableName: "WatchAmount")
            .font(.headline)
            .monospacedDigit()
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.cyan)
        .accessibilityIdentifier("watch.water.custom.add")
      }
      .padding(.horizontal, 4)
      .padding(.bottom, 4)
    }
    .coordinateSpace(name: "watch.amount.scrub")
    // Keep the scrub on the scroll container. Axis locking prevents vertical
    // movement from changing the amount, and all essential controls fit together.
    .simultaneousGesture(
      DragGesture(minimumDistance: 8, coordinateSpace: .named("watch.amount.scrub"))
        .updating($gestureIsActive) { _, active, _ in active = true }
        .onChanged(adjustFromDrag)
        .onEnded { _ in scrub = nil }
    )
    .onChange(of: gestureIsActive) { _, active in
      if !active { scrub = nil }
    }
  }

  private func amountButton(increasing: Bool) -> some View {
    Button(action: { changeAmount(by: increasing ? 10 : -10) }) {
      Image(systemName: increasing ? "plus" : "minus")
        .font(.headline)
        .foregroundStyle(.cyan)
        .frame(width: 44, height: 44)
        .background(.cyan.opacity(0.10), in: Circle())
    }
    .buttonStyle(.plain)
    .disabled(increasing
      ? milliliters >= WatchHydrationAmountAdjustment.range.upperBound
      : milliliters <= WatchHydrationAmountAdjustment.range.lowerBound)
    .accessibilityLabel(Text(increasing ? LocalizedStringKey("Increase amount") : LocalizedStringKey("Decrease amount"), tableName: "WatchAmount"))
    .accessibilityIdentifier(increasing ? "watch.water.custom.increase" : "watch.water.custom.decrease")
  }

  private func adjustFromDrag(_ value: DragGesture.Value) {
    guard isEnabled, amountFrame.contains(value.startLocation) else { return }
    var adjustment = scrub ?? WatchHydrationAmountAdjustment()
    let next = adjustment.update(
      current: milliliters,
      horizontal: Double(value.translation.width),
      vertical: Double(value.translation.height)
    )
    scrub = adjustment
    setAmount(next)
  }

  private func changeAmount(by delta: Int) {
    guard isEnabled else { return }
    setAmount(WatchHydrationAmountAdjustment.clamped(milliliters + delta))
  }

  private func setAmount(_ amount: Int) {
    guard amount != milliliters else { return }
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
      milliliters = amount
    }
    let now = Date.timeIntervalSinceReferenceDate
    if hapticsEnabled && now - lastHapticTime >= 0.08 {
      WKInterfaceDevice.current().play(.click)
      lastHapticTime = now
    }
  }
}
