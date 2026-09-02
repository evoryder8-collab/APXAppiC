import MapKit
import SwiftUI

struct RoutePlannerView: View {
    @Environment(AppSession.self) private var session
    @State private var location = OrbitLocationManager.shared
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var distanceKM = 5.0
    @State private var shape = "loop"
    @State private var terrain = "flat"
    @State private var surface = "mixed"
    @State private var mission: String
    @State private var simpleNavigation = true
    @State private var candidates: [OrbitRouteCandidate] = []
    @State private var selected: OrbitRouteCandidate?
    @State private var isGenerating = false
    @State private var message: String?
    @State private var routeToStart: OrbitRouteRecord?
    @State private var importingGPX = false
    @State private var language = LanguageState.shared
    let campaignSessionID: UUID?

    init(initialMission: String = "Easy", campaignSessionID: UUID? = nil) {
        _mission = State(initialValue: initialMission.replacingOccurrences(of: "_", with: " ").capitalized)
        self.campaignSessionID = campaignSessionID
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack(alignment: .bottomLeading) {
                    Map(position: $position) {
                        UserAnnotation()
                        if let selected {
                            MapPolyline(coordinates: selected.points.map(\.coordinate))
                                .stroke(APEXColor.cyan.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
                    .mapControls { MapCompass(); MapUserLocationButton(); MapScaleView() }
                    .frame(height: 430)

                    HStack(spacing: 8) {
                        Image(systemName: selected == nil ? "location.fill" : "point.topleft.down.to.point.bottomright.curvepath")
                        Text(language.text(mapCaption))
                    }
                    .font(APEXFont.mono(9))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 38)
                    .background(.black.opacity(0.72), in: Capsule())
                    .padding(15)
                }
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 34).stroke(.white.opacity(0.8)))

                GlassCard(radius: 30, padding: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(language.text("Build a route"))
                            .font(APEXFont.display(27))
                        HStack {
                            Text(language.text("DISTANCE")).font(APEXFont.mono(10)).tracking(1.2)
                            Spacer()
                            Text(language.format("%.1f km", distanceKM)).font(APEXFont.display(19))
                        }
                        Slider(value: $distanceKM, in: 1...42.2, step: 0.5).tint(APEXColor.cyan)
                        Picker("Shape", selection: $shape) {
                            Text(language.text("Loop")).tag("loop")
                            Text(language.text("Out & back")).tag("out_back")
                            Text(language.text("Point to point")).tag("point_to_point")
                        }.pickerStyle(.segmented)
                        Picker("Terrain", selection: $terrain) {
                            Text(language.text("Flat")).tag("flat")
                            Text(language.text("Rolling")).tag("rolling")
                            Text(language.text("Hilly")).tag("hilly")
                        }.pickerStyle(.segmented)
                        Picker("Surface", selection: $surface) {
                            Text(language.text("Road")).tag("road")
                            Text(language.text("Path")).tag("path")
                            Text(language.text("Trail")).tag("trail")
                            Text(language.text("Mixed")).tag("mixed")
                        }.pickerStyle(.menu)
                        Picker("Mission", selection: $mission) {
                            ForEach(["Recovery", "Easy", "Tempo", "Hills", "Long run"], id: \.self) { Text(language.text($0)).tag($0) }
                        }.pickerStyle(.menu)
                        Toggle(language.text("Prefer simpler navigation"), isOn: $simpleNavigation)
                            .tint(APEXColor.cyan)

                        Button {
                            guard let operation = session.accountOperationLease() else { return }
                            Task { await generate(operation: operation) }
                        } label: {
                            if isGenerating { ProgressView().tint(.white) }
                            else { Label(language.text("Generate route options"), systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                        }
                        .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.cyan))
                        .disabled(isGenerating || location.currentLocation == nil)

                        HStack(spacing: 10) {
                            NavigationLink {
                                ManualRouteEditorView()
                            } label: {
                                Label(language.text("Draw"), systemImage: "pencil.and.outline")
                            }
                            .buttonStyle(.bordered)

                            Button { importingGPX = true } label: {
                                Label(language.text("Import GPX"), systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                        }

                        if location.currentLocation == nil {
                            Label(language.text("Waiting for location permission and a usable GPS fix"), systemImage: "location.circle")
                                .font(APEXFont.body(11, weight: .semibold))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                    }
                }

                if let message {
                    Text(language.text(message))
                        .font(APEXFont.body(12, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .background(APEXColor.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                }

                if candidates.isEmpty == false {
                    VStack(alignment: .leading, spacing: 11) {
                        Text(language.text("Route options"))
                            .font(APEXFont.display(24))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 11) {
                                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                                    Button {
                                        withAnimation(.snappy) {
                                            selected = candidate
                                            fit(candidate)
                                        }
                                    } label: {
                                        RouteCandidateCard(
                                            candidate: candidate,
                                            isBest: index == 0,
                                            isSelected: selected?.id == candidate.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                if let selected {
                    GlassCard(radius: 30, padding: 20) {
                        VStack(alignment: .leading, spacing: 13) {
                            Text(language.format("Orbit option %d", selected.optionNumber))
                                .font(APEXFont.display(23))
                            Text(language.text(selected.explanation))
                                .font(APEXFont.body(13, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                            HStack(spacing: 10) {
                                Button(language.text("Save route")) {
                                    guard let operation = session.accountOperationLease() else { return }
                                    Task { _ = await save(selected, operation: operation) }
                                }
                                    .buttonStyle(.bordered)
                                Button(language.text("Start this route")) {
                                    guard let operation = session.accountOperationLease() else { return }
                                    Task {
                                        let route = await save(selected, operation: operation)
                                        guard session.accountOperationIsCurrent(operation) else { return }
                                        routeToStart = route
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(APEXColor.cyan)
                            }
                        }
                    }
                } else if message != nil {
                    NavigationLink {
                        LiveRunView(mission: mission, campaignSessionID: campaignSessionID)
                    } label: {
                        Label(language.text("Start a free run instead"), systemImage: "figure.run")
                    }
                    .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.cyan))
                }

                Text(language.text("Orbit never labels a route guaranteed safe. It can compare map-supported features such as crossings, turns, terrain and surface where data exists."))
                    .font(APEXFont.body(11, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .padding(.horizontal, 5)
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .navigationTitle(language.text("Plan a run"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $routeToStart) { route in
            LiveRunView(mission: mission, plannedRoute: route, campaignSessionID: campaignSessionID)
        }
        .onAppear { location.requestLocation() }
        .fileImporter(isPresented: $importingGPX, allowedContentTypes: [.gpx]) { result in
            guard let operation = session.accountOperationLease() else { return }
            Task { await importGPX(result, operation: operation) }
        }
    }

    @MainActor
    private func generate(operation: AccountOperationLease) async {
        guard session.accountOperationIsCurrent(operation),
              let start = location.currentLocation?.coordinate else { return }
        isGenerating = true
        message = "Orbit is comparing genuinely different route shapes."
        defer {
            if session.accountOperationIsCurrent(operation) {
                isGenerating = false
            }
        }
        do {
            let generatedCandidates = try await OrbitRouteEngine.shared.generate(
                start: start,
                distanceKM: distanceKM,
                shape: shape,
                terrain: terrain,
                surface: surface,
                mission: mission,
                simpleNavigation: simpleNavigation
            )
            guard session.accountOperationIsCurrent(operation) else { return }
            candidates = generatedCandidates
            selected = candidates.first
            if let selected { fit(selected) }
            message = nil
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            candidates = []
            selected = nil
            message = language.text(error.localizedDescription)
        }
    }

    @MainActor
    private func save(
        _ candidate: OrbitRouteCandidate,
        operation: AccountOperationLease
    ) async -> OrbitRouteRecord? {
        guard session.accountOperationIsCurrent(operation) else { return nil }
        do {
            return try await session.saveOrbitRoute(
                candidate,
                name: "Orbit \(mission) · \(Date().apexDateKey)",
                mission: mission,
                surface: surface,
                shape: shape,
                operation: operation
            )
        } catch is CancellationError {
            return nil
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return nil }
            message = language.text(error.localizedDescription)
            return nil
        }
    }

    private func fit(_ candidate: OrbitRouteCandidate) {
        guard let first = candidate.points.first else { return }
        let latitudes = candidate.points.map(\.lat)
        let longitudes = candidate.points.map(\.lng)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.008, (latitudes.max() ?? first.lat) - (latitudes.min() ?? first.lat)) * 1.35,
            longitudeDelta: max(0.008, (longitudes.max() ?? first.lng) - (longitudes.min() ?? first.lng)) * 1.35
        )
        position = .region(.init(center: first.coordinate, span: span))
    }

    private var mapCaption: String {
        guard let selected else { return "START FROM CURRENT LOCATION" }
        let distance = (Double(selected.distanceM) / 1_000).formatted(.number.precision(.fractionLength(1)).locale(language.language.locale))
        return language.format("OPTION %d · %@ KM", selected.optionNumber, distance)
    }

    @MainActor
    private func importGPX(
        _ result: Result<URL, Error>,
        operation: AccountOperationLease
    ) async {
        guard session.accountOperationIsCurrent(operation) else { return }
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let points = try OrbitGPXService.parse(Data(contentsOf: url))
            let candidate = OrbitGPXService.candidate(points: points)
            let route = try await session.saveOrbitRoute(
                candidate,
                name: url.deletingPathExtension().lastPathComponent,
                mission: mission,
                surface: surface,
                shape: "point_to_point",
                operation: operation
            )
            guard session.accountOperationIsCurrent(operation) else { return }
            selected = candidate
            fit(candidate)
            message = route == nil ? "The GPX route could not be saved." : "GPX imported into your private Orbit library."
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            message = language.text(error.localizedDescription)
        }
    }
}

private struct RouteCandidateCard: View {
    @State private var language = LanguageState.shared
    let candidate: OrbitRouteCandidate
    let isBest: Bool
    let isSelected: Bool

    private var distanceLabel: String {
        language.format("%.1f km", Double(candidate.distanceM) / 1_000)
    }

    private var elevationLabel: String {
        candidate.elevationGainM.map { language.format("%d m gain", $0) } ?? language.text("Elevation unavailable")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isBest ? language.text("BEST FIT") : language.format("OPTION %d", candidate.optionNumber))
                .font(APEXFont.mono(9))
                .tracking(1)
                .foregroundStyle(isBest ? APEXColor.amber : APEXColor.cyan)
            Text(distanceLabel)
                .font(APEXFont.display(25))
            Text(elevationLabel)
                .font(APEXFont.mono(9))
                .foregroundStyle(APEXColor.secondaryInk)
            Text(language.text(candidate.explanation))
                .font(APEXFont.body(11, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
                .lineLimit(4)
            Text(language.format("MISSION FIT %d", candidate.score))
                .font(APEXFont.mono(8))
                .foregroundStyle(APEXColor.cyan)
        }
        .frame(width: 225, alignment: .leading)
        .padding(17)
        .background(
            isSelected ? APEXColor.cyan.opacity(0.14) : .white.opacity(0.62),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(isSelected ? APEXColor.cyan : .white.opacity(0.9))
        )
    }
}
