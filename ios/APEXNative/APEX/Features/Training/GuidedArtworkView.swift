import SwiftUI

/// The two photos show endpoints. The first travel direction and the position of
/// the prescribed hold belong to the movement, independent of the file order.
struct GuidedPoseCadence: Decodable {
    enum Phase: String, Decodable { case eccentric, concentric }
    enum Hold: String, Decodable { case eccentric, concentric, mid }

    let first: Phase
    let pause: Hold

    struct Cue {
        let concentricOpacity: Double
        let label: String
    }

    func cue(for exercise: Exercise, elapsed: Double, reduceMotion: Bool) -> Cue? {
        guard GuidedWorkout.usesAutomaticCadence(for: exercise),
              exercise.tempoDown > 0, exercise.tempoUp > 0,
              exercise.tempoPause >= 0, elapsed.isFinite,
              exercise.tempoPause == 0 || pause != .mid else { return nil }

        let duration = PlayerTimeline.repDuration(exercise)
        // The counter allows a final fraction of a second to finish the set.
        // Keep the last endpoint visible until the player actually advances.
        let finished = PlayerTimeline.repTarget(exercise).map {
            elapsed >= Double($0) * duration
        } ?? false
        var time = finished ? duration : max(0, elapsed).truncatingRemainder(dividingBy: duration)

        for phase in [first, first == .eccentric ? .concentric : .eccentric] {
            let isUp = phase == .concentric
            let travel = isUp ? exercise.tempoUp : exercise.tempoDown
            if time < travel {
                // Briefly dissolve into the target, then leave it clear for
                // the rest of the prescribed movement. No animation clock runs.
                let progress = min(1, time / min(0.42, travel))
                let mix = reduceMotion && time > 0 ? 1 : progress * progress * (3 - 2 * progress)
                return Cue(concentricOpacity: isUp ? mix : 1 - mix,
                           label: isUp ? "Concentric phase" : "Eccentric phase")
            }
            time -= travel
            if (isUp && pause == .concentric) || (!isUp && pause == .eccentric) {
                if time < exercise.tempoPause {
                    return Cue(concentricOpacity: isUp ? 1 : 0, label: "Hold")
                }
                time -= exercise.tempoPause
            }
        }
        return Cue(concentricOpacity: first == .eccentric ? 1 : 0, label: "Hold")
    }
}

enum GuidedArtwork {
    case reference(String)
    case pair(String, GuidedPoseCadence?)

    static let directory = "GuidedArtwork"

    private static let files = Dictionary(uniqueKeysWithValues: (Bundle.main.urls(
        forResourcesWithExtension: "webp", subdirectory: directory
    ) ?? []).map { ($0.deletingPathExtension().lastPathComponent, $0) })

    private static let cadence: [String: GuidedPoseCadence] = {
        guard let url = Bundle.main.url(forResource: "cadence", withExtension: "json", subdirectory: directory),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: GuidedPoseCadence].self, from: data)) ?? [:]
    }()

    static func movement(_ exercise: Exercise) -> Self? {
        guard let id = ExerciseCatalog.artworkMovementID(for: exercise) else { return nil }
        if files[id] != nil { return .reference(id) }
        guard files[id + "-1"] != nil, files[id + "-2"] != nil else { return nil }
        return .pair(id, cadence[id])
    }

    static var waterBreak: Self? { files["breaktime"] != nil ? .reference("breaktime") : nil }

    @MainActor private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 6
        return cache
    }()

    @MainActor static func image(_ stem: String) -> UIImage? {
        let key = stem as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let url = files[stem], let image = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }
}

struct GuidedArtworkView: View {
    let artwork: GuidedArtwork
    var exercise: Exercise?
    var elapsed: Double = 0
    var advancing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var language = LanguageState.shared

    private var cue: GuidedPoseCadence.Cue? {
        guard case .pair(_, let cadence) = artwork, let exercise else { return nil }
        return cadence?.cue(for: exercise, elapsed: elapsed, reduceMotion: reduceMotion)
    }

    var body: some View {
        let cue = cue
        Group {
            switch artwork {
            case .reference(let stem):
                photo(stem)
            case .pair(let stem, _):
                if let cue {
                    ZStack {
                        photo(stem + "-1").opacity(1 - cue.concentricOpacity)
                        photo(stem + "-2").opacity(cue.concentricOpacity)
                    }
                    .animation(advancing && !reduceMotion ? .linear(duration: 0.1) : nil, value: cue.concentricOpacity)
                    .id(advancing)
                } else {
                    HStack(spacing: 0) {
                        photo(stem + "-1")
                        photo(stem + "-2")
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(language.text(exercise?.name ?? "Water break"))
        .accessibilityValue(cue.map { language.text($0.label) } ?? "")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier(exercise == nil ? "workout-break-artwork" : "workout-movement-artwork")
    }

    @ViewBuilder
    private func photo(_ stem: String) -> some View {
        if let image = GuidedArtwork.image(stem) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The overview uses the player's bundled photographs without starting its cadence clock.
struct GuidedPreviewPhoto: View {
    let exercise: Exercise
    var height: CGFloat = 108

    var body: some View {
        if let artwork = GuidedArtwork.movement(exercise) {
            GuidedArtworkView(artwork: artwork)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .accessibilityHidden(true)
        }
    }
}

struct GuidedExerciseLineup: View {
    let exercises: [Exercise]
    let accent: Color
    let prescription: (Exercise) -> String
    @State private var language = LanguageState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text((index + 1).formatted(.number.precision(.integerLength(2...))))
                            .font(APEXFont.mono(12, weight: .bold))
                            .foregroundStyle(accent)
                        Text(language.text(exercise.name))
                            .font(APEXFont.body(16, weight: .bold))
                            .foregroundStyle(APEXColor.ink)
                            .accessibilityIdentifier("simple-training-exercise-\(exercise.id.uuidString.lowercased())")
                    }
                    Text(prescription(exercise))
                        .font(APEXFont.mono(12))
                        .foregroundStyle(APEXColor.secondaryInk)
                    GuidedPreviewPhoto(exercise: exercise, height: 150)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if index < exercises.count - 1 { Divider() }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("training-lineup-list")
    }
}
