import PhotosUI
import SwiftUI

/// Two photos chosen to compare, oldest first so BEFORE really is before.
private struct ProgressComparisonPair: Identifiable {
    let before: ProgressPhoto
    let after: ProgressPhoto
    var id: [UUID] { [before.id, after.id] }
}

struct VisualProgressView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var includeStats = true
    @State private var showCamera = false
    @State private var pose = "front"
    @State private var note = ""
    @State private var capturedWeightKG: Double?
    @State private var capturedFraming = ProgressPhotoEngine.FramingMode.full
    /// When an imported photo was taken. Nil for a photo taken just now.
    @State private var capturedDate: Date?
    @State private var isSaving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var saveOperationID: UUID?
    @State private var saveError: String?
    @State private var comparisonSelection: [UUID] = []
    /* The capture flow, in the order the web runs it: brief, frame, save. */
    @State private var showBriefing = false
    @State private var captureIntent: ProgressCaptureIntent?
    @State private var captureOperation: AccountOperationLease?
    @State private var captureRequestID: UUID?
    /// The pair on the comparison screen. It holds its own two photos, so the
    /// screen cannot open with nothing to show, or be emptied by the timeline
    /// reloading underneath it.
    @State private var comparing: ProgressComparisonPair?
    @State private var preparationTask: Task<Void, Never>?
    @State private var preparationID: UUID?
    /// Older photos loaded as the timeline is scrolled, beyond the first page.
    @State private var earlierPhotos: [ProgressPhoto] = []
    @State private var reachedFirstPhoto = false

    /// Every photo loaded so far, newest first.
    private var photos: [ProgressPhoto] {
        ProgressPhotoEngine.timeline(session.data.progressPhotos, earlier: earlierPhotos)
    }

    /// Replaces the server's answer for older photos, for layout checks.
    var loadEarlier: (([ProgressPhoto]) async throws -> (photos: [ProgressPhoto], reachedEnd: Bool))?

    /// Opens straight on the review of a photo already in hand, or with
    /// photos already ticked for comparison.
    init(
        reviewing image: UIImage? = nil,
        ticked: [UUID] = [],
        loadEarlier: (([ProgressPhoto]) async throws -> (photos: [ProgressPhoto], reachedEnd: Bool))? = nil
    ) {
        _selectedImage = State(initialValue: image)
        _comparisonSelection = State(initialValue: ticked)
        self.loadEarlier = loadEarlier
    }

    /// The two ticked photos, once both are on the timeline.
    private var comparisonPair: ProgressComparisonPair? {
        let chosen = comparisonSelection.compactMap { id in
            photos.first { $0.id == id }
        }
        guard chosen.count == 2 else { return nil }
        let ordered = chosen.sorted { $0.localDate < $1.localDate }
        return ProgressComparisonPair(before: ordered[0], after: ordered[1])
    }

    /// SwiftUI writes `nil` through the presentation binding for system and
    /// interactive dismissals. Revoke the account-bound request in that same
    /// turn, before an in-flight camera delegate can publish its image.
    private var capturePresentation: Binding<ProgressCaptureIntent?> {
        Binding(
            get: { captureIntent },
            set: { intent in
                captureIntent = intent
                if intent == nil {
                    revokeCapturePresentation()
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(language.text("Private Visual Progress"), systemImage: "camera.fill")
                        .font(APEXFont.display(31))
                    Text(language.text("Your photos remain private. Compare your physique and the performance signals behind it."))
                        .font(APEXFont.body(14, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let selectedImage {
                    ProgressImageCard(image: selectedImage, title: "New capture", includeStats: includeStats, snapshot: session.data.snapshots.max { $0.date < $1.date })
                    GlassCard(radius: 29, padding: 19) {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("Pose", selection: $pose) {
                                Text(language.text("Front")).tag("front")
                                Text(language.text("Side")).tag("side")
                                Text(language.text("Back")).tag("back")
                            }
                            .pickerStyle(.segmented)
                            TextField(language.text("Optional note"), text: $note, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                            HStack(spacing: 10) {
                                Button(language.text("Retake")) { self.selectedImage = nil }
                                    .buttonStyle(.bordered)
                                    .layoutFrame("retake")
                                Button {
                                    guard let operation = session.accountOperationLease() else { return }
                                    let requestID = UUID()
                                    saveTask?.cancel()
                                    saveOperationID = requestID
                                    isSaving = true
                                    saveTask = Task {
                                        await save(selectedImage, operation: operation, requestID: requestID)
                                    }
                                } label: {
                                    if isSaving { ProgressView().tint(.white) }
                                    else { Label(language.text("Save private checkpoint"), systemImage: "lock.fill") }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(APEXColor.violet)
                                .disabled(isSaving)
                                .layoutFrame("save")
                            }
                        }
                    }
                } else {
                    GlassCard(radius: 34, padding: 24) {
                        VStack(spacing: 18) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 55, weight: .light))
                                .foregroundStyle(APEXColor.violet)
                            Text(language.text("Create a new checkpoint"))
                                .font(APEXFont.display(23))
                            Text(language.text("Use the same pose, distance and lighting for the clearest comparison."))
                                .font(APEXFont.body(13, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .multilineTextAlignment(.center)
                            HStack {
                                Button {
                                    guard let operation = session.accountOperationLease() else { return }
                                    captureRequestID = UUID()
                                    captureOperation = operation
                                    showBriefing = true
                                } label: {
                                    Label(language.text("Take progress photo"), systemImage: "camera.fill")
                                }
                                .accessibilityIdentifier("progress-take-photo")
                                .buttonStyle(.borderedProminent)
                                .tint(APEXColor.violet)
                                PhotosPicker(selection: $selectedItem, matching: .images) {
                                    Label(language.text("Library"), systemImage: "photo")
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
                            Text(language.text("Include stats"))
                                .font(APEXFont.display(18))
                            Text(language.text("Overlay compact performance bars on comparison photos"))
                                .font(APEXFont.body(11, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                    }
                    .tint(APEXColor.violet)
                }

                if let pair = comparisonPair {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(language.text("Before and after"))
                                .font(APEXFont.display(25))
                            Spacer()
                            Button(language.text("Compare")) { comparing = pair }
                                .font(APEXFont.body(12, weight: .bold))
                                .foregroundStyle(APEXColor.violet)
                                .accessibilityIdentifier("progress-compare")
                                .layoutFrame("compare")
                            Button(language.text("Clear")) { comparisonSelection = [] }
                                .font(APEXFont.body(12, weight: .bold))
                        }
                        HStack(spacing: 10) {
                            ForEach([pair.before, pair.after]) { photo in
                                RemoteProgressImageCard(
                                    photo: photo,
                                    title: photo.id == pair.before.id ? "Before" : "After",
                                    includeStats: includeStats,
                                    snapshot: snapshot(for: photo),
                                    compact: true
                                )
                            }
                        }
                    }
                }

                if photos.isEmpty {
                    GlassCard(radius: 29, padding: 20) {
                        VStack(spacing: 9) {
                            Text(language.text("No synced checkpoints yet"))
                                .font(APEXFont.display(20))
                            Text(language.text("Your existing web progress photos will appear here as soon as their private signed previews are loaded."))
                                .font(APEXFont.body(12, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    /* Lazy, so the end of the list is only reached by
                       scrolling to it, and that is what asks for older photos. */
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text(language.text("Timeline"))
                            .font(APEXFont.display(25))
                        Text(language.text("Select any two checkpoints to compare them."))
                            .font(APEXFont.body(12, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                        ForEach(photos) { photo in
                            ProgressTimelineRow(
                                photo: photo,
                                selected: comparisonSelection.contains(photo.id)
                            ) {
                                toggleComparison(photo.id)
                            }
                            .layoutFrame("timelineRow \(photo.id)")
                        }
                        if !reachedFirstPhoto, photos.count >= ProgressPhotoEngine.pageSize {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .task(id: photos.count) { await loadEarlierPhotos() }
                        }
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 28)
.dockClearance()
        }
        .navigationTitle(language.text("Visual Progress"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedItem) { _, item in
            preparationTask?.cancel()
            guard let item,
                  let operation = session.accountOperationLease() else {
                preparationTask = nil
                preparationID = nil
                return
            }
            let requestID = UUID()
            preparationID = requestID
            preparationTask = Task {
                await prepareSelectedImage(
                    item,
                    operation: operation,
                    requestID: requestID
                )
            }
        }
        .onChange(of: ProgressPhotoEngine.firstPageReach(session.data.progressPhotos)) { _, _ in
            reloadEarlierPhotos()
        }
        .onChange(of: session.data.progressPhotos.map(\.id)) { before, _ in
            /* A photo that has left the first page and is not among the
               older ones may still be on the server. An old photo imported
               here is added to the first page in memory, and the refresh
               that follows keeps only the newest. The older pages were
               loaded without it, so they load again. */
            let shown = Set(photos.map(\.id))
            if before.contains(where: { !shown.contains($0) }) { reloadEarlierPhotos() }
        }
        .onChange(of: session.profile?.userID) { _, _ in
            preparationTask?.cancel()
            preparationTask = nil
            preparationID = nil
            saveTask?.cancel()
            saveTask = nil
            saveOperationID = nil
            isSaving = false
            selectedItem = nil
            selectedImage = nil
            note = ""
            capturedWeightKG = nil
            earlierPhotos = []
            reachedFirstPhoto = false
            saveError = nil
            showBriefing = false
            captureIntent = nil
            captureOperation = nil
            captureRequestID = nil
            comparing = nil
            comparisonSelection = []
            showCamera = false
        }
        /* A card, not a screen: the briefing is four rules and two choices. */
        .apexPopover(isPresented: $showBriefing) {
            ProgressCaptureBriefing(
                initial: ProgressCaptureIntent(pose: pose),
                onCancel: {
                    showBriefing = false
                    captureOperation = nil
                    captureRequestID = nil
                },
                onConfirm: { intent in
                    guard let operation = captureOperation,
                          captureRequestID != nil,
                          session.accountOperationIsCurrent(operation) else {
                        showBriefing = false
                        captureOperation = nil
                        captureRequestID = nil
                        return
                    }
                    showBriefing = false
                    pose = intent.pose
                    note = intent.note
                    captureIntent = intent
                }
            )
        }
        .fullScreenCover(item: capturePresentation, onDismiss: revokeCapturePresentation) { intent in
            if let operation = captureOperation,
               let requestID = captureRequestID,
               session.accountOperationIsCurrent(operation) {
                ProgressCameraView(
                    intent: intent,
                    photos: photos,
                    operation: operation,
                    onClose: {
                        guard captureRequestID == requestID else { return }
                        captureIntent = nil
                        captureOperation = nil
                        captureRequestID = nil
                    },
                    onCaptured: { image, resolved, takenAt in
                        guard captureRequestID == requestID,
                              captureOperation == operation,
                              session.accountOperationIsCurrent(operation) else {
                            if captureRequestID == requestID {
                                captureIntent = nil
                                captureOperation = nil
                                captureRequestID = nil
                            }
                            return
                        }
                        selectedImage = image
                        pose = resolved.pose
                        note = resolved.note
                        capturedWeightKG = resolved.resolvedWeightKG
                        capturedFraming = resolved.framing
                        capturedDate = takenAt
                        captureIntent = nil
                        captureOperation = nil
                        captureRequestID = nil
                    }
                )
            }
        }
        .fullScreenCover(item: $comparing) { pair in
            ProgressComparisonView(
                before: pair.before, after: pair.after,
                includeStats: includeStats,
                onClose: { comparing = nil }
            )
            .environment(session)
        }
        .sheet(isPresented: $showCamera) {
            ProgressCameraPicker(image: $selectedImage)
                .ignoresSafeArea()
        }
        .alert("Could not save checkpoint", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button(language.text("OK"), role: .cancel) {}
        } message: {
            Text(language.text(saveError ?? "Please try again."))
        }
    }

    private func revokeCapturePresentation() {
        captureIntent = nil
        captureOperation = nil
        captureRequestID = nil
    }

    /* The first page ends somewhere else now, so the older pages no longer
       join onto it. They load again from where it ends. A tick on a photo
       that leaves with them goes too: only a photo on the timeline can be
       compared. */
    private func reloadEarlierPhotos() {
        earlierPhotos = []
        reachedFirstPhoto = false
        comparisonSelection.removeAll { id in
            !session.data.progressPhotos.contains { $0.id == id }
        }
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
    private func loadEarlierPhotos() async {
        guard let operation = session.accountOperationLease() else { return }
        do {
            while !Task.isCancelled {
                let reach = ProgressPhotoEngine.firstPageReach(session.data.progressPhotos)
                let asked = earlierPhotos
                let page: (photos: [ProgressPhoto], reachedEnd: Bool)
                if let loadEarlier {
                    page = try await loadEarlier(asked)
                } else {
                    page = try await session.earlierProgressPhotos(after: asked, operation: operation)
                }
                guard session.accountOperationIsCurrent(operation) else { return }
                /* A page is what comes after the photos loaded when it was
                   asked for. If those have changed since, it would leave a
                   hole where it no longer joins on, so it is asked again. */
                guard asked == earlierPhotos,
                      reach == ProgressPhotoEngine.firstPageReach(session.data.progressPhotos) else { continue }
                earlierPhotos = ProgressPhotoEngine.timeline(earlierPhotos, earlier: page.photos)
                reachedFirstPhoto = page.reachedEnd
                return
            }
        } catch {
            /* Asked again the next time the end of the list scrolls into view. */
        }
    }

    @MainActor
    private func prepareSelectedImage(
        _ item: PhotosPickerItem,
        operation: AccountOperationLease,
        requestID: UUID
    ) async {
        defer {
            if preparationID == requestID {
                preparationTask = nil
            }
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  preparationID == requestID,
                  session.accountOperationIsCurrent(operation),
                  let image = UIImage(data: data) else { return }
            selectedImage = image
            capturedWeightKG = nil
            capturedFraming = .full
            capturedDate = ProgressPhotoEngine.takenAt(imageData: data)
        } catch is CancellationError {
            return
        } catch {
            /* A PhotosPicker read failure leaves the capture empty, matching the
               prior behavior. Most importantly, an old owner's failure does not
               publish an alert or any prepared state into the new account. */
            guard preparationID == requestID,
                  session.accountOperationIsCurrent(operation) else { return }
        }
    }

    @MainActor
    private func save(
        _ image: UIImage,
        operation: AccountOperationLease,
        requestID: UUID
    ) async {
        defer {
            if saveOperationID == requestID {
                isSaving = false
                saveTask = nil
            }
        }
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
                framing: capturedFraming,
                note: note,
                weightKG: capturedWeightKG,
                date: capturedDate ?? .now,
                operation: operation
            )
            guard saveOperationID == requestID,
                  session.accountOperationIsCurrent(operation) else { return }
            selectedImage = nil
            note = ""
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch is CancellationError {
            return
        } catch {
            guard saveOperationID == requestID,
                  session.accountOperationIsCurrent(operation) else { return }
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
            /* Over a layer the width of the page, so a square or landscape
               photo is cropped by the card rather than widening the page. */
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.68)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 9) {
                Text(language.text(title).uppercased(with: language.language.locale))
                    .font(APEXFont.mono(11))
                    .tracking(1.5)
                if includeStats, let snapshot {
                    compactBar("OVERALL", snapshot.overall, APEXColor.violet)
                    compactBar("HEALTH", snapshot.health, APEXColor.green)
                    compactBar("JOINTS", snapshot.joint, APEXColor.amber)
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: 230, alignment: .leading)
        }
        .frame(height: 470)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .layoutFrame("reviewCard")
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
            guard let operation = session.accountOperationLease() else {
                thumbnailURL = nil
                return
            }
            do {
                let url = try await session.signedProgressURL(
                    for: photo,
                    thumbnail: true,
                    operation: operation
                )
                guard session.accountOperationIsCurrent(operation) else { return }
                thumbnailURL = url
            } catch is CancellationError {
                return
            } catch {
                guard session.accountOperationIsCurrent(operation) else { return }
                thumbnailURL = nil
            }
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
                if includeStats, let snapshot {
                    miniBar("FITNESS", snapshot.overall, APEXColor.violet)
                    miniBar("HEALTH", snapshot.health, APEXColor.green)
                    miniBar("JOINTS", snapshot.joint, APEXColor.amber)
                    miniBar("ENDURANCE", snapshot.endurance, APEXColor.cyan)
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
            guard let operation = session.accountOperationLease() else {
                imageURL = nil
                return
            }
            do {
                let url = try await session.signedProgressURL(
                    for: photo,
                    thumbnail: false,
                    operation: operation
                )
                guard session.accountOperationIsCurrent(operation) else { return }
                imageURL = url
            } catch is CancellationError {
                return
            } catch {
                guard session.accountOperationIsCurrent(operation) else { return }
                imageURL = nil
            }
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
        "FITR MAX could not prepare this photo without losing quality."
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
