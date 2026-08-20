import CoreLocation
import Photos
import SwiftUI
import UIKit

struct OrbitRoutePosterSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let run: OrbitRunRecord

    @State private var style = "constellation"
    @State private var trimM = 300.0
    @State private var includeHeartRate = false
    @State private var note = ""
    @State private var renderedURL: URL?
    @State private var saving = false
    @State private var message: String?
    @State private var language = LanguageState.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    RoutePosterArtwork(
                        run: run,
                        profileName: session.profile?.displayName ?? "APEX athlete",
                        style: style,
                        privacyTrimM: trimM,
                        includeHeartRate: includeHeartRate,
                        note: note
                    )
                    .frame(width: 324, height: 405)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.24), radius: 20, y: 12)

                    Picker("Style", selection: $style) {
                        Text(language.text("Map")).tag("map")
                        Text(language.text("Constellation")).tag("constellation")
                        Text(language.text("Elevation")).tag("elevation")
                        Text(language.text("Minimal")).tag("minimal")
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(language.text("Privacy trim"))
                            Spacer()
                            Text(language.format("%d m from both ends", Int(trimM)))
                                .font(APEXFont.mono(8))
                        }
                        Slider(value: $trimM, in: 0...maximumTrim, step: 50)
                            .tint(APEXColor.cyan)
                        Text(language.text("The precise start and finish are hidden by default."))
                            .font(APEXFont.body(9, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }

                    Toggle(language.text("Include recorded heart rate"), isOn: $includeHeartRate)
                        .disabled(run.metrics["heart_rate_avg"]?.numberValue == nil)
                        .tint(APEXColor.cyan)
                    TextField(language.text("Optional poster note"), text: $note)
                        .textFieldStyle(.roundedBorder)

                    if let message {
                        Text(language.text(message))
                            .font(APEXFont.body(10, weight: .semibold))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }

                    HStack(spacing: 10) {
                        Button { Task { await saveToPhotos() } } label: {
                            if saving { ProgressView() }
                            else { Label(language.text("Save image"), systemImage: "photo.badge.arrow.down") }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(APEXColor.cyan)

                        if let renderedURL {
                            ShareLink(item: renderedURL) {
                                Label(language.text("Share"), systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button(language.text("Prepare share")) { render() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .navigationTitle(language.text("Route poster"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(language.text("Done")) { dismiss() } } }
            .onChange(of: style) { _, _ in renderedURL = nil }
            .onChange(of: trimM) { _, _ in renderedURL = nil }
            .onChange(of: note) { _, _ in renderedURL = nil }
        }
    }

    private var maximumTrim: Double {
        max(50, min(1_000, (run.metrics["distance_m"]?.numberValue ?? 0) * 0.32))
    }

    @MainActor
    private func render() {
        do {
            renderedURL = try OrbitPosterRenderer.render(
                run: run,
                profileName: session.profile?.displayName ?? "APEX athlete",
                style: style,
                privacyTrimM: trimM,
                includeHeartRate: includeHeartRate,
                note: note
            )
            message = nil
        } catch {
            message = language.text(error.localizedDescription)
        }
    }

    @MainActor
    private func saveToPhotos() async {
        saving = true
        if renderedURL == nil { render() }
        guard let renderedURL else {
            saving = false
            return
        }
        do {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { throw OrbitPosterError.photoPermission }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: renderedURL)
            }
            await session.saveOrbitPosterMetadata(
                run: run,
                style: style,
                privacyTrimM: Int(trimM),
                includeHeartRate: includeHeartRate,
                note: note
            )
            message = language.text("Poster saved to Photos.")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            message = language.text(error.localizedDescription)
        }
        saving = false
    }
}

private struct RoutePosterArtwork: View {
    @State private var language = LanguageState.shared
    let run: OrbitRunRecord
    let profileName: String
    let style: String
    let privacyTrimM: Double
    let includeHeartRate: Bool
    let note: String

    private var palette: (Color, Color, Color) {
        switch style {
        case "map": (Color(red: 0.03, green: 0.12, blue: 0.16), Color(red: 0.02, green: 0.26, blue: 0.27), APEXColor.cyan)
        case "elevation": (Color(red: 0.11, green: 0.03, blue: 0.17), Color(red: 0.32, green: 0.08, blue: 0.27), APEXColor.amber)
        case "minimal": (.white, Color(red: 0.93, green: 0.96, blue: 0.97), .black)
        default: (.black, Color(red: 0.08, green: 0.03, blue: 0.2), APEXColor.cyan)
        }
    }

    private var points: [PosterPoint] {
        OrbitPosterRenderer.trimmedPoints(run: run, trimM: privacyTrimM)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.0, palette.1], startPoint: .topLeading, endPoint: .bottomTrailing)
            if style == "constellation" || style == "elevation" { posterStars }
            if style == "map" { mapGrid }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text("APEX ORBIT"))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(2)
                        Text(profileName.uppercased())
                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                            .opacity(0.55)
                    }
                    Spacer()
                    Text(language.dateKey(run.localDate))
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .opacity(0.55)
                }
                .foregroundStyle(style == "minimal" ? .black : .white)

                Spacer(minLength: 14)

                PosterRouteCanvas(points: points, style: style, accent: palette.2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Spacer(minLength: 14)

                Text(language.text(run.mission.replacingOccurrences(of: "_", with: " ").capitalized).uppercased(with: language.language.locale))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(palette.2)
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(((run.metrics["distance_m"]?.numberValue ?? 0) / 1_000).formatted(.number.precision(.fractionLength(2)).locale(language.language.locale)))
                        .font(.system(size: 42, weight: .black, design: .rounded))
                    Text(language.text("KM"))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .opacity(0.55)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(duration(run.metrics["moving_s"]?.numberValue ?? 0))
                        Text(pace(run.metrics["avg_pace_sec_km"]?.numberValue))
                        if includeHeartRate, let heartRate = run.metrics["heart_rate_avg"]?.numberValue {
                            Text(language.format("%d BPM", Int(heartRate)))
                        }
                    }
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(style == "minimal" ? .black : .white)
                if note.isEmpty == false {
                    Text(note)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(style == "minimal" ? .black.opacity(0.65) : .white.opacity(0.65))
                        .lineLimit(2)
                }
                Text(language.format("START AND FINISH PRIVACY TRIM · %d M", Int(privacyTrimM)))
                    .font(.system(size: 5.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(style == "minimal" ? .black.opacity(0.35) : .white.opacity(0.35))
                    .padding(.top, 7)
            }
            .padding(22)
        }
    }

    private var posterStars: some View {
        Canvas { context, size in
            for index in 0..<44 {
                let x = CGFloat((index * 73) % 101) / 100 * size.width
                let y = CGFloat((index * 47) % 97) / 100 * size.height
                let radius: CGFloat = index.isMultiple(of: 9) ? 1.2 : 0.45
                context.fill(Path(ellipseIn: .init(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(index.isMultiple(of: 7) ? 0.7 : 0.24)))
            }
        }
    }

    private var mapGrid: some View {
        Canvas { context, size in
            for index in 0..<13 {
                var path = Path()
                let y = CGFloat(index) / 12 * size.height
                path.move(to: .init(x: 0, y: y))
                path.addLine(to: .init(x: size.width, y: y + CGFloat((index % 3) * 7)))
                context.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: index.isMultiple(of: 3) ? 2 : 0.6)
            }
        }
    }

    private func duration(_ seconds: Double) -> String {
        let value = Int(seconds)
        return value >= 3_600 ? String(format: "%d:%02d:%02d", value / 3_600, value / 60 % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func pace(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return language.text("PACE –:––") }
        return language.format("PACE %d:%02d /KM", Int(seconds) / 60, Int(seconds) % 60)
    }
}

