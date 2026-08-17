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
                        Text("Build a route")
                            .font(APEXFont.display(27))
                        HStack {
                            Text("DISTANCE").font(APEXFont.mono(10)).tracking(1.2)
                            Spacer()
                            Text(language.format("%.1f km", distanceKM)).font(APEXFont.display(19))
                        }
                        Slider(value: $distanceKM, in: 1...42.2, step: 0.5).tint(APEXColor.cyan)
                        Picker("Shape", selection: $shape) {
                            Text("Loop").tag("loop")
                            Text("Out & back").tag("out_back")
                            Text("Point to point").tag("point_to_point")
                        }.pickerStyle(.segmented)
                        Picker("Terrain", selection: $terrain) {
                            Text("Flat").tag("flat")
                            Text("Rolling").tag("rolling")
                            Text("Hilly").tag("hilly")
                        }.pickerStyle(.segmented)
                        Picker("Surface", selection: $surface) {
                            Text("Road").tag("road")
                            Text("Path").tag("path")
                            Text("Trail").tag("trail")
                            Text("Mixed").tag("mixed")
                        }.pickerStyle(.menu)
                        Picker("Mission", selection: $mission) {
                            ForEach(["Recovery", "Easy", "Tempo", "Hills", "Long run"], id: \.self) { Text(language.text($0)).tag($0) }
                        }.pickerStyle(.menu)
                        Toggle("Prefer simpler navigation", isOn: $simpleNavigation)
                            .tint(APEXColor.cyan)

                        Button { Task { await generate() } } label: {
                            if isGenerating { ProgressView().tint(.white) }
                            else { Label("Generate route options", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                        }
                        .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.cyan))
                        .disabled(isGenerating || location.currentLocation == nil)

                        HStack(spacing: 10) {
                            NavigationLink {
                                ManualRouteEditorView()
                            } label: {
                                Label("Draw", systemImage: "pencil.and.outline")
                            }
                            .buttonStyle(.bordered)

                            Button { importingGPX = true } label: {
                                Label("Import GPX", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                        }

                        if location.currentLocation == nil {
                            Label("Waiting for location permission and a usable GPS fix", systemImage: "location.circle")
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
                        Text("Route options")
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
                                Button("Save route") { Task { _ = await save(selected) } }
                                    .buttonStyle(.bordered)
                                Button("Start this route") {
                                    Task { routeToStart = await save(selected) }
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
                        Label("Start a free run instead", systemImage: "figure.run")
                    }
                    .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.cyan))
                }

                Text("Orbit never labels a route guaranteed safe. It can compare map-supported features such as crossings, turns, terrain and surface where data exists.")
                    .font(APEXFont.body(11, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .padding(.horizontal, 5)
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .navigationTitle("Plan a run")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $routeToStart) { route in
            LiveRunView(mission: mission, plannedRoute: route, campaignSessionID: campaignSessionID)
        }
        .onAppear { location.requestLocation() }
        .fileImporter(isPresented: $importingGPX, allowedContentTypes: [.gpx]) { result in
            Task { await importGPX(result) }
        }
    }

    @MainActor
    private func generate() async {
        guard let start = location.currentLocation?.coordinate else { return }
        isGenerating = true
        message = "Orbit is comparing genuinely different route shapes."
        defer { isGenerating = false }
        do {
            candidates = try await OrbitRouteEngine.shared.generate(
                start: start,
                distanceKM: distanceKM,
                shape: shape,
                terrain: terrain,
                surface: surface,
                mission: mission,
                simpleNavigation: simpleNavigation
            )
            selected = candidates.first
            if let selected { fit(selected) }
            message = nil
        } catch {
            candidates = []
            selected = nil
            message = language.text(error.localizedDescription)
        }
    }

    @MainActor
    private func save(_ candidate: OrbitRouteCandidate) async -> OrbitRouteRecord? {
        await session.saveOrbitRoute(
            candidate,
            name: "Orbit \(mission) · \(Date().apexDateKey)",
            mission: mission,
            surface: surface,
            shape: shape
        )
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
    private func importGPX(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let points = try OrbitGPXService.parse(Data(contentsOf: url))
            let candidate = OrbitGPXService.candidate(points: points)
            let route = await session.saveOrbitRoute(
                candidate,
                name: url.deletingPathExtension().lastPathComponent,
                mission: mission,
                surface: surface,
                shape: "point_to_point"
            )
            selected = candidate
            fit(candidate)
            message = route == nil ? "The GPX route could not be saved." : "GPX imported into your private Orbit library."
        } catch {
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
