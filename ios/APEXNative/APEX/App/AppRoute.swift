import Foundation

enum AppRoute: Equatable {
    case launching
    case persona
    case login(Persona)
    case portal
}

enum PortalDestination: Hashable {
    case nutrition
    case transition
    case mainPhase
    case orbit
    case avatar
    case visualProgress
    case settings
}
