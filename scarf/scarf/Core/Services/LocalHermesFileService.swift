import Foundation

/// Local file/CLI implementation of `HermesFileServicing`.
/// Reads files directly from `~/.hermes/` and spawns the local `hermes` binary
/// via `LocalHermesTransport`. Its sibling `RemoteHermesFileService` satisfies the
/// same protocol using SSH `cat` / `tee` / `find` and `ssh user@host hermes ...` for CLI.
struct LocalHermesFileService: HermesFileServicing {
    nonisolated let locator: any HermesLocator
    nonisolated let transport: any HermesTransport

    init(
        locator: any HermesLocator = LocalHermesLocator(),
        transport: any HermesTransport = LocalHermesTransport()
    ) {
        self.locator = locator
        self.transport = transport
    }

    // MARK: - Config

    func loadConfig() -> HermesConfig {
        guard let content = readFile(locator.configYAML) else { return .empty }
        return HermesYAMLParsers.parseConfig(content)
    }

    nonisolated func loadRawConfig() -> String {
        readFile(locator.configYAML) ?? ""
    }

    // MARK: - Gateway State

    func loadGatewayState() -> GatewayState? {
        guard let data = readFileData(locator.gatewayStateJSON) else { return nil }
        do {
            return try JSONDecoder().decode(GatewayState.self, from: data)
        } catch {
            print("[Scarf] Failed to decode gateway state: \(error.localizedDescription)")
            return nil
        }
    }

    nonisolated func loadGatewayStateData() -> Data? {
        readFileData(locator.gatewayStateJSON)
    }

    // MARK: - Memory

