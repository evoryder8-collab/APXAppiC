import Foundation

/*
 * Seed definitions carry a version, and an account created before a bump
 * needs its programme, meals and supplements repaired to the current one.
 *
 * Constantine's V7 -> V8 programme delivery is handled by
 * BespokeProgrammeUpgrade using a manifest generated from src/data/seed.ts.
 * Other legacy repairs remain web-owned; a native release must not mistake
 * an old account version for a successfully installed programme.
 */
enum SeedVersion {
    /// Mirrors CURRENT_SEED_VERSION in src/lib/seedRepair.ts.
    static let current = 8

    enum State: Equatable, Sendable {
        case current
        case behind(stored: Int)
        case unknown

        var needsRepair: Bool {
            switch self {
            case .current: false
            case .behind, .unknown: true
            }
        }
    }

    static func state(of profile: Profile?) -> State {
        guard let profile else { return .unknown }
        return profile.seedVersion >= current ? .current : .behind(stored: profile.seedVersion)
    }

    /// Shown when a plan on screen may not be the current one.
    static func notice(for state: State) -> String? {
        switch state {
        case .current:
            nil
        case .behind, .unknown:
            "Your programme and meal definitions are from an earlier release. Open APEX on the web once to bring them up to date; your logged history is untouched."
        }
    }
}
