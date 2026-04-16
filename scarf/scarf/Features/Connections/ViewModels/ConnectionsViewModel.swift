import Foundation
import os

/// Manages the list of known remote Hermes instances plus the currently active
/// connection. Persists to `ConnectionStore` on every mutation.
///
/// Test-Connect: a lightweight two-step diagnostic — SSH reachability, then
/// `hermes --version` — just enough to surface the most common misconfigurations
/// (wrong host, missing key, stale hermes binary). Both steps exercise the
/// same SSH transport the rest of the app uses at runtime, so a passing test
/// is an honest signal that live use will work.
@Observable
final class ConnectionsViewModel {
    private let logger = Logger(subsystem: "com.scarf", category: "ConnectionsViewModel")
    private let store = ConnectionStore.shared

    var remotes: [RemoteHermes] = []

    /// Working copy for the add/edit sheet. Nil when the sheet is dismissed.
    var editing: RemoteHermes?
    var isNewRemote = false
    var pendingDelete: RemoteHermes?

    /// Per-remote test result, keyed by RemoteHermes.id. Cleared on re-test.
    var testResults: [UUID: TestOutcome] = [:]
    /// Remote id currently mid-test. Used to disable the button and show a spinner.
    var testing: UUID?

    /// Status banner shown above the list — success messages, errors from
    /// persistence failures, etc.
    var banner: String?

    enum TestOutcome: Sendable, Equatable {
        case passed(summary: String)
        case failed(step: String, message: String)

        var isPassing: Bool { if case .passed = self { return true } else { return false } }
        var iconName: String {
            switch self {
            case .passed: return "checkmark.circle.fill"
            case .failed: return "xmark.octagon.fill"
            }
        }
    }

    func load() async {
        remotes = await store.allRemotes()
    }

    // MARK: - Active selection

    /// Persist the selection, warm the locator cache off the main thread, then
    /// update `AppCoordinator.activeConnection` so its `didSet` fires
    /// `ConnectionProvider.set(...)` and SwiftUI's `.id()` on `ContentView`
    /// rebuilds the whole subtree against the new Hermes.
    ///
    /// Why warm the cache first: VM constructors in the rebuilt subtree call
    /// facade inits synchronously on the main actor. For a remote target
    /// without a warmed locator cache, facade init blocks up to 15 s on the
    /// `$HOME` SSH probe — freezing the UI during the switch. Warming ahead of
    /// time on a detached task keeps the main actor responsive; if Test Connect
    /// already warmed the cache (common case), this is a no-op.
    ///
    /// Must receive the coordinator — the VM can't reach it through @Environment
    /// (observable objects aren't SwiftUI views). The call site in
    /// `ConnectionsView` passes it in explicitly.
    func setActive(_ connection: HermesConnection, coordinator: AppCoordinator) async {
        do {
            try await store.setActive(connection)
            if case .remote(let r) = connection {
                await Task.detached { _ = RemoteHermesLocator.forRemote(r) }.value
            }
            coordinator.activeConnection = connection
            banner = "Now connected to \"\(connection.displayName)\"."
        } catch {
            logger.error("Failed to persist active connection: \(error.localizedDescription)")
            banner = "Couldn't save active connection: \(error.localizedDescription)"
        }
    }

    // MARK: - Sheet lifecycle

    func startAddingRemote() {
        editing = RemoteHermes(nickname: "", host: "", user: NSUserName())
        isNewRemote = true
    }

    func startEditing(_ remote: RemoteHermes) {
        editing = remote
        isNewRemote = false
    }

    func cancelEditing() {
        editing = nil
        isNewRemote = false
    }

    /// Persist edits and, if the user was editing the currently-active remote,
    /// tell the coordinator so the view tree rebuilds against the fresh record.
    /// Without this hop, `AppCoordinator.activeConnection` still carries the
    /// pre-edit `RemoteHermes` value and downstream services see stale host /
    /// binary path / HERMES_HOME. We warm the locator cache off the main
    /// thread first so the rebuild's facade inits don't freeze the UI on a
    /// cold `$HOME` probe after the cache invalidation.
    func commitEditing(coordinator: AppCoordinator) async {
        guard let remote = editing else { return }
        do {
            try await store.upsert(remote)
            // Host / user / remoteHermesHome might have changed — drop the
            // cached absolute $HOME for this remote so the next service build
            // re-probes. No-op on first save.
            RemoteHermesLocator.invalidateCache(for: remote.id)
            remotes = await store.allRemotes()
            let isEditingActive: Bool = {
                if case .remote(let current) = coordinator.activeConnection {
                    return current.id == remote.id
                }
                return false
            }()
            if isEditingActive {
                await Task.detached { _ = RemoteHermesLocator.forRemote(remote) }.value
                coordinator.activeConnection = .remote(remote)
            }
            editing = nil
            isNewRemote = false
        } catch {
            logger.error("Failed to save remote: \(error.localizedDescription)")
            banner = "Couldn't save remote: \(error.localizedDescription)"
        }
    }

