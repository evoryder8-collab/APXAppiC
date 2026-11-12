import SwiftUI

/// The supplements page: a glass capsule that fills as the day's supplements are taken, then the checklist.
struct WatchSupplementChecklistView: View {
    let animates: Bool
    let motionScale: Double

    @EnvironmentObject private var hydration: WatchHydrationStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var timelineAnchor = Date()

    private static let capsuleBands = [
        WatchVesselBand(red: 1.0, green: 0.42, blue: 0.2, location: 0),
        WatchVesselBand(red: 1.0, green: 0.72, blue: 0.26, location: 0.6),
        WatchVesselBand(red: 1.0, green: 0.9, blue: 0.55, location: 1),
    ]

    var body: some View {
        if let ownerID = hydration.supplements.snapshot?.ownerID {
            TimelineView(.explicit([timelineAnchor, Self.midnight(after: timelineAnchor)])) { timeline in
                let day = timeline.date.apexDateKey
                let items = hydration.supplements.visibleItems
                let takenCount = items.count { hydration.supplements.isTaken(itemID: $0.id, day: day) }
                let allTaken = !items.isEmpty && takenCount == items.count

                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 4) {
                            WatchVessel(
                                shape: .capsule,
                                progress: items.isEmpty ? 0 : Double(takenCount) / Double(items.count),
                                bands: Self.capsuleBands,
                                animates: animates,
                                motionScale: motionScale
                            )
                            .frame(width: 64, height: 76)

                            VStack(alignment: .leading, spacing: 0) {
                                Text("Supplements", tableName: "WatchSupplements")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text("\(takenCount) of \(items.count)", tableName: "WatchSupplements")
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                Text(allTaken ? "All taken today" : "Taken today", tableName: "WatchSupplements")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(allTaken ? WatchTint.gold : .secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.trailing, 10)
                            .animation(reduceMotion ? nil : .snappy, value: takenCount)
                            .accessibilityElement(children: .combine)
                        }

                        ForEach(items) { item in
                            let taken = hydration.supplements.isTaken(itemID: item.id, day: day)
                            Button {
                                hydration.toggleSupplement(item.id, ownerID: ownerID)
                            } label: {
                                WatchSupplementRow(item: item, isSelected: taken)
                            }
                            .buttonStyle(WatchGlassButtonStyle(tint: WatchTint.gold, cornerRadius: 18, isLit: taken))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(verbatim: item.accessibilityDescription))
                            .accessibilityValue(Text(
                                taken ? "Taken today" : "Not taken today", tableName: "WatchSupplements"
                            ))
                            .accessibilityHint(Text(
                                taken ? "Mark as not taken" : "Mark as taken", tableName: "WatchSupplements"
                            ))
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: day) { _, _ in
                    timelineAnchor = timeline.date
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { timelineAnchor = .now }
            }
        }
    }

    private static func midnight(after date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))
            ?? date.addingTimeInterval(86_400)
    }
}

struct WatchSupplementSettingsView: View {
    @EnvironmentObject private var hydration: WatchHydrationStore
    @State private var showsSupplements = true
    @State private var settingsOwnerID: UUID?

    var body: some View {
        Form {
            if let snapshot = hydration.supplements.snapshot {
                Section {
                    Toggle(isOn: $showsSupplements) {
                        Text("Show supplements", tableName: "WatchSupplements")
                    }
                    Text("Choose which supplements appear on this Watch.", tableName: "WatchSupplements")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if showsSupplements {
                    Section {
                        ForEach(snapshot.items) { item in
                            let isShown = !hydration.supplements.preferences.hiddenIDs.contains(item.id)
                            Button {
                                hydration.setSupplementVisibility(
                                    item.id, isVisible: !isShown, ownerID: snapshot.ownerID
                                )
                            } label: {
                                WatchSupplementRow(item: item, isSelected: isShown)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(verbatim: item.accessibilityDescription))
                            .accessibilityValue(Text(
                                isShown ? "Shown on Watch" : "Hidden on Watch", tableName: "WatchSupplements"
                            ))
                        }
                    } header: {
                        Text("Choose supplements", tableName: "WatchSupplements")
                    }
                }

                if snapshot.items.isEmpty {
                    Text("Add supplements in FITR MAX on iPhone.", tableName: "WatchSupplements")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Open FITR MAX on iPhone to sync your supplements.", tableName: "WatchSupplements")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text("Supplements", tableName: "WatchSupplements"))
        .task(id: hydration.supplements.snapshot?.ownerID) {
            settingsOwnerID = hydration.supplements.snapshot?.ownerID
            showsSupplements = hydration.supplements.preferences.isVisible
        }
        .onChange(of: showsSupplements) { _, isVisible in
            guard let settingsOwnerID else { return }
            hydration.setSupplementsVisible(isVisible, ownerID: settingsOwnerID)
        }
    }
}

private struct WatchSupplementRow: View {
    let item: WatchSupplementItem
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(isSelected ? 0 : 0.3), lineWidth: 1.5)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [WatchTint.gold, WatchTint.ember], startPoint: .top, endPoint: .bottom
                        )
                    )
                    .scaleEffect(isSelected ? 1 : 0.2)
                    .opacity(isSelected ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.8))
                    .scaleEffect(isSelected ? 1 : 0.2)
                    .opacity(isSelected ? 1 : 0)
            }
            .frame(width: 26, height: 26)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.55), value: isSelected)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if !item.dose.isEmpty {
                    Text(verbatim: item.dose)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 48)
        .contentShape(.rect)
    }
}

private extension WatchSupplementItem {
    var accessibilityDescription: String {
        dose.isEmpty ? name : "\(name), \(dose)"
    }
}