private struct PosterRouteCanvas: View {
    let points: [PosterPoint]
    let style: String
    let accent: Color

    var body: some View {
        Canvas { context, size in
            guard points.count >= 2 else { return }
            let inset: CGFloat = 12
            let minX = points.map(\.x).min() ?? 0
            let maxX = points.map(\.x).max() ?? 1
            let minY = points.map(\.y).min() ?? 0
            let maxY = points.map(\.y).max() ?? 1
            let width = max(maxX - minX, 0.000_001)
            let height = max(maxY - minY, 0.000_001)
            let scale = min((size.width - inset * 2) / width, (size.height - inset * 2) / height)
            let renderedWidth = width * scale
            let renderedHeight = height * scale
            let originX = (size.width - renderedWidth) / 2
            let originY = (size.height - renderedHeight) / 2
            let rendered = points.map { point in
                CGPoint(x: originX + (point.x - minX) * scale, y: originY + (maxY - point.y) * scale)
            }
            var path = Path()
            path.move(to: rendered[0])
            for point in rendered.dropFirst() { path.addLine(to: point) }
            context.stroke(path, with: .color(style == "minimal" ? .black.opacity(0.13) : .white.opacity(0.18)), style: .init(lineWidth: 7, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(accent), style: .init(lineWidth: style == "constellation" ? 1.7 : 2.8, lineCap: .round, lineJoin: .round))
            if style == "constellation" {
                for (index, point) in rendered.enumerated() where index.isMultiple(of: max(1, rendered.count / 16)) {
                    context.fill(Path(ellipseIn: .init(x: point.x - 2, y: point.y - 2, width: 4, height: 4)), with: .color(.white))
                    context.fill(Path(ellipseIn: .init(x: point.x - 5, y: point.y - 5, width: 10, height: 10)), with: .color(accent.opacity(0.16)))
                }
            }
        }
    }
}

struct PosterPoint: Hashable, Sendable {
    let x: CGFloat
    let y: CGFloat
    let distanceM: Double
}

enum OrbitPosterRenderer {
    static func trimmedPoints(run: OrbitRunRecord, trimM: Double) -> [PosterPoint] {
        let coordinates: [(Double, Double)] = run.samples.compactMap { sample in
            guard let object = sample.objectValue,
                  let lat = object["lat"]?.numberValue,
                  let lng = object["lng"]?.numberValue
            else { return nil }
            return (lat, lng)
        }
        guard coordinates.count >= 2 else { return [] }
        let origin = coordinates[0]
        let latitudeScale = Double.pi * 6_371_000 / 180
        let longitudeScale = latitudeScale * cos(origin.0 * .pi / 180)
        var cumulative = [0.0]
        for index in 1..<coordinates.count {
            let first = CLLocation(latitude: coordinates[index - 1].0, longitude: coordinates[index - 1].1)
            let second = CLLocation(latitude: coordinates[index].0, longitude: coordinates[index].1)
            cumulative.append(cumulative.last! + second.distance(from: first))
        }
        let total = cumulative.last ?? 0
        guard total > trimM * 2 + 50 else { return [] }
        return coordinates.enumerated().compactMap { index, coordinate in
            let distance = cumulative[index]
            guard distance >= trimM, distance <= total - trimM else { return nil }
            return PosterPoint(
                x: CGFloat((coordinate.1 - origin.1) * longitudeScale),
                y: CGFloat((coordinate.0 - origin.0) * latitudeScale),
                distanceM: distance
            )
        }
    }

    @MainActor
    static func render(
        run: OrbitRunRecord,
        profileName: String,
        style: String,
        privacyTrimM: Double,
        includeHeartRate: Bool,
        note: String
    ) throws -> URL {
        guard trimmedPoints(run: run, trimM: privacyTrimM).count >= 2 else { throw OrbitPosterError.trimTooLarge }
        let artwork = RoutePosterArtwork(
            run: run,
            profileName: profileName,
            style: style,
            privacyTrimM: privacyTrimM,
            includeHeartRate: includeHeartRate,
            note: note
        )
        .frame(width: 360, height: 450)
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { throw OrbitPosterError.renderFailed }
        let url = FileManager.default.temporaryDirectory.appending(path: "apex-orbit-\(run.localDate)-\(style).png")
        try data.write(to: url, options: .atomic)
        return url
    }
}

enum OrbitPosterError: LocalizedError {
    case trimTooLarge
    case renderFailed
    case photoPermission

    var errorDescription: String? {
        switch self {
        case .trimTooLarge: "Privacy trim leaves too little route to create a poster."
        case .renderFailed: "The route poster could not be rendered."
        case .photoPermission: "Photo access was not granted. You can still use the Share button."
        }
    }
}
