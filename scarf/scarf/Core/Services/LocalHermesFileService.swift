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
    nonisolated func runHermesCLI(args: [String], timeout: TimeInterval = 60) -> (exitCode: Int32, output: String) {
        guard let process = transport.makeHermesProcess(args: args) else { return (-1, "") }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        defer {
            try? stdoutPipe.fileHandleForReading.close()
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForWriting.close()
        }
        do {
            try process.run()
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
