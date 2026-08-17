import PhotosUI
import SwiftUI

struct VisualProgressView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var includeStats = true
    @State private var showCamera = false
    @State private var pose = "front"
    @State private var note = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var comparisonSelection: [UUID] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Private Visual Progress", systemImage: "camera.fill")
                        .font(APEXFont.display(31))
                    Text("Your photos remain private. Compare your physique and the performance signals behind it.")
                        .font(APEXFont.body(14, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let selectedImage {
                    ProgressImageCard(image: selectedImage, title: "New capture", includeStats: includeStats, snapshot: session.data.snapshots.first)
                    GlassCard(radius: 29, padding: 19) {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("Pose", selection: $pose) {
                                Text("Front").tag("front")
                                Text("Side").tag("side")
                                Text("Back").tag("back")
                            }
                            .pickerStyle(.segmented)
                            TextField("Optional note", text: $note, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                            HStack(spacing: 10) {
                                Button("Retake") { self.selectedImage = nil }
                                    .buttonStyle(.bordered)
                                Button {
                                    Task { await save(selectedImage) }
                                } label: {
                                    if isSaving { ProgressView().tint(.white) }
                                    else { Label("Save private checkpoint", systemImage: "lock.fill") }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(APEXColor.violet)
                                .disabled(isSaving)
                            }
                        }
                    }
                } else {
                    GlassCard(radius: 34, padding: 24) {
                        VStack(spacing: 18) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 55, weight: .light))
                                .foregroundStyle(APEXColor.violet)
                            Text("Create a new checkpoint")
                                .font(APEXFont.display(23))
                            Text("Use the same pose, distance and lighting for the clearest comparison.")
                                .font(APEXFont.body(13, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .multilineTextAlignment(.center)
                            HStack {
                                Button { showCamera = true } label: {
                                    Label("Camera", systemImage: "camera.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(APEXColor.violet)
                                PhotosPicker(selection: $selectedItem, matching: .images) {
                                    Label("Library", systemImage: "photo")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                GlassCard(radius: 29, padding: 18) {
                    Toggle(isOn: $includeStats) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Include stats")
                                .font(APEXFont.display(18))
                            Text("Overlay compact performance bars on comparison photos")
                                .font(APEXFont.body(11, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                    }
                    .tint(APEXColor.violet)
                }

                if comparisonSelection.count == 2 {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Before and after")
                                .font(APEXFont.display(25))
                            Spacer()
                            Button("Clear") { comparisonSelection = [] }
                                .font(APEXFont.body(12, weight: .bold))
                        }
                        HStack(spacing: 10) {
                            ForEach(selectedPhotos) { photo in
                                RemoteProgressImageCard(
                                    photo: photo,
                                    title: photo == selectedPhotos.first ? "Before" : "After",
                                    includeStats: includeStats,
                                    snapshot: snapshot(for: photo),
                                    compact: true
                                )
                            }
                        }
                    }
                }

                if session.data.progressPhotos.isEmpty {
                    GlassCard(radius: 29, padding: 20) {
                        VStack(spacing: 9) {
                            Text("No synced checkpoints yet")
                                .font(APEXFont.display(20))
                            Text("Your existing web progress photos will appear here as soon as their private signed previews are loaded.")
                                .font(APEXFont.body(12, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Timeline")
                            .font(APEXFont.display(25))
                        Text("Select any two checkpoints to compare them.")
                            .font(APEXFont.body(12, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                        ForEach(session.data.progressPhotos) { photo in
                            ProgressTimelineRow(
                                photo: photo,
                                selected: comparisonSelection.contains(photo.id)
                            ) {
                                toggleComparison(photo.id)
                            }
                        }
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 28)
        }
        .navigationTitle("Visual Progress")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                selectedImage = image
            }
        }
        .sheet(isPresented: $showCamera) {
            ProgressCameraPicker(image: $selectedImage)
                .ignoresSafeArea()
        }
        .alert("Could not save checkpoint", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(language.text(saveError ?? "Please try again."))
        }
    }

    private var selectedPhotos: [ProgressPhoto] {
        comparisonSelection.compactMap { id in session.data.progressPhotos.first { $0.id == id } }
            .sorted { $0.localDate < $1.localDate }
    }

    private func snapshot(for photo: ProgressPhoto) -> RPGSnapshot? {
        session.data.snapshots
            .filter { $0.date <= photo.localDate }
            .sorted { $0.date > $1.date }
            .first
    }

    private func toggleComparison(_ id: UUID) {
        if comparisonSelection.contains(id) {
            comparisonSelection.removeAll { $0 == id }
        } else if comparisonSelection.count < 2 {
            comparisonSelection.append(id)
        } else {
            comparisonSelection = [comparisonSelection[1], id]
        }
    }

    @MainActor
    private func save(_ image: UIImage) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let normalized = image.apexNormalized(maxDimension: 2_400)
            let thumbnail = normalized.apexNormalized(maxDimension: 600)
            guard let originalData = normalized.jpegData(compressionQuality: 0.88),
                  let thumbnailData = thumbnail.jpegData(compressionQuality: 0.76)
            else { throw VisualProgressError.encodingFailed }
            try await session.saveProgressPhoto(
                original: originalData,
                thumbnail: thumbnailData,
                width: Int(normalized.size.width),
                height: Int(normalized.size.height),
                pose: pose,
                note: note
            )
            selectedImage = nil
            note = ""
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct ProgressImageCard: View {
    @State private var language = LanguageState.shared
    let image: UIImage
    let title: String
    let includeStats: Bool
    let snapshot: RPGSnapshot?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 470)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.68)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 9) {
                Text(language.text(title).uppercased(with: language.language.locale))
                    .font(APEXFont.mono(11))
                    .tracking(1.5)
                if includeStats {
                    compactBar("OVERALL", snapshot?.overall ?? 0, APEXColor.violet)
                    compactBar("HEALTH", snapshot?.health ?? 0, APEXColor.green)
                    compactBar("JOINTS", snapshot?.joint ?? 0, APEXColor.amber)
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: 230, alignment: .leading)
        }
        .frame(height: 470)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private func compactBar(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(language.format("%@  %d", language.text(title), Int(value.rounded()))).font(APEXFont.mono(8))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(color).frame(width: proxy.size.width * min(max(value / 100, 0), 1))
                }
            }
            .frame(height: 5)
        }
    }
}

private struct ProgressTimelineRow: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let photo: ProgressPhoto
    let selected: Bool
    let action: () -> Void
    @State private var thumbnailURL: URL?

    var body: some View {
        Button(action: action) {
            GlassCard(radius: 23, padding: 12) {
                HStack(spacing: 13) {
                    AsyncImage(url: thumbnailURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            ZStack {
                                APEXColor.violet.opacity(0.1)
                                Image(systemName: "lock.fill").foregroundStyle(APEXColor.violet)
                            }
                        }
                    }
                    .frame(width: 62, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.dateKey(photo.localDate))
                            .font(APEXFont.display(17))
                        Text("\(language.text(photo.pose.capitalized)) · \(photo.note.isEmpty ? language.text("Private checkpoint") : photo.note)")
                            .font(APEXFont.body(12, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(selected ? APEXColor.violet : APEXColor.secondaryInk.opacity(0.4))
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: photo.thumbnailPath) {
            thumbnailURL = try? await session.signedProgressURL(for: photo, thumbnail: true)
        }
    }
}

private struct RemoteProgressImageCard: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let photo: ProgressPhoto
    let title: String
    let includeStats: Bool
    let snapshot: RPGSnapshot?
    let compact: Bool
    @State private var imageURL: URL?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: imageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else if phase.error != nil {
                    ContentUnavailableView("Preview unavailable", systemImage: "photo.badge.exclamationmark")
                } else {
                    ZStack {
                        APEXColor.violet.opacity(0.1)
                        ProgressView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: compact ? 4 : 7) {
                Text(language.text(title).uppercased(with: language.language.locale))
                    .font(APEXFont.mono(compact ? 8 : 11))
                    .tracking(1.2)
                Text(language.dateKey(photo.localDate))
                    .font(APEXFont.mono(compact ? 7 : 9))
                    .opacity(0.82)
                if includeStats {
                    miniBar("FITNESS", snapshot?.overall ?? 0, APEXColor.violet)
                    miniBar("HEALTH", snapshot?.health ?? 0, APEXColor.green)
                    miniBar("JOINTS", snapshot?.joint ?? 0, APEXColor.amber)
                    miniBar("ENDURANCE", snapshot?.endurance ?? 0, APEXColor.cyan)
                }
            }
            .foregroundStyle(.white)
            .padding(compact ? 10 : 16)
            .frame(maxWidth: compact ? 150 : 225, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 330 : 470)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 24 : 34, style: .continuous))
        .task(id: photo.storagePath) {
            imageURL = try? await session.signedProgressURL(for: photo, thumbnail: false)
        }
    }

    private func miniBar(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(language.format("%@ %d", language.text(title), Int(value.rounded())))
                .font(APEXFont.mono(compact ? 6 : 8))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(color).frame(width: proxy.size.width * min(max(value / 100, 0), 1))
                }
            }
            .frame(height: compact ? 3 : 5)
        }
    }
}

private enum VisualProgressError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "APEX could not prepare this photo without losing quality."
    }
}

private extension UIImage {
    func apexNormalized(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        let scale = min(1, maxDimension / max(largest, 1))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

private struct ProgressCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var image: UIImage?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProgressCameraPicker
        init(parent: ProgressCameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
