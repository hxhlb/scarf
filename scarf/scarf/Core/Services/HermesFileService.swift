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
    nonisolated func runHermesCLI(args: [String], timeout: TimeInterval = 60, stdinInput: String? = nil) -> (exitCode: Int32, output: String) {
        impl.runHermesCLI(args: args, timeout: timeout, stdinInput: stdinInput)
    }

    // MARK: - MCP Servers

    func loadMCPServers() -> [HermesMCPServer] { impl.loadMCPServers() }

    @discardableResult
    func addMCPServerStdio(name: String, command: String, args: [String]) -> (exitCode: Int32, output: String) {
        impl.addMCPServerStdio(name: name, command: command, args: args)
    }

    @discardableResult
    func addMCPServerHTTP(name: String, url: String, auth: String?) -> (exitCode: Int32, output: String) {
        impl.addMCPServerHTTP(name: name, url: url, auth: auth)
    }

    @discardableResult
    func setMCPServerArgs(name: String, args: [String]) -> Bool { impl.setMCPServerArgs(name: name, args: args) }

    @discardableResult
    func removeMCPServer(name: String) -> (exitCode: Int32, output: String) { impl.removeMCPServer(name: name) }

    nonisolated func testMCPServer(name: String) async -> MCPTestResult {
        await impl.testMCPServer(name: name)
    }

    @discardableResult
    func toggleMCPServerEnabled(name: String, enabled: Bool) -> Bool { impl.toggleMCPServerEnabled(name: name, enabled: enabled) }

    @discardableResult
    func setMCPServerEnv(name: String, env: [String: String]) -> Bool { impl.setMCPServerEnv(name: name, env: env) }

    @discardableResult
    func setMCPServerHeaders(name: String, headers: [String: String]) -> Bool { impl.setMCPServerHeaders(name: name, headers: headers) }

    @discardableResult
    func updateMCPToolFilters(name: String, include: [String], exclude: [String], resources: Bool, prompts: Bool) -> Bool {
        impl.updateMCPToolFilters(name: name, include: include, exclude: exclude, resources: resources, prompts: prompts)
    }

    @discardableResult
    func setMCPServerTimeouts(name: String, timeout: Int?, connectTimeout: Int?) -> Bool {
        impl.setMCPServerTimeouts(name: name, timeout: timeout, connectTimeout: connectTimeout)
    }

    @discardableResult
    func deleteMCPOAuthToken(name: String) -> Bool { impl.deleteMCPOAuthToken(name: name) }
}
