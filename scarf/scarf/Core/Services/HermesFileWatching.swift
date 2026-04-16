import Foundation

/// Signature every local or remote file-watcher backend must implement.
/// The contract is deliberately narrow: `startWatching(onChange:)` starts emitting
/// change notifications, and the implementation invokes the closure whenever
/// something observable has changed. The facade above this protocol is @Observable
/// and converts callback-style signals into a `lastChangeDate` SwiftUI can react to.
///
/// Local = `DispatchSourceFileSystemObject` wired to each Hermes path.
/// Remote = polling loop that checks `updated_at` timestamps via the HTTP API.
protocol HermesFileWatching: Sendable, AnyObject {
    func startWatching(onChange: @escaping @Sendable () -> Void)
    func stopWatching()
    func updateProjectWatches(_ paths: [String])
}