    func loadMemoryProfiles() -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: locator.memoriesDir) else { return [] }
        return entries.filter { name in
            var isDir: ObjCBool = false
            let path = locator.memoriesDir + "/" + name
            return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }.sorted()
    }

    func loadMemory(profile: String) -> String {
        let path = memoryPath(profile: profile, file: "MEMORY.md")
        return readFile(path) ?? ""
    }

    func loadUserProfile(profile: String) -> String {
        let path = memoryPath(profile: profile, file: "USER.md")
        return readFile(path) ?? ""
    }

    func saveMemory(_ content: String, profile: String) {
        let path = memoryPath(profile: profile, file: "MEMORY.md")
        writeFile(path, content: content)
    }

    func saveUserProfile(_ content: String, profile: String) {
        let path = memoryPath(profile: profile, file: "USER.md")
        writeFile(path, content: content)
    }

    private func memoryPath(profile: String, file: String) -> String {
        if profile.isEmpty {
            return locator.memoriesDir + "/" + file
        }
        return locator.memoriesDir + "/" + profile + "/" + file
    }

    // MARK: - Cron

    func loadCronJobs() -> [HermesCronJob] {
        guard let data = readFileData(locator.cronJobsJSON) else { return [] }
        do {
            let file = try JSONDecoder().decode(CronJobsFile.self, from: data)
            return file.jobs
        } catch {
            print("[Scarf] Failed to decode cron jobs: \(error.localizedDescription)")
            return []
        }
    }

    func loadCronOutput(jobId: String) -> String? {
        let dir = locator.cronOutputDir
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
        let matching = files.filter { $0.contains(jobId) }.sorted().last
        guard let filename = matching else { return nil }
        return readFile(dir + "/" + filename)
    }

    // MARK: - Skills

    func loadSkills() -> [HermesSkillCategory] {
        let dir = locator.skillsDir
        let fm = FileManager.default
        guard let categories = try? fm.contentsOfDirectory(atPath: dir) else { return [] }

        return categories.sorted().compactMap { categoryName in
            let categoryPath = dir + "/" + categoryName
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: categoryPath, isDirectory: &isDir), isDir.boolValue else { return nil }
            guard let skillNames = try? fm.contentsOfDirectory(atPath: categoryPath) else { return nil }

            let skills = skillNames.sorted().compactMap { skillName -> HermesSkill? in
                let skillPath = categoryPath + "/" + skillName
                var isSkillDir: ObjCBool = false
                guard fm.fileExists(atPath: skillPath, isDirectory: &isSkillDir), isSkillDir.boolValue else { return nil }
                let files = (try? fm.contentsOfDirectory(atPath: skillPath)) ?? []
                let yaml = readFile(skillPath + "/skill.yaml") ?? ""
                let requiredConfig = HermesYAMLParsers.parseSkillRequiredConfig(yaml)
                return HermesSkill(
                    id: categoryName + "/" + skillName,
                    name: skillName,
                    category: categoryName,
                    path: skillPath,
                    files: files.sorted(),
                    requiredConfig: requiredConfig
                )
            }

            guard !skills.isEmpty else { return nil }
            return HermesSkillCategory(id: categoryName, name: categoryName, skills: skills)
        }
    }

    func loadSkillContent(path: String) -> String {
        guard isValidSkillPath(path) else { return "" }
        return readFile(path) ?? ""
    }

    func saveSkillContent(path: String, content: String) {
        guard isValidSkillPath(path) else { return }
        writeFile(path, content: content)
    }

    private func isValidSkillPath(_ path: String) -> Bool {
        guard !path.contains(".."), path.hasPrefix(locator.skillsDir) else {
            print("[Scarf] Rejected skill path outside skills directory: \(path)")
            return false
        }
        return true
    }

    // MARK: - Hermes Process

    nonisolated func isHermesRunning() -> Bool {
        hermesPID() != nil
    }

    nonisolated func hermesPID() -> pid_t? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "hermes"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            guard let firstLine = output.components(separatedBy: "\n").first(where: { !$0.isEmpty }),
                  let pid = pid_t(firstLine.trimmingCharacters(in: .whitespaces)) else { return nil }
            return pid
        } catch {
            return nil
        }
    }

    @discardableResult
    nonisolated func stopHermes() -> Bool {
        // v0.9.0 fixed `hermes gateway stop` so it issues `launchctl bootout` and
        // waits for exit. Use the CLI to avoid racing launchd's KeepAlive respawn.
        if runHermesCLI(args: ["gateway", "stop"], timeout: 60).exitCode == 0 {
            return true
        }
        guard let pid = hermesPID() else { return false }
        return kill(pid, SIGTERM) == 0
    }

    @discardableResult
    nonisolated func startGateway() -> (exitCode: Int32, output: String) {
        runHermesCLI(args: ["gateway", "start"], timeout: 60)
    }

    @discardableResult
    nonisolated func restartGateway() -> (exitCode: Int32, output: String) {
        runHermesCLI(args: ["gateway", "restart"], timeout: 60)
    }

    nonisolated func gatewayStatus() -> String {
        runHermesCLI(args: ["gateway", "status"], timeout: 60).output
    }

    nonisolated func hermesBinaryPath() -> String? {
        transport.hermesBinaryPath
    }

    @discardableResult
    nonisolated func runHermesCLI(args: [String], timeout: TimeInterval = 60, stdinInput: String? = nil) -> (exitCode: Int32, output: String) {
        guard let process = transport.makeHermesProcess(args: args) else { return (-1, "") }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe: Pipe? = stdinInput != nil ? Pipe() : nil
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if let stdinPipe { process.standardInput = stdinPipe }
        defer {
            try? stdoutPipe.fileHandleForReading.close()
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForWriting.close()
            try? stdinPipe?.fileHandleForReading.close()
            try? stdinPipe?.fileHandleForWriting.close()
        }
        do {
            try process.run()
            if let stdinInput, let stdinPipe, let data = stdinInput.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
                try? stdinPipe.fileHandleForWriting.close()
            }
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let combined = (String(data: outData, encoding: .utf8) ?? "") + (String(data: errData, encoding: .utf8) ?? "")
            return (process.terminationStatus, combined)
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    // MARK: - MCP Servers

    func loadMCPServers() -> [HermesMCPServer] {
        guard let yaml = readFile(locator.configYAML) else { return [] }
        let parsed = HermesMCPConfigParser.parseMCPServersBlock(yaml: yaml)
        let fm = FileManager.default
        return parsed.map { server in
            let tokenPath = locator.mcpTokensDir + "/" + server.name + ".json"
            let hasToken = fm.fileExists(atPath: tokenPath)
            guard hasToken != server.hasOAuthToken else { return server }
            return HermesMCPServer(
                name: server.name, transport: server.transport, command: server.command,
                args: server.args, url: server.url, auth: server.auth, env: server.env,
                headers: server.headers, timeout: server.timeout, connectTimeout: server.connectTimeout,
                enabled: server.enabled, toolsInclude: server.toolsInclude, toolsExclude: server.toolsExclude,
                resourcesEnabled: server.resourcesEnabled, promptsEnabled: server.promptsEnabled,
                hasOAuthToken: hasToken
            )
        }
    }

    @discardableResult
    func addMCPServerStdio(name: String, command: String, args: [String]) -> (exitCode: Int32, output: String) {
        let addResult = runHermesCLI(args: ["mcp", "add", name, "--command", command], timeout: 45, stdinInput: "y\ny\ny\n")
        guard addResult.exitCode == 0 else { return addResult }
        if !args.isEmpty { _ = setMCPServerArgs(name: name, args: args) }
        return addResult
    }

    @discardableResult
    func addMCPServerHTTP(name: String, url: String, auth: String?) -> (exitCode: Int32, output: String) {
        var cliArgs: [String] = ["mcp", "add", name, "--url", url]
        if let auth, !auth.isEmpty { cliArgs.append(contentsOf: ["--auth", auth]) }
        return runHermesCLI(args: cliArgs, timeout: 45, stdinInput: "y\ny\ny\n")
    }

    @discardableResult
    func setMCPServerArgs(name: String, args: [String]) -> Bool {
        patchMCPField(name: name) { HermesMCPConfigParser.replaceOrInsertList(header: "args", items: args, in: &$0) }
    }

    @discardableResult
    func removeMCPServer(name: String) -> (exitCode: Int32, output: String) {
        runHermesCLI(args: ["mcp", "remove", name], timeout: 30)
    }

    nonisolated func testMCPServer(name: String) async -> MCPTestResult {
        let started = Date()
        let service = self
        let result = await Task.detached { () -> (Int32, String) in
            service.runHermesCLI(args: ["mcp", "test", name], timeout: 30)
        }.value
        let elapsed = Date().timeIntervalSince(started)
        let tools = HermesMCPConfigParser.parseToolListFromTestOutput(result.1)
        return MCPTestResult(serverName: name, succeeded: result.0 == 0, output: result.1, tools: tools, elapsed: elapsed)
    }

    @discardableResult
    func toggleMCPServerEnabled(name: String, enabled: Bool) -> Bool {
        patchMCPField(name: name) { HermesMCPConfigParser.replaceOrInsertScalar(key: "enabled", value: enabled ? "true" : "false", in: &$0) }
    }

    @discardableResult
    func setMCPServerEnv(name: String, env: [String: String]) -> Bool {
        patchMCPField(name: name) { HermesMCPConfigParser.replaceOrInsertSubMap(header: "env", map: env, in: &$0) }
    }

    @discardableResult
    func setMCPServerHeaders(name: String, headers: [String: String]) -> Bool {
        patchMCPField(name: name) { HermesMCPConfigParser.replaceOrInsertSubMap(header: "headers", map: headers, in: &$0) }
    }

    @discardableResult
    func updateMCPToolFilters(name: String, include: [String], exclude: [String], resources: Bool, prompts: Bool) -> Bool {
        patchMCPField(name: name) { HermesMCPConfigParser.replaceOrInsertToolsBlock(include: include, exclude: exclude, resources: resources, prompts: prompts, in: &$0) }
    }

    @discardableResult
    func setMCPServerTimeouts(name: String, timeout: Int?, connectTimeout: Int?) -> Bool {
        patchMCPField(name: name) { lines in
            if let timeout { HermesMCPConfigParser.replaceOrInsertScalar(key: "timeout", value: String(timeout), in: &lines) }
            else { HermesMCPConfigParser.removeScalar(key: "timeout", in: &lines) }
            if let connectTimeout { HermesMCPConfigParser.replaceOrInsertScalar(key: "connect_timeout", value: String(connectTimeout), in: &lines) }
            else { HermesMCPConfigParser.removeScalar(key: "connect_timeout", in: &lines) }
        }
    }

    @discardableResult
    func deleteMCPOAuthToken(name: String) -> Bool {
        let path = locator.mcpTokensDir + "/" + name + ".json"
        do { try FileManager.default.removeItem(atPath: path); return true }
        catch { return false }
    }

    private func patchMCPField(name: String, mutate: (inout [String]) -> Void) -> Bool {
        guard let yaml = readFile(locator.configYAML) else { return false }
        guard let patched = HermesMCPConfigParser.patchMCPServerField(yaml: yaml, name: name, mutate: mutate) else { return false }
        writeFile(locator.configYAML, content: patched)
        return true
    }

    // MARK: - File I/O

    private nonisolated func readFile(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    private nonisolated func readFileData(_ path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }

    private nonisolated func writeFile(_ path: String, content: String) {
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            print("[Scarf] Failed to write \(path): \(error.localizedDescription)")
        }
    }
}
