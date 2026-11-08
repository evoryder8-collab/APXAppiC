import MapKit
import SwiftUI

struct RoutePlannerView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        GeometryReader { viewport in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: 18) {
                        routePreview(mapHeight: min(390, max(155, viewport.size.height * 0.44)))
                            .id("route-preview")
                        if let message {
                            Text(language.text(message))
                                .font(APEXFont.body(12, weight: .semibold))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        routeForm
                        if selected == nil, message != nil, !isGenerating {
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
                .onChange(of: candidates.first?.id) { _, firstID in
                    if firstID != nil {
                        withAnimation(reduceMotion ? nil : .snappy) { scroll.scrollTo("route-preview", anchor: .top) }
                    }
                }
            }
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

    private func routePreview(mapHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Map(position: $position) {
                UserAnnotation()
                if let selected {
                    MapPolyline(coordinates: selected.points.map(\.coordinate))
                        .stroke(APEXColor.cyan.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
            .mapControls { MapCompass(); MapUserLocationButton(); MapScaleView() }
            .frame(height: mapHeight)
            .accessibilityIdentifier("orbit.route.map")
            .overlay(alignment: .bottomLeading) {
                if selected == nil {
                    Label(language.text("START FROM CURRENT LOCATION"), systemImage: "location.fill")
                        .font(APEXFont.mono(10))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.72), in: Capsule())
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }

            if let selected {
                VStack(alignment: .leading, spacing: 12) {
                    if let index = candidates.firstIndex(where: { $0.id == selected.id }) {
                        HStack {
                            Text(language.text("Route options"))
                                .font(APEXFont.display(20))
                            Spacer()
                            Text("\(index + 1) / \(candidates.count)")
                                .font(APEXFont.mono(12))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }

                        HStack(spacing: 8) {
                            if candidates.count > 1 {
                                routeArrow(previous: true)
                                Menu {
                                    ForEach(Array(candidates.enumerated()), id: \.element.id) { offset, option in
                                        Button {
                                            select(option)
                                        } label: {
                                            let title = optionTitle(option, at: offset) + " · " + elevation(option)
                                            if option.id == selected.id { Label(title, systemImage: "checkmark") }
                                            else { Text(title) }
                                        }
                                    }
                                } label: {
                                    optionLabel(selected, index: index, opensMenu: true)
                                }
                                .accessibilityLabel(language.text("Route options"))
                                .accessibilityValue(optionTitle(selected, at: index) + " · " + elevation(selected))
                                .accessibilityIdentifier("orbit.route.options")
                                routeArrow(previous: false)
                            } else {
                                optionLabel(selected, index: index, opensMenu: false)
                            }
                        }
                    } else {
                        Text(distance(selected)).font(APEXFont.display(22))
                    }

                    Text(language.text(selected.explanation))
                        .font(APEXFont.body(13, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    routeActions(selected)
                }
                .padding(16)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.7)).allowsHitTesting(false) }
    }

    private func optionTitle(_ option: OrbitRouteCandidate, at index: Int) -> String {
        let rank = index == 0 ? language.text("Best fit") : language.format("OPTION %d", index + 1)
        return rank + " · " + distance(option)
    }

    private func distance(_ option: OrbitRouteCandidate) -> String {
        language.format("%.1f km", Double(option.distanceM) / 1_000)
    }

    private func elevation(_ option: OrbitRouteCandidate) -> String {
        option.elevationGainM.map { language.format("%d m gain", $0) } ?? language.text("Elevation unavailable")
    }

    private func optionLabel(_ option: OrbitRouteCandidate, index: Int, opensMenu: Bool) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(optionTitle(option, at: index)).font(APEXFont.body(16, weight: .bold))
                Text(elevation(option) + " · " + language.format("MISSION FIT %d", option.score))
                    .font(APEXFont.mono(10))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if opensMenu { Image(systemName: "chevron.down").font(.caption.weight(.bold)) }
        }
        .foregroundStyle(APEXColor.ink)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
        .background(APEXColor.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }

    private func routeArrow(previous: Bool) -> some View {
        Button {
            guard let index = candidates.firstIndex(where: { $0.id == selected?.id }) else { return }
            let count = candidates.count
            select(candidates[(index + (previous ? count - 1 : 1)) % count])
        } label: {
            Image(systemName: previous ? "chevron.backward" : "chevron.forward")
                .font(.body.weight(.semibold))
                .foregroundStyle(APEXColor.ink)
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.text(previous ? "Previous route" : "Next route"))
        .accessibilityIdentifier(previous ? "orbit.route.previous" : "orbit.route.next")
    }

    private func select(_ candidate: OrbitRouteCandidate) {
        withAnimation(reduceMotion ? nil : .snappy) {
            selected = candidate
            fit(candidate)
        }
    }

    private func routeActions(_ selected: OrbitRouteCandidate) -> some View {
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

    private var routeForm: some View {
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
        let offsets = candidate.points.map { ($0.lng - first.lng).remainder(dividingBy: 360) }
        guard let south = latitudes.min(), let north = latitudes.max(),
              let west = offsets.min(), let east = offsets.max() else { return }
        let center = CLLocationCoordinate2D(latitude: (south + north) / 2,
            longitude: (first.lng + (west + east) / 2).remainder(dividingBy: 360))
        position = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(
            latitudeDelta: max(0.008, north - south) * 1.35,
            longitudeDelta: max(0.008, east - west) * 1.35
        )))
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
            candidates = []
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
