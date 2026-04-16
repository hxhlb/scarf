import Foundation

/// @Observable public facade for file-system change notifications.
/// SwiftUI views bind to `lastChangeDate` via `@Environment(HermesFileWatcher.self)`
/// and re-render `.onChange(of: fileWatcher.lastChangeDate)`.
///
/// Internally holds a `HermesFileWatching` impl: `LocalHermesFileWatcher` uses
/// `DispatchSourceFileSystemObject` for push-based events; `RemoteHermesFileWatcher`
/// polls on a fixed interval. The impl notifies via a `@Sendable` callback, which
/// the facade hops to `@MainActor` before bumping `lastChangeDate`.
@Observable
final class HermesFileWatcher {
    private(set) var lastChangeDate = Date()
    let impl: any HermesFileWatching

    init(connection: HermesConnection = ConnectionProvider.current) {
        switch connection {
        case .local:
            self.impl = LocalHermesFileWatcher()
        case .remote(let r):
            self.impl = RemoteHermesFileWatcher(
                remote: r,
                locator: RemoteHermesLocator.forRemote(r)
            )
        }
    }

    func startWatching() {
        impl.startWatching { [weak self] in
            Task { @MainActor [weak self] in
                self?.lastChangeDate = Date()
            }
        }
    }

    func stopWatching() {
        impl.stopWatching()
    }

    func updateProjectWatches(_ dashboardPaths: [String]) {
        impl.updateProjectWatches(dashboardPaths)
    }
}
