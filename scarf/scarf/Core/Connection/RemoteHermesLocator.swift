import Foundation
import os

/// Remote-aware `HermesLocator`. Returns absolute paths for the Hermes tree on
/// the remote host — resolved from the remote user's `$HOME` via one SSH probe
/// at first use, then cached per `RemoteHermes.id`.
///
/// Why not just use `~` or `$HOME` in paths: OpenSSH forwards our argv by joining
/// with spaces and sending to the remote login shell, which re-tokenizes the line.
/// Tilde / variable expansion inside quoted paths is unreliable across bash / zsh /
/// sh defaults and breaks when wrapping commands in `sh -c '...'`. Resolving once
/// to an absolute path side-steps all of that.
nonisolated struct RemoteHermesLocator: HermesLocator {
    /// Absolute Hermes-home path on the remote (`/home/alan/.hermes`,
    /// `/opt/hermes`, etc.). Everything else is derived from this.
    nonisolated let basePath: String

    nonisolated init(basePath: String) {
        self.basePath = basePath
    }

    /// Derived by stripping the trailing `/.hermes` from `basePath`. If the user
    /// overrode `HERMES_HOME` to a path that doesn't end in `.hermes`, this will
    /// return `basePath` itself — acceptable, since ACP cwd just needs a directory
    /// the remote Hermes can resolve.
    nonisolated var userHome: String {
        if basePath.hasSuffix("/.hermes") {
            return String(basePath.dropLast("/.hermes".count))
        }
        return basePath
    }

    nonisolated var home: String { basePath }
    nonisolated var stateDB: String { basePath + "/state.db" }
    nonisolated var configYAML: String { basePath + "/config.yaml" }
    nonisolated var memoriesDir: String { basePath + "/memories" }
    nonisolated var memoryMD: String { basePath + "/memories/MEMORY.md" }
    nonisolated var userMD: String { basePath + "/memories/USER.md" }
    nonisolated var sessionsDir: String { basePath + "/sessions" }
    nonisolated var cronJobsJSON: String { basePath + "/cron/jobs.json" }
    nonisolated var cronOutputDir: String { basePath + "/cron/output" }
    nonisolated var gatewayStateJSON: String { basePath + "/gateway_state.json" }
    nonisolated var skillsDir: String { basePath + "/skills" }
    nonisolated var errorsLog: String { basePath + "/logs/errors.log" }
    nonisolated var agentLog: String { basePath + "/logs/agent.log" }
    nonisolated var gatewayLog: String { basePath + "/logs/gateway.log" }
    nonisolated var scarfDir: String { basePath + "/scarf" }
    nonisolated var projectsRegistry: String { basePath + "/scarf/projects.json" }
    nonisolated var mcpTokensDir: String { basePath + "/mcp-tokens" }

    // MARK: - Resolution

    private static let logger = Logger(subsystem: "com.scarf", category: "RemoteHermesLocator")
    private static let cache = OSAllocatedUnfairLock<[UUID: String]>(initialState: [:])

    /// Build a locator for a remote. Uses `remoteHermesHome` if the user pinned
    /// one (trusted absolute path); otherwise asks the remote what `$HOME` is
    /// and appends `/.hermes`. Resolution is cached per `remote.id` — if the
    /// SSH master is already open (Test Connect ran earlier), this costs one
    /// multiplexed round trip, usually well under 100 ms.
    nonisolated static func forRemote(_ remote: RemoteHermes) -> RemoteHermesLocator {
        if let override = remote.remoteHermesHome, !override.isEmpty {
            return RemoteHermesLocator(basePath: override)
        }
        if let cached = cache.withLock({ $0[remote.id] }) {
            return RemoteHermesLocator(basePath: cached)
        }

        let transport = RemoteHermesTransport(remote: remote)
        let runner = SSHCommandRunner(ssh: transport.ssh)
        // Resolve `$HOME` via an explicit `sh -c` with `$HOME` double-quoted so
        // homes containing spaces (rare but legal) don't get word-split. Wrapping
        // with `wrapForRemoteShell` keeps the script as a single sh -c argument
        // after SSH's argv flattening. printf avoids the trailing newline that
        // `echo` adds.
        let script = "printf %s \"$HOME\""
        let result = runner.run(
            ["sh", "-c", SSHSessionConfig.wrapForRemoteShell(script)],
            timeout: 15
        )

        let base: String
        if result.succeeded, !result.stdoutString.isEmpty {
            let home = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            base = home + "/.hermes"
        } else {
            logger.warning("Could not resolve \(remote.sshTarget) $HOME (\(result.stderrString.prefix(120))). Caching broken fallback; downstream reads will fail until the user re-runs Test Connect or restarts Scarf.")
            base = Self.failureSentinel // marker for "probed and failed"
        }
        // Cache unconditionally. A failed probe takes up to 15s; without caching,
        // every subsequent facade init (dashboard, sessions, file watcher, ...)
        // would repeat the probe and pile on 15s of UI freezing per facade.
        // `Test Connect` and `commitEditing` invalidate this cache when the user
        // wants a fresh attempt.
        cache.withLock { $0[remote.id] = base }
        return RemoteHermesLocator(basePath: base)
    }

    /// Sentinel value cached on probe failure. Downstream file operations will
    /// quickly fail (path doesn't exist), which is better than a 15-second hang.
    /// Test Connect surfaces the underlying stderr so the user knows what broke.
    nonisolated static let failureSentinel = "/.hermes_SCARF_PROBE_FAILED"

    /// Invalidate the cached base path for a remote — call this if the user
    /// edits the remote record (e.g. changes host, which changes $HOME).
    nonisolated static func invalidateCache(for remoteId: UUID) {
        cache.withLock { _ = $0.removeValue(forKey: remoteId) }
    }
}
