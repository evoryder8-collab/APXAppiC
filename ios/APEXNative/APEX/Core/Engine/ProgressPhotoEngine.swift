import Foundation

/*
 * Port of the portable half of src/lib/progressPhoto.ts and
 * src/lib/progressComparison.ts.
 *
 * The web modules mix logic with browser rendering: canvas resizing, image
 * decoding and poster drawing. Those are not ported, because iOS has native
 * equivalents and a canvas port would be a worse version of Core Graphics.
 * What is ported is everything that decides an outcome rather than a pixel:
 * crop geometry, comparison framing, pose selection, storage paths, and the
 * strength delta between two photo dates.
 */
enum ProgressPhotoEngine {
    enum FramingMode: String, Sendable, CaseIterable {
        case full, torso, free
    }

    struct NormalizedCrop: Hashable, Sendable {
        let x: Double
        let y: Double
        let scale: Double
    }

    struct ComparisonView: Hashable, Sendable {
        var scale: Double
        var x: Double
        var y: Double
    }

    struct ComparisonViews: Hashable, Sendable {
        var left: ComparisonView
        var right: ComparisonView
    }

    enum Side: Sendable { case left, right }

    struct CoverCrop: Hashable, Sendable {
        let sx: Double
        let sy: Double
        let width: Double
        let height: Double
    }

    struct Fitted: Hashable, Sendable {
        let width: Int
        let height: Int
        let scale: Double
    }

    /// Largest size inside the bounds without ever enlarging the source.
    static func fitWithin(width: Double, height: Double, maxWidth: Double, maxHeight: Double) -> Fitted? {
        guard width > 0, height > 0 else { return nil }
        let scale = min(1, maxWidth / width, maxHeight / height)
        return Fitted(
            width: max(1, Int((width * scale).rounded())),
            height: max(1, Int((height * scale).rounded())),
            scale: scale
        )
    }

    static func normalizeCrop(x: Double, y: Double, scale: Double) -> NormalizedCrop {
        NormalizedCrop(
            x: max(0, min(1, x.isFinite ? x : 0.5)),
            y: max(0, min(1, y.isFinite ? y : 0.5)),
            scale: max(1, min(3, scale.isFinite ? scale : 1))
        )
    }

    /* Panning is only allowed once zoomed in, and the further in, the further
       it may travel, so a photo can never be dragged off its own frame. */
    static func normalizeComparisonView(_ view: ComparisonView) -> ComparisonView {
        let scale = max(1, min(4, view.scale.isFinite ? view.scale : 1))
        let limit = scale == 1 ? 0 : min(42, (scale - 1) * 22)
        if limit == 0 { return ComparisonView(scale: scale, x: 0, y: 0) }
        return ComparisonView(
            scale: scale,
            x: max(-limit, min(limit, view.x.isFinite ? view.x : 0)),
            y: max(-limit, min(limit, view.y.isFinite ? view.y : 0))
        )
    }

    static func zoom(_ view: ComparisonView, by delta: Double) -> ComparisonView {
        var next = view
        next.scale = view.scale + delta
        return normalizeComparisonView(next)
    }

    /// Synced panning moves both photos together, which is what makes a
    /// side-by-side actually comparable.
    static func updateViews(
        _ views: ComparisonViews,
        side: Side,
        view: ComparisonView,
        synced: Bool
    ) -> ComparisonViews {
        let normalized = normalizeComparisonView(view)
        if synced { return ComparisonViews(left: normalized, right: normalized) }
        var next = views
        switch side {
        case .left: next.left = normalized
        case .right: next.right = normalized
        }
        return next
    }

    /* The source rectangle matching an object-cover preview, so the saved
       image is the one the user aligned against on screen. */
    static func coverCrop(width: Double, height: Double, targetAspectRatio: Double) -> CoverCrop? {
        guard width > 0, height > 0, targetAspectRatio.isFinite, targetAspectRatio > 0 else { return nil }
        let sourceRatio = width / height
        if sourceRatio > targetAspectRatio {
            let cropWidth = height * targetAspectRatio
            return CoverCrop(sx: (width - cropWidth) / 2, sy: 0, width: cropWidth, height: height)
        }
        let cropHeight = width / targetAspectRatio
        return CoverCrop(sx: 0, sy: (height - cropHeight) / 2, width: width, height: cropHeight)
    }

