import Foundation

/// Public facade for file/CLI operations. Dispatches to `LocalHermesFileService`
/// (`FileManager` + local `hermes` subprocess) or `RemoteHermesFileService` (SSH
/// `cat` / `tee` / `find` + `ssh user@host hermes ...`) based on the connection.
///
/// Default init reads from `ConnectionProvider.current`, so `HermesFileService()`
/// automatically targets whichever Hermes the user has selected.
struct HermesFileService: Sendable {
    nonisolated let impl: any HermesFileServicing

    init(connection: HermesConnection = ConnectionProvider.current) {
        switch connection {
        case .local:
            self.impl = LocalHermesFileService()
        case .remote(let r):
            self.impl = RemoteHermesFileService(
                remote: r,
                locator: RemoteHermesLocator.forRemote(r)
            )
        }
    }

    nonisolated var locator: any HermesLocator { impl.locator }
    nonisolated var transport: any HermesTransport { impl.transport }

    // MARK: - Config

    func loadConfig() -> HermesConfig { impl.loadConfig() }
    nonisolated func loadRawConfig() -> String { impl.loadRawConfig() }

    // MARK: - Gateway state

    func loadGatewayState() -> GatewayState? { impl.loadGatewayState() }
    nonisolated func loadGatewayStateData() -> Data? { impl.loadGatewayStateData() }

    // MARK: - Memory

    func loadMemoryProfiles() -> [String] { impl.loadMemoryProfiles() }
    func loadMemory(profile: String = "") -> String { impl.loadMemory(profile: profile) }
    func loadUserProfile(profile: String = "") -> String { impl.loadUserProfile(profile: profile) }
    func saveMemory(_ content: String, profile: String = "") { impl.saveMemory(content, profile: profile) }
    func saveUserProfile(_ content: String, profile: String = "") { impl.saveUserProfile(content, profile: profile) }

    // MARK: - Cron

    func loadCronJobs() -> [HermesCronJob] { impl.loadCronJobs() }
    func loadCronOutput(jobId: String) -> String? { impl.loadCronOutput(jobId: jobId) }

    // MARK: - Skills

    func loadSkills() -> [HermesSkillCategory] { impl.loadSkills() }
    func loadSkillContent(path: String) -> String { impl.loadSkillContent(path: path) }
    func saveSkillContent(path: String, content: String) { impl.saveSkillContent(path: path, content: content) }

    // MARK: - Hermes Process

    nonisolated func isHermesRunning() -> Bool { impl.isHermesRunning() }
    nonisolated func hermesPID() -> pid_t? { impl.hermesPID() }

    @discardableResult
    nonisolated func stopHermes() -> Bool { impl.stopHermes() }

    @discardableResult
    nonisolated func startGateway() -> (exitCode: Int32, output: String) { impl.startGateway() }

    @discardableResult
    nonisolated func restartGateway() -> (exitCode: Int32, output: String) { impl.restartGateway() }

    nonisolated func gatewayStatus() -> String { impl.gatewayStatus() }
    nonisolated func hermesBinaryPath() -> String? { impl.hermesBinaryPath() }

    @discardableResult
    nonisolated func runHermesCLI(args: [String], timeout: TimeInterval = 60) -> (exitCode: Int32, output: String) {
        impl.runHermesCLI(args: args, timeout: timeout)
    }
}
