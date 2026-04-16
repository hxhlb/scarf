import Foundation

/// Identifies which Hermes instance the app is currently bound to.
/// Hashable so SwiftUI's `.id(...)` modifier can pivot view identity on
/// connection switches — the view tree rebuilds whenever this value changes.
enum HermesConnection: Sendable, Equatable, Hashable {
    case local
    case remote(RemoteHermes)

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .remote(let r): return r.nickname
        }
    }

    var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }

    var remoteRecord: RemoteHermes? {
        if case .remote(let r) = self { return r }
        return nil
    }
}
