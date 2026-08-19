import Foundation

/*
 * Seed definitions carry a version, and an account created before a bump
 * needs its programme, meals and supplements repaired to the current one.
 *
 * The repair itself is deliberately NOT ported. It is driven entirely by
 * src/data/seed.ts, the authored programmes for each persona, so porting the
 * logic without that data would repair nothing, and porting the data too
 * would duplicate roughly twelve hundred lines whose only job is to be
 * identical on both sides. Worse, the web already writes its repair back to
 * Supabase, definition rows first and the version marker last, precisely so
 * a second device can resume an interrupted one. A second implementation
 * racing the first is a way to corrupt that, not a way to help.
 *
 * What native owes the user is honesty: notice that definitions are behind,
 * say so, and never present a stale plan as if it were current.
 */
enum SeedVersion {
    /// Mirrors CURRENT_SEED_VERSION in src/lib/seedRepair.ts.
    static let current = 7

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
