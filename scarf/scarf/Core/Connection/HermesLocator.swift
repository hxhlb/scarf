import Foundation

/// Resolves on-disk paths used by a local Hermes installation.
/// Only consulted by services that perform direct file I/O (the local strategy).
/// Remote services will not use a locator — they'll query the HTTP API instead.
protocol HermesLocator: Sendable {
    /// User's home directory on whichever host this locator addresses.
    /// Local: `NSHomeDirectory()`. Remote: the `$HOME` resolved from the remote
    /// login shell. Used as the default `cwd` for ACP chat sessions and any
    /// other code that needs a "reasonable working directory" default.
    nonisolated var userHome: String { get }

    /// Path to the Hermes data directory (typically `<userHome>/.hermes`, unless
    /// `HERMES_HOME` is overridden).
    nonisolated var home: String { get }
    nonisolated var stateDB: String { get }
    nonisolated var configYAML: String { get }
    nonisolated var memoriesDir: String { get }
    nonisolated var memoryMD: String { get }
    nonisolated var userMD: String { get }
    nonisolated var sessionsDir: String { get }
    nonisolated var cronJobsJSON: String { get }
    nonisolated var cronOutputDir: String { get }
    nonisolated var gatewayStateJSON: String { get }
    nonisolated var skillsDir: String { get }
    nonisolated var errorsLog: String { get }
    nonisolated var agentLog: String { get }
    nonisolated var gatewayLog: String { get }
    nonisolated var scarfDir: String { get }
    nonisolated var projectsRegistry: String { get }
    nonisolated var mcpTokensDir: String { get }
}

/// Default locator that mirrors the layout under `~/.hermes/`.
/// Wraps the legacy `HermesPaths` enum so existing call sites keep behaving identically.
struct LocalHermesLocator: HermesLocator {
    nonisolated init() {}
    nonisolated var userHome: String { HermesPaths.userHomeDirectory }
    nonisolated var home: String { HermesPaths.home }
    nonisolated var stateDB: String { HermesPaths.stateDB }
    nonisolated var configYAML: String { HermesPaths.configYAML }
    nonisolated var memoriesDir: String { HermesPaths.memoriesDir }
    nonisolated var memoryMD: String { HermesPaths.memoryMD }
    nonisolated var userMD: String { HermesPaths.userMD }
    nonisolated var sessionsDir: String { HermesPaths.sessionsDir }
    nonisolated var cronJobsJSON: String { HermesPaths.cronJobsJSON }
    nonisolated var cronOutputDir: String { HermesPaths.cronOutputDir }
    nonisolated var gatewayStateJSON: String { HermesPaths.gatewayStateJSON }
    nonisolated var skillsDir: String { HermesPaths.skillsDir }
    nonisolated var errorsLog: String { HermesPaths.errorsLog }
    nonisolated var agentLog: String { HermesPaths.agentLog }
    nonisolated var gatewayLog: String { HermesPaths.gatewayLog }
    nonisolated var scarfDir: String { HermesPaths.scarfDir }
    nonisolated var projectsRegistry: String { HermesPaths.projectsRegistry }
    nonisolated var mcpTokensDir: String { HermesPaths.mcpTokensDir }
}
