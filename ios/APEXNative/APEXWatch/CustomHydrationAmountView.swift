import SwiftUI
import WatchKit

struct CustomHydrationAmountView: View {
  @EnvironmentObject private var hydration: WatchHydrationStore
  @Environment(\.dismiss) private var dismiss
  @State private var milliliters = 350

  var body: some View {
    WatchHydrationAmountControl(
      milliliters: $milliliters,
      hapticsEnabled: hydration.preferences.confirmationHaptics,
      onAddWater: addWater
    )
    .disabled(hydration.isSaving)
    .navigationTitle(Text("Custom water", tableName: "WatchAmount"))
  }

  private func addWater() {
    let amount = Double(milliliters)
    Task {
      await hydration.add(milliliters: amount)
      if hydration.isAuthorized { dismiss() }
    }
  }
}
