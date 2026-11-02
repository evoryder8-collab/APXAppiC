import SwiftUI

struct WatchSupplementChecklistView: View {
    @EnvironmentObject private var hydration: WatchHydrationStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var timelineAnchor = Date()

    var body: some View {
        if !hydration.supplements.visibleItems.isEmpty,
           let ownerID = hydration.supplements.snapshot?.ownerID {
            TimelineView(.explicit([timelineAnchor, Self.midnight(after: timelineAnchor)])) { timeline in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Supplements today", tableName: "WatchSupplements")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)

                    ForEach(hydration.supplements.visibleItems) { item in
                        let taken = hydration.supplements.isTaken(
                            itemID: item.id, day: timeline.date.apexDateKey
                        )
                        Button {
                            hydration.toggleSupplement(item.id, ownerID: ownerID)
                        } label: {
                            WatchSupplementRow(item: item, isSelected: taken)
                        }
                        .buttonStyle(.plain)
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
                .onChange(of: timeline.date.apexDateKey) { _, _ in
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

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.cyan : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name)
                    .font(.footnote)
                    .fontWeight(.semibold)
                if !item.dose.isEmpty {
                    Text(verbatim: item.dose)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(.rect)
    }
}

private extension WatchSupplementItem {
    var accessibilityDescription: String {
        dose.isEmpty ? name : "\(name), \(dose)"
    }
}
