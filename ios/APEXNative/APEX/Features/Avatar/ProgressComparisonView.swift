import SwiftUI
import UIKit

/*
 * The private comparison, matching the web's PhotoComparison.
 *
 * Two photos side by side, zoomed and panned together or apart, exported as
 * a single card. Synced is the default because moving both at once is what
 * makes a difference in the body visible rather than a difference in framing.
 */
struct ProgressComparisonView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var views = ProgressPhotoEngine.ComparisonViews(
        left: .init(scale: 1, x: 0, y: 0),
        right: .init(scale: 1, x: 0, y: 0)
    )
    @State private var synced = true
    @State private var exported: URL?
    @State private var isExporting = false

    let before: ProgressPhoto
    let after: ProgressPhoto
    var onClose: () -> Void

    /* The screen loads its own photos. Passing them in was how it ended up
       showing two black panels with an export button that had nothing to
       export. */
    @State private var beforeImage: UIImage?
    @State private var afterImage: UIImage?
    @State private var loadFailed = false

    private var daysApart: Int { ProgressPhotoEngine.daysBetween(before, after) }

    private var workoutsBetween: Int {
        let from = min(before.localDate, after.localDate)
        let to = max(before.localDate, after.localDate)
        return session.data.workoutSessions.filter {
            $0.completed && $0.date >= from && $0.date <= to
        }.count
    }

    private var exportMode: ProgressComparison.ExportMode {
        ProgressComparison.resolveExportMode(session.data.settings?.addons["comparison_export_mode"])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                pair
                controls
                exportCard
            }
            .padding(18)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(item: $exported) { url in
            ShareSheet(items: [url])
        }
        .task(id: before.id) { beforeImage = await load(before) }
        .task(id: after.id) { afterImage = await load(after) }
    }

    private func load(_ photo: ProgressPhoto) async -> UIImage? {
        guard let url = try? await session.signedProgressURL(for: photo, thumbnail: false),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else {
            loadFailed = true
            return nil
        }
        return image
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text("PRIVATE COMPARISON").uppercased())
                    .font(APEXFont.mono(9))
                    .tracking(1.6)
                    .foregroundStyle(Color(red: 0.77, green: 0.71, blue: 0.99))
                Text(language.format("%d days apart", daysApart))
                    .font(APEXFont.display(24))
                    .foregroundStyle(.white)
                Text(language.format("%d completed workouts between", workoutsBetween))
                    .font(APEXFont.body(11))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Button(language.text("Close"), action: onClose)
                .font(APEXFont.body(14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 42)
                .background(.white.opacity(0.12), in: Capsule())
                .buttonStyle(.plain)
        }
    }

    private var pair: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                panel(
                    image: beforeImage, photo: before,
                    label: language.text("BEFORE"), side: .left,
                    width: (proxy.size.width - 2) / 2
                )
                panel(
                    image: afterImage, photo: after,
                    label: language.text("AFTER"), side: .right,
                    width: (proxy.size.width - 2) / 2
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .aspectRatio(
            /* The narrower of the two, so neither photo is cropped to fit. */
            ProgressPhotoEngine.comparisonAspectRatio(before, after) * 2,
            contentMode: .fit
        )
    }

    private func panel(
        image: UIImage?,
        photo: ProgressPhoto,
        label: String,
        side: ProgressPhotoEngine.Side,
        width: CGFloat
    ) -> some View {
        let view = side == .left ? views.left : views.right
        return ZStack(alignment: .top) {
            Color.white.opacity(0.04)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(view.scale)
                    .offset(x: view.x, y: view.y)
            } else if loadFailed {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 26, weight: .light))
                    Text(language.text("Preview unavailable"))
                        .font(APEXFont.body(10, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.4))
            } else {
                ProgressView().tint(.white.opacity(0.6))
            }
            HStack {
                if side == .right { Spacer() }
                VStack(alignment: side == .left ? .leading : .trailing, spacing: 2) {
                    Text(label)
                        .font(APEXFont.mono(10, weight: .bold))
                        .tracking(1.2)
                    Text(momentText(photo))
                        .font(APEXFont.mono(8))
                        .opacity(0.75)
                }
                .foregroundStyle(.white)
                .shadow(radius: 6)
                if side == .left { Spacer() }
            }
            .padding(10)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    var next = side == .left ? views.left : views.right
                    next.x += value.translation.width / 40
                    next.y += value.translation.height / 40
                    views = ProgressPhotoEngine.updateViews(views, side: side, view: next, synced: synced)
                }
        )
        .clipped()
    }

    private func momentText(_ photo: ProgressPhoto) -> String {
        let pose = language.text(photo.pose.capitalized)
        return "\(photo.localDate) · \(pose)"
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { zoom(-0.25) } label: { zoomGlyph("minus") }
                Text("\(Int(views.left.scale * 100))%")
                    .font(APEXFont.mono(13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 62)
                Button { zoom(0.25) } label: { zoomGlyph("plus") }
                Spacer()
                syncToggle
            }
            .padding(12)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(language.text("Drag to inspect. Synced moves both photos together; Unlocked edits the side you touch."))
                .font(APEXFont.body(10))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
    }

    private func zoomGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 40)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var syncToggle: some View {
        HStack(spacing: 3) {
            ForEach([true, false], id: \.self) { value in
                Button { synced = value } label: {
                    Text(language.text(value ? "SYNCED" : "UNLOCKED"))
                        .font(APEXFont.mono(9, weight: .bold))
                        .foregroundStyle(synced == value ? .white : .white.opacity(0.55))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(
                            synced == value ? AnyShapeStyle(APEXColor.violet.gradient) : AnyShapeStyle(.clear),
                            in: Capsule()
                        )
                }
            }
        }
        .padding(3)
        .background(.white.opacity(0.08), in: Capsule())
    }

    private var exportCard: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text("SHAREABLE PROGRESS CARD").uppercased())
                    .font(APEXFont.mono(9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                Text(language.text("Your current zoom and positioning are preserved in the high-resolution PNG."))
                    .font(APEXFont.body(10))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: export) {
                Text(language.text(isExporting ? "Exporting…" : "Export PNG"))
                    .font(APEXFont.body(13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: [APEXColor.violet, APEXColor.cyan],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
            .accessibilityIdentifier("comparison-export")
        }
        .padding(15)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.1))
        )
    }

    private func zoom(_ delta: Double) {
        let next = ProgressPhotoEngine.zoom(views.left, by: delta)
        views = ProgressPhotoEngine.updateViews(views, side: .left, view: next, synced: true)
    }

    private func export() {
        /* Silence was the bug: the button did nothing when the photos had not
           loaded, with no way to tell that from a failed export. */
        guard let beforeImage, let afterImage else {
            loadFailed = true
            return
        }
        isExporting = true
        Task {
            let card = ProgressPosterRenderer.render(
                before: beforeImage, after: afterImage,
                beforeMoment: momentText(before), afterMoment: momentText(after),
                views: views,
                content: ProgressComparison.posterContent(exportMode),
                daysApart: daysApart, workouts: workoutsBetween
            )
            exported = ProgressPosterRenderer.write(card)
            isExporting = false
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
