import Foundation

/// Polling `HermesFileWatching` for remote Hermes instances.
///
/// OpenSSH gives us no way to subscribe to FS events on the remote side, so this
/// watcher fires `onChange` on a fixed 3s interval while watching is active.
/// Upstream ViewModels reload on `lastChangeDate` changes, so the effect is
/// "fresh data every 3s" — coarser than local's push-based `DispatchSource`
/// updates but correct.
///
/// Each tick triggers one query per feature-view's subscription. With the Sessions
/// view open against a remote Hermes that's one `sqlite3 -json` query every 3s —
/// bounded, and acceptable for interactive use.
final class RemoteHermesFileWatcher: HermesFileWatching {
    nonisolated let locator: any HermesLocator
    private let queue = DispatchQueue(label: "com.scarf.remote-file-watcher")
    private var timer: DispatchSourceTimer?

    /// Matches the local watcher's 5s heartbeat plus a shorter sub-interval so
    /// the Scarf UI feels "near-live" on remote without flooding SSH.
    private static let pollInterval: TimeInterval = 3.0

    init(remote _: RemoteHermes, locator: any HermesLocator) {
        self.locator = locator
    }

    func startWatching(onChange: @escaping @Sendable () -> Void) {
        stopWatching()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Self.pollInterval, repeating: Self.pollInterval)
        t.setEventHandler {
            onChange()
        }
        t.resume()
        timer = t
    }

    func stopWatching() {
        timer?.cancel()
        timer = nil
    }

    func updateProjectWatches(_: [String]) {
        // No-op — the unconditional 3s poll already picks up dashboard-file changes
        // at the next tick. The project-paths list would be needed for per-path
        // mtime polling but we don't do that here.
    }

    deinit {
        timer?.cancel()
    }
}
