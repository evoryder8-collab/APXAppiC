import MapKit
import SwiftUI

struct OrbitLibraryView: View {
    @Environment(AppSession.self) private var session
    @State private var editingRoute: OrbitRouteRecord?
    @State private var language = LanguageState.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 11) {
                    NavigationLink {
                        RunningShoesView()
                    } label: {
                        libraryAction("shoe.2.fill", "Shoes")
                    }
                    NavigationLink {
                        ManualRouteEditorView()
                    } label: {
                        libraryAction("pencil.and.outline", "Draw route")
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 12) {
                    Text(language.text("Recent runs"))
                        .font(APEXFont.display(26))
                    if session.data.orbitRuns.isEmpty {
                        empty("figure.run.circle", "No recorded runs yet", "A completed Orbit run will appear here with its private debrief.")
                    }
                    ForEach(session.data.orbitRuns) { run in
                        NavigationLink {
                            HistoricalRunDebrief(run: run)
                        } label: {
                            RunHistoryRow(run: run)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(language.text("Saved routes"))
                        .font(APEXFont.display(26))
                    if session.data.orbitRoutes.isEmpty {
                        empty("map", "No saved routes yet", "Generate, draw or import a route to build a private library.")
                    }
                    ForEach(session.data.orbitRoutes) { route in
                        RouteLibraryCard(route: route, editingRoute: $editingRoute)
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .navigationTitle(language.text("Orbit Library"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingRoute) { route in
            RouteEditorSheet(route: route)
                .environment(session)
        }
    }

    private func libraryAction(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(APEXColor.cyan.gradient, in: Circle())
            Text(language.text(title))
                .font(APEXFont.body(11, weight: .bold))
                .foregroundStyle(APEXColor.ink)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25))
    }

    private func empty(_ icon: String, _ title: String, _ body: String) -> some View {
        GlassCard(radius: 26, padding: 18) {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.system(size: 32)).foregroundStyle(APEXColor.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text(title)).font(APEXFont.display(17))
                    Text(language.text(body)).font(APEXFont.body(10, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
                }
            }
        }
    }
}

private struct RouteLibraryCard: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let route: OrbitRouteRecord
    @Binding var editingRoute: OrbitRouteRecord?
    @State private var exportURL: URL?
    @State private var showSegmentEditor = false

    var body: some View {
        GlassCard(radius: 30, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Map(initialPosition: mapPosition, interactionModes: []) {
                    if route.geoPoints.count > 1 {
                        MapPolyline(coordinates: route.geoPoints.map(\.coordinate))
                            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: route.geoPoints.map(\.coordinate))
                            .stroke(APEXColor.cyan.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                }
                .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: 185)
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(route.name).font(APEXFont.display(21))
                            Text(language.format(
                                "%.1f km · %@ · %@ navigation",
                                Double(route.distanceM) / 1_000,
                                language.text(route.terrain.capitalized),
                                language.text(route.navigationComplexity.capitalized)
                            ))
                                .font(APEXFont.mono(8))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                        Spacer()
                        if route.favourite { Image(systemName: "star.fill").foregroundStyle(APEXColor.amber) }
                    }
                    if route.note.isEmpty == false {
                        Text(route.note)
                            .font(APEXFont.body(10, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    if route.missionTags.isEmpty == false {
                        Text(route.missionTags.map {
                            language.text($0.replacingOccurrences(of: "_", with: " ").capitalized).uppercased(with: language.language.locale)
                        }.joined(separator: " · "))
                            .font(APEXFont.mono(7))
                            .foregroundStyle(APEXColor.cyan)
                    }
                    ForEach(session.data.orbitSegments.filter { $0.routeID == route.id }) { segment in
                        SegmentPerformanceRow(
                            segment: segment,
                            summary: OrbitAnalysisEngine.segmentSummary(segment: segment, runs: session.data.orbitRuns)
                        )
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            NavigationLink {
                                LiveRunView(
                                    mission: route.missionTags.first?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Easy",
                                    plannedRoute: route
                                )
                            } label: { Label(language.text("Start"), systemImage: "play.fill") }
                                .buttonStyle(.borderedProminent).tint(APEXColor.cyan)
                            Button(language.text(route.favourite ? "Unfavourite" : "Favourite")) { toggleFavourite() }
                                .buttonStyle(.bordered)
                            Button(language.text("Edit")) { editingRoute = route }
                                .buttonStyle(.bordered)
                            Button(language.text("Reverse")) { reverse() }
                                .buttonStyle(.bordered)
                            Button(language.text("Duplicate")) {
                                guard let operation = session.accountOperationLease() else { return }
                                Task { await duplicate(operation: operation) }
                            }
                                .buttonStyle(.bordered)
                            Button(language.text("Add segment")) { showSegmentEditor = true }
                                .buttonStyle(.bordered)
                            if let exportURL {
                                ShareLink(item: exportURL) { Label(language.text("Export GPX"), systemImage: "square.and.arrow.up") }
                                    .buttonStyle(.bordered)
                            } else {
                                Button(language.text("Prepare GPX")) { exportURL = try? OrbitGPXService.export(route: route) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(17)
            }
        }
        .sheet(isPresented: $showSegmentEditor) {
            SegmentEditorSheet(route: route)
                .environment(session)
        }
    }

    private var mapPosition: MapCameraPosition {
        guard let first = route.geoPoints.first else { return .automatic }
        let latitudes = route.geoPoints.map(\.lat)
        let longitudes = route.geoPoints.map(\.lng)
        return .region(.init(
            center: first.coordinate,
            span: .init(
                latitudeDelta: max(0.008, (latitudes.max() ?? first.lat) - (latitudes.min() ?? first.lat)) * 1.4,
                longitudeDelta: max(0.008, (longitudes.max() ?? first.lng) - (longitudes.min() ?? first.lng)) * 1.4
            )
        ))
    }

    private func toggleFavourite() {
        guard let operation = session.accountOperationLease() else { return }
        var updated = route
        updated.favourite.toggle()
        Task { await update(updated, operation: operation) }
    }

    private func reverse() {
        guard let operation = session.accountOperationLease() else { return }
        var updated = route
        updated.points.reverse()
        updated.name = "\(route.name) reversed"
        Task { await update(updated, operation: operation) }
    }

    @MainActor
    private func update(
        _ route: OrbitRouteRecord,
        operation: AccountOperationLease
    ) async {
        guard session.accountOperationIsCurrent(operation) else { return }
        do {
            try await session.updateOrbitRoute(route, operation: operation)
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            session.alertMessage = error.localizedDescription
        }
    }

    @MainActor
    private func duplicate(operation: AccountOperationLease) async {
        guard session.accountOperationIsCurrent(operation) else { return }
        do {
            _ = try await session.duplicateOrbitRoute(route, operation: operation)
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            session.alertMessage = error.localizedDescription
        }
    }
}

private struct SegmentPerformanceRow: View {
    @State private var language = LanguageState.shared
    let segment: OrbitSegment
    let summary: OrbitSegmentSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "scope").foregroundStyle(APEXColor.violet)
                Text(segment.name).font(APEXFont.body(10, weight: .bold))
                Spacer()
                Text(language.format("%.2f km", Double(segment.endDistanceM - segment.startDistanceM) / 1_000))
                    .font(APEXFont.mono(8))
            }
            if let summary {
                HStack(spacing: 13) {
                    segmentMetric("BEST", duration(summary.best.durationSeconds))
                    segmentMetric("RECENT", duration(summary.recent.durationSeconds))
                    segmentMetric("TYPICAL", duration(summary.typicalDurationSeconds))
                    Spacer(minLength: 0)
                }
                Text(language.text(summary.interpretation))
                    .font(APEXFont.body(8, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
            } else {
                Text(language.text("Complete this saved route to establish a private segment baseline."))
                    .font(APEXFont.body(8, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
        }
        .padding(11)
        .background(APEXColor.violet.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
    }

    private func segmentMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(language.text(label)).font(APEXFont.mono(6)).foregroundStyle(APEXColor.secondaryInk)
            Text(value).font(APEXFont.mono(8)).foregroundStyle(APEXColor.ink)
        }
    }

    private func duration(_ seconds: Double) -> String {
        let value = Int(seconds.rounded())
        return value >= 3_600
            ? String(format: "%d:%02d:%02d", value / 3_600, value / 60 % 60, value % 60)
            : String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private struct SegmentEditorSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let route: OrbitRouteRecord
    @State private var name = "Favourite segment"
    @State private var startM = 0.0
    @State private var endM: Double

    init(route: OrbitRouteRecord) {
        self.route = route
        _endM = State(initialValue: Double(min(route.distanceM, max(500, route.distanceM / 2))))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(language.text("Segment name"), text: $name)
                Section(language.text("Start")) {
                    Slider(value: $startM, in: 0...Double(max(1, route.distanceM - 100)), step: 50)
                    Text(language.format("%.2f km", startM / 1_000))
                }
                Section(language.text("End")) {
                    Slider(value: $endM, in: 100...Double(max(100, route.distanceM)), step: 50)
                    Text(language.format("%.2f km", endM / 1_000))
                }
                Text(language.text("Personal segments remain private. There are no public leaderboards."))
                    .font(APEXFont.body(10, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            .navigationTitle(language.text("Personal segment"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(language.text("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Save")) {
                        guard let operation = session.accountOperationLease() else { return }
                        Task {
                            await save(operation: operation)
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || endM <= startM + 50)
                }
            }
        }
    }

    @MainActor
    private func save(operation: AccountOperationLease) async {
        guard session.accountOperationIsCurrent(operation) else { return }
        do {
            try await session.saveOrbitSegment(
                route: route,
                name: name,
                startDistanceM: Int(startM),
                endDistanceM: Int(endM),
                operation: operation
            )
            guard session.accountOperationIsCurrent(operation) else { return }
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            session.alertMessage = error.localizedDescription
        }
    }
}

private struct RouteEditorSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    @State private var route: OrbitRouteRecord
    @State private var missionText: String

    init(route: OrbitRouteRecord) {
        _route = State(initialValue: route)
        _missionText = State(initialValue: route.missionTags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(language.text("Route name"), text: $route.name)
                TextField(language.text("Private note"), text: $route.note, axis: .vertical)
                    .lineLimit(3...6)
                Picker("Surface", selection: $route.surface) {
                    ForEach(["road", "path", "trail", "mixed"], id: \.self) { Text(language.text($0.capitalized)).tag($0) }
                }
                Picker("Useful for", selection: Binding(
                    get: { route.missionTags.first ?? "easy" },
                    set: { route.missionTags = [$0] }
                )) {
                    ForEach(["recovery", "easy", "tempo", "intervals", "hills", "long_run", "exploration"], id: \.self) {
                        Text(language.text($0.replacingOccurrences(of: "_", with: " ").capitalized)).tag($0)
                    }
                }
                Stepper("Rating: \(route.rating ?? 0) / 5", value: Binding(
                    get: { route.rating ?? 0 },
                    set: { route.rating = $0 == 0 ? nil : $0 }
                ), in: 0...5)
                TextField(language.text("Preferred sections, separated by commas"), text: Binding(
                    get: { route.preferredSections.joined(separator: ", ") },
                    set: { route.preferredSections = split($0) }
                ))
                TextField(language.text("Avoided sections, separated by commas"), text: Binding(
                    get: { route.avoidedSections.joined(separator: ", ") },
                    set: { route.avoidedSections = split($0) }
                ))
                Text(language.text("Preferred and avoided sections inform future route comparison. They are not safety guarantees."))
                    .font(APEXFont.body(9, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            .navigationTitle(language.text("Edit route"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(language.text("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Save")) {
                        guard let operation = session.accountOperationLease() else { return }
                        Task { await save(operation: operation) }
                    }
                    .disabled(route.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @MainActor
    private func save(operation: AccountOperationLease) async {
        guard session.accountOperationIsCurrent(operation) else { return }
        do {
            try await session.updateOrbitRoute(route, operation: operation)
            guard session.accountOperationIsCurrent(operation) else { return }
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            session.alertMessage = error.localizedDescription
        }
    }

    private func split(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.isEmpty == false }
    }
}

private struct HistoricalRunDebrief: View {
    @Environment(\.dismiss) private var dismiss
    let run: OrbitRunRecord

    var body: some View {
        RunDebriefView(run: run) { dismiss() }
    }
}