    // MARK: - Delete

    /// Deleting the currently-active remote must also flip the coordinator to
    /// `.local` so the view tree rebuilds away from the just-deleted target
    /// (whose SSH config would now fail). Store's `remove` already clears the
    /// active pointer in JSON; this mirrors the change into the live coordinator.
    func confirmDelete(coordinator: AppCoordinator) async {
        guard let remote = pendingDelete else { return }
        do {
            try await store.remove(id: remote.id)
            RemoteHermesLocator.invalidateCache(for: remote.id)
            remotes = await store.allRemotes()
            if case .remote(let current) = coordinator.activeConnection, current.id == remote.id {
                coordinator.activeConnection = .local
            }
            testResults.removeValue(forKey: remote.id)
            pendingDelete = nil
        } catch {
            logger.error("Failed to delete remote: \(error.localizedDescription)")
            banner = "Couldn't delete: \(error.localizedDescription)"
            pendingDelete = nil
        }
    }

    // MARK: - Test Connect

    /// Runs three SSH steps in sequence: reachability, home-dir resolution,
    /// and `hermes --version`. First failure short-circuits with a specific error.
    /// On a healthy remote with an already-open SSH master, all three complete
    /// in well under 2s. The home step doubles as a cache warm-up so the first
    /// service call after the user clicks Set Active doesn't eat a cold SSH
    /// handshake for path resolution.
    func testConnection(_ remote: RemoteHermes) async {
        testing = remote.id
        defer { testing = nil }

        let transport = RemoteHermesTransport(remote: remote)
        let runner = SSHCommandRunner(ssh: transport.ssh)

        // Step 1: SSH reachability — run `true` and confirm exit 0.
        let ssh = runner.run(["true"], timeout: 10)
        if !ssh.succeeded {
            testResults[remote.id] = .failed(
                step: "SSH reachability",
                message: ssh.stderrString.isEmpty ? "ssh exit \(ssh.exitCode)" : ssh.stderrString
            )
            return
        }

        // Step 2: Resolve and cache the remote Hermes home. `forRemote` runs
        // `printf %s $HOME` and populates the locator cache, so later service
        // construction doesn't need to re-probe. Invalidate first so a retry
        // after a previous failure actually re-probes instead of returning the
        // cached failure sentinel.
        RemoteHermesLocator.invalidateCache(for: remote.id)
        let locator = RemoteHermesLocator.forRemote(remote)
        if locator.basePath.isEmpty || locator.basePath == RemoteHermesLocator.failureSentinel {
            testResults[remote.id] = .failed(
                step: "Remote home directory",
                message: "Could not resolve $HOME on the remote. Check the SSH user is valid and has a login shell."
            )
            return
        }

        // Step 3: Hermes binary resolvable — `<binary> --version`.
        // Shell-quote the path so spaces in the binary location (`/opt/my hermes/...`)
        // survive SSH's argv flattening + remote shell re-tokenization.
        let version = runner.run(
            [SSHSessionConfig.shellQuote(remote.remoteBinaryPath), "--version"],
            timeout: 15
        )
        if !version.succeeded {
            testResults[remote.id] = .failed(
                step: "Hermes binary",
                message: version.stderrString.isEmpty
                    ? "exit \(version.exitCode); binary at '\(remote.remoteBinaryPath)' not runnable"
                    : version.stderrString
            )
            return
        }

        let versionLine = version.stdoutString
            .components(separatedBy: .newlines)
            .first(where: { !$0.isEmpty }) ?? "Hermes reachable"
        testResults[remote.id] = .passed(summary: versionLine.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Helpers

    func dismissBanner() {
        banner = nil
    }
}
