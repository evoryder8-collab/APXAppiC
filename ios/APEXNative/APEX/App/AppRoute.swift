import Foundation

enum AppRoute: Equatable {
    case launching
    /// The commercial front door: what a new install opens to.
    case welcome
    case emailAuth(signUp: Bool)
    /// A brand-new account answers these before anything is generated for it.
    case induction
    case consent
    case persona
    case login(Persona)
    case portal
}

enum PortalDestination: Hashable {
    case nutrition
    case transition
    case mainPhase
    case customWorkouts
    case orbit
    case avatar
    case visualProgress
    case settings
    case coachWorkspace
    case coachPlan
    case coachWorkouts
}
