import MapKit
import SwiftUI

struct ManualRouteEditorView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var points: [OrbitGeoPoint] = []
    @State private var name = ""
    @State private var mission = "easy"
    @State private var surface = "mixed"
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()
                    if points.count > 1 {
                        MapPolyline(coordinates: points.map(\.coordinate))
                            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: points.map(\.coordinate))
                            .stroke(APEXColor.cyan.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        Annotation(index == 0 ? language.text("START") : "\(index + 1)", coordinate: point.coordinate) {
                            Circle()
                                .fill(index == 0 ? APEXColor.amber : APEXColor.cyan)
                                .frame(width: index == 0 ? 16 : 11, height: index == 0 ? 16 : 11)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
                .mapControls { MapCompass(); MapUserLocationButton(); MapScaleView() }
                .gesture(
                    SpatialTapGesture().onEnded { event in
                        guard let coordinate = proxy.convert(event.location, from: .local) else { return }
                        points.append(.init(lat: coordinate.latitude, lng: coordinate.longitude, elevationM: nil))
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
            }
            .overlay(alignment: .top) {
                Text(language.text("Tap the map to place route points"))
                    .font(APEXFont.body(11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(.black.opacity(0.66), in: Capsule())
                    .padding(12)
            }

            VStack(spacing: 12) {
                HStack {
                    Button(language.text("Undo")) { if points.isEmpty == false { points.removeLast() } }
                        .buttonStyle(.bordered)
                    Button(language.text("Clear"), role: .destructive) { points.removeAll() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Text(distanceLabel)
                        .font(APEXFont.mono(10))
                }
                TextField(language.text("Route name"), text: $name)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Picker("Mission", selection: $mission) {
                        ForEach(["recovery", "easy", "tempo", "hills", "long_run", "exploration"], id: \.self) {
                            Text(language.text($0.replacingOccurrences(of: "_", with: " ").capitalized)).tag($0)
                        }
                    }
                    Picker("Surface", selection: $surface) {
                        ForEach(["road", "path", "trail", "mixed"], id: \.self) { Text(language.text($0.capitalized)).tag($0) }
                    }
                }
                Button { Task { await save() } } label: {
                    if saving { ProgressView().tint(.white) }
                    else { Label(language.text("Save drawn route"), systemImage: "checkmark") }
                }
                .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.cyan))
                .disabled(points.count < 2 || saving)
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(language.text("Draw route"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var candidate: OrbitRouteCandidate { OrbitGPXService.candidate(points: points) }
    private var distanceLabel: String { language.format("%.2f km", Double(candidate.distanceM) / 1_000) }

    @MainActor
    private func save() async {
        saving = true
        _ = await session.saveOrbitRoute(
            candidate,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Drawn route" : name,
            mission: mission,
            surface: surface,
            shape: "point_to_point"
        )
        saving = false
        dismiss()
    }
}