    /// The narrower of the two, so neither photo is cropped to fit the other.
    static func comparisonAspectRatio(_ a: ProgressPhoto, _ b: ProgressPhoto) -> Double {
        let ratios = [a.aspectRatio, b.aspectRatio].filter { $0.isFinite && $0 > 0 }
        return ratios.min() ?? (2.0 / 3.0)
    }

    /* Framing is read out of the idempotency key. The web type declares a
       framing_mode column, but production has never had one, so the key
       encoding is what every existing photo actually carries. */
    static func framingMode(_ photo: ProgressPhoto) -> FramingMode {
        framingMode(idempotencyKey: photo.clientIdempotencyKey)
    }

    static func framingMode(idempotencyKey key: String) -> FramingMode {
        guard key.range(of: "^framing:(full|torso|free):", options: [.regularExpression, .caseInsensitive]) != nil
        else { return .full }
        let encoded = key.split(separator: ":").dropFirst().first.map { String($0).lowercased() }
        if encoded == "torso" { return .torso }
        if encoded == "free" { return .free }
        return .full
    }

    static func idempotencyKey(_ mode: FramingMode, id: UUID = UUID()) -> String {
        "framing:\(mode.rawValue):\(id.uuidString.lowercased())"
    }

    /* Full and free keep the camera preview crop from before framing modes
       existed. Torso deliberately saves a wider 4:5 source, for room around
       the shoulders and arms in a side-by-side. */
    static func captureAspectRatio(_ mode: FramingMode, previewAspectRatio: Double) -> Double {
        mode == .torso ? 4.0 / 5.0 : previewAspectRatio
    }

    /* Parity: formatProgressPhotoMoment. "19 Aug 2026 at 06:37", from the
       capture timestamp, falling back to midday on the local date when that
       timestamp is unreadable. A raw ISO date is not a moment. */
    static func moment(_ photo: ProgressPhoto, language: AppLanguage) -> String {
        let locale: Locale
        switch language {
        case .romanian: locale = Locale(identifier: "ro_RO")
        case .thai: locale = Locale(identifier: "th_TH")
        case .english: locale = Locale(identifier: "en_GB")
        default: locale = Locale(identifier: "en_GB")
        }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let captured = parser.date(from: photo.capturedAt)
            ?? ISO8601DateFormatter().date(from: photo.capturedAt)
            ?? APEXDateMath.date(from: photo.localDate)
        guard let captured else { return photo.localDate }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy HH:mm")
        return formatter.string(from: captured)
    }

    static func daysBetween(_ a: ProgressPhoto, _ b: ProgressPhoto) -> Int {
        guard let first = APEXDateMath.date(from: a.localDate),
              let second = APEXDateMath.date(from: b.localDate) else { return 0 }
        return Int((abs(second.timeIntervalSince(first)) / 86_400).rounded())
    }

    /// Same pose first, then most recent: the comparison a person means.
    static func preferSamePose(reference: ProgressPhoto, photos: [ProgressPhoto]) -> [ProgressPhoto] {
        photos.sorted { left, right in
            let leftMatches = left.pose == reference.pose
            let rightMatches = right.pose == reference.pose
            if leftMatches != rightMatches { return leftMatches }
            return left.localDate > right.localDate
        }
    }

    /* A comparison must never borrow a future score for an older photo: use
       the latest snapshot at or before capture, or report no history. */
    static func snapshot(for date: String, snapshots: [RPGSnapshot]) -> RPGSnapshot? {
        snapshots.filter { $0.date <= date }.max { $0.date < $1.date }
    }

    /// Must match the web byte for byte or the two clients write a photo to
    /// different places and neither can find the other's.
    static func storagePaths(userID: UUID, photoID: UUID) -> (full: String, thumbnail: String)? {
        let owner = userID.uuidString.lowercased()
        let photo = photoID.uuidString.lowercased()
        guard isSafePathPart(owner), isSafePathPart(photo) else { return nil }
        return ("\(owner)/\(photo)/photo.webp", "\(owner)/\(photo)/thumbnail.webp")
    }

    private static func isSafePathPart(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil
    }
}
