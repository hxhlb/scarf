import Foundation

/// Signature every local or remote file/CLI service must implement.
/// Local = direct filesystem reads/writes + subprocess spawning via `HermesTransport`.
/// Remote = SSH `cat`/`tee`/`find` + CLI passthrough via `RemoteHermesTransport`.
///
/// Isolation rules: subprocess/raw-config/binary-resolution methods are `nonisolated`
/// so they can be called from detached tasks; methods that decode main-actor-isolated
/// typed models (`GatewayState`, `CronJobsFile`, `HermesConfig`) stay main-actor-bound.
protocol HermesFileServicing: Sendable {
    nonisolated var locator: any HermesLocator { get }
    nonisolated var transport: any HermesTransport { get }

    // MARK: - Config (typed read is main-actor; raw read is nonisolated)
    func loadConfig() -> HermesConfig
    nonisolated func loadRawConfig() -> String

    // MARK: - Gateway state (typed read is main-actor; raw bytes are nonisolated)
    func loadGatewayState() -> GatewayState?
    nonisolated func loadGatewayStateData() -> Data?

    // MARK: - Memory
    func loadMemoryProfiles() -> [String]
    func loadMemory(profile: String) -> String
    func loadUserProfile(profile: String) -> String
    func saveMemory(_ content: String, profile: String)
    func saveUserProfile(_ content: String, profile: String)

    // MARK: - Cron
    func loadCronJobs() -> [HermesCronJob]
    func loadCronOutput(jobId: String) -> String?

    // MARK: - Skills
    func loadSkills() -> [HermesSkillCategory]
    func loadSkillContent(path: String) -> String
    func saveSkillContent(path: String, content: String)

    // MARK: - Hermes Process (nonisolated — safe from detached tasks)
    nonisolated func isHermesRunning() -> Bool
    nonisolated func hermesPID() -> pid_t?
    @discardableResult nonisolated func stopHermes() -> Bool
    @discardableResult nonisolated func startGateway() -> (exitCode: Int32, output: String)
    @discardableResult nonisolated func restartGateway() -> (exitCode: Int32, output: String)
    nonisolated func gatewayStatus() -> String
    nonisolated func hermesBinaryPath() -> String?
    @discardableResult nonisolated func runHermesCLI(args: [String], timeout: TimeInterval) -> (exitCode: Int32, output: String)
}
