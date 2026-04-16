import Foundation
import os

/// Thread-safe ambient state holding the currently-active `HermesConnection`.
///
/// Service facades with no explicit `connection:` argument consult this, so
/// ViewModels that write `HermesDataService()` today automatically target
/// whichever Hermes the user selected — no VM migration required.
///
/// Ownership: only `AppCoordinator` writes here (via `bootstrapActiveConnection`
/// and `activeConnection.didSet`). Facades and VMs only read. Keeping the mutation
/// surface narrow means we don't need a full env-injection refactor just to make
/// in-session connection switching work.
enum ConnectionProvider {
    nonisolated static let state = OSAllocatedUnfairLock<HermesConnection>(initialState: .local)

    /// Snapshot of the active connection. Safe to call from any context.
    nonisolated static var current: HermesConnection {
        state.withLock { $0 }
    }

    /// Update the active connection. Callers MUST NOT call this directly —
    /// route through `AppCoordinator.activeConnection` so the `@Observable`
    /// property fires its downstream change notifications.
    nonisolated static func set(_ connection: HermesConnection) {
        state.withLock { $0 = connection }
    }
}
