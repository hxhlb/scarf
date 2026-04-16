import Foundation
import os

/// SSH-backed implementation of `HermesFileServicing`.
///
/// Every file operation funnels through `SSHCommandRunner` running `cat` / `tee` /
/// `find` on the remote host. CLI invocations reuse `RemoteHermesTransport`, which
/// already wraps commands in `ssh user@host hermes ...`. Works against any Hermes
/// install with sshd running — no Hermes-side server process required.
struct RemoteHermesFileService: HermesFileServicing {
    nonisolated let locator: any HermesLocator
    nonisolated let transport: any HermesTransport
    nonisolated let runner: SSHCommandRunner
    private static let logger = Logger(subsystem: "com.scarf", category: "RemoteHermesFileService")

    init(remote: RemoteHermes, locator: any HermesLocator) {
        self.locator = locator
        let remoteTransport = RemoteHermesTransport(remote: remote)
        self.transport = remoteTransport
        self.runner = SSHCommandRunner(ssh: remoteTransport.ssh)
    }

    // MARK: - Config

    func loadConfig() -> HermesConfig {
        let raw = loadRawConfig()
        guard !raw.isEmpty else { return .empty }
        return HermesYAMLParsers.parseConfig(raw)
    }

    nonisolated func loadRawConfig() -> String {
        remoteReadString(locator.configYAML) ?? ""
    }

    // MARK: - Gateway state

    func loadGatewayState() -> GatewayState? {
        guard let data = loadGatewayStateData() else { return nil }
        do {
            return try JSONDecoder().decode(GatewayState.self, from: data)
        } catch {
            Self.logger.error("Failed to decode remote gateway state: \(error.localizedDescription)")
            return nil
        }
    }

    nonisolated func loadGatewayStateData() -> Data? {
        remoteReadData(locator.gatewayStateJSON)
    }

    // MARK: - Memory

    func loadMemoryProfiles() -> [String] {
        remoteListSubdirectories(locator.memoriesDir).sorted()
    }

    func loadMemory(profile: String) -> String {
        remoteReadString(memoryPath(profile: profile, file: "MEMORY.md")) ?? ""
    }

    func loadUserProfile(profile: String) -> String {
        remoteReadString(memoryPath(profile: profile, file: "USER.md")) ?? ""
    }

    func saveMemory(_ content: String, profile: String) {
        remoteWriteString(content, to: memoryPath(profile: profile, file: "MEMORY.md"))
    }

    func saveUserProfile(_ content: String, profile: String) {
        remoteWriteString(content, to: memoryPath(profile: profile, file: "USER.md"))
    }

    private func memoryPath(profile: String, file: String) -> String {
        if profile.isEmpty {
            return locator.memoriesDir + "/" + file
        }
        return locator.memoriesDir + "/" + profile + "/" + file
    }

    // MARK: - Cron

    func loadCronJobs() -> [HermesCronJob] {
        guard let data = remoteReadData(locator.cronJobsJSON) else { return [] }
        do {
            let file = try JSONDecoder().decode(CronJobsFile.self, from: data)
            return file.jobs
        } catch {
            Self.logger.error("Failed to decode remote cron jobs: \(error.localizedDescription)")
            return []
        }
    }

    func loadCronOutput(jobId: String) -> String? {
        // Find the newest cron output file whose name contains the jobId.
        let dir = locator.cronOutputDir
        let script = "ls -1 \(SSHSessionConfig.shellQuote(dir)) 2>/dev/null | sort"
        let listResult = runner.run([
            "sh", "-c", SSHSessionConfig.wrapForRemoteShell(script)
        ])
        guard listResult.succeeded else { return nil }
        let files = listResult.stdoutString
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains(jobId) }
        guard let filename = files.last else { return nil }
        return remoteReadString(dir + "/" + filename)
    }

    // MARK: - Skills

    func loadSkills() -> [HermesSkillCategory] {
        // Single SSH call to list everything 2 levels deep under the skills dir.
        // Output lines are absolute paths; we bucket them into category/skill/file.
        let dir = locator.skillsDir
        let script = "find \(SSHSessionConfig.shellQuote(dir)) -mindepth 1 -maxdepth 3 2>/dev/null"
        let listing = runner.run([
            "sh", "-c", SSHSessionConfig.wrapForRemoteShell(script)
        ])
        guard listing.succeeded else { return [] }

        // Build category → skillName → [filenames]
        var tree: [String: [String: [String]]] = [:]
        for line in listing.stdoutString.split(separator: "\n").map(String.init) {
            guard line.hasPrefix(dir + "/") else { continue }
            let relative = String(line.dropFirst(dir.count + 1))
            let parts = relative.split(separator: "/").map(String.init)
            switch parts.count {
            case 1:
                // Category directory
                if tree[parts[0]] == nil { tree[parts[0]] = [:] }
            case 2:
                // Skill directory
                if tree[parts[0]]?[parts[1]] == nil {
                    tree[parts[0], default: [:]][parts[1]] = []
                }
            case 3:
                // Skill file
                tree[parts[0], default: [:]][parts[1], default: []].append(parts[2])
            default:
                continue
            }
        }

        return tree.keys.sorted().compactMap { categoryName in
            guard let skills = tree[categoryName] else { return nil }
            let entries = skills.keys.sorted().map { skillName -> HermesSkill in
                let skillPath = dir + "/" + categoryName + "/" + skillName
                let files = (skills[skillName] ?? []).sorted()
                let yaml = remoteReadString(skillPath + "/skill.yaml") ?? ""
                let requiredConfig = HermesYAMLParsers.parseSkillRequiredConfig(yaml)
                return HermesSkill(
                    id: categoryName + "/" + skillName,
                    name: skillName,
                    category: categoryName,
                    path: skillPath,
                    files: files,
                    requiredConfig: requiredConfig
                )
            }
            guard !entries.isEmpty else { return nil }
            return HermesSkillCategory(id: categoryName, name: categoryName, skills: entries)
        }
    }

    func loadSkillContent(path: String) -> String {
        guard isValidSkillPath(path) else { return "" }
        return remoteReadString(path) ?? ""
    }

    func saveSkillContent(path: String, content: String) {
        guard isValidSkillPath(path) else { return }
        remoteWriteString(content, to: path)
    }

    private func isValidSkillPath(_ path: String) -> Bool {
        guard !path.contains(".."), path.hasPrefix(locator.skillsDir) else {
            Self.logger.warning("Rejected remote skill path outside skills directory: \(path)")
            return false
        }
        return true
    }

    // MARK: - Hermes Process

    nonisolated func isHermesRunning() -> Bool {
        hermesPID() != nil
    }

    nonisolated func hermesPID() -> pid_t? {
        let result = runner.run(["pgrep", "-f", "hermes"], timeout: 10)
        guard result.succeeded else { return nil }
        let output = result.stdoutString
        guard let firstLine = output.components(separatedBy: "\n").first(where: { !$0.isEmpty }),
              let pid = pid_t(firstLine.trimmingCharacters(in: .whitespaces)) else { return nil }
        return pid
    }

    @discardableResult
    nonisolated func stopHermes() -> Bool {
        // Remote: always go through `hermes gateway stop`. Unlike local we don't have
        // a meaningful SIGTERM fallback since we can't signal processes on another host
        // without another SSH call, and the CLI's launchctl bootout / systemd stop is
        // the supported path anyway.
        runHermesCLI(args: ["gateway", "stop"], timeout: 60).exitCode == 0
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
        // Remote transport wraps this in `ssh user@host hermes <args>` automatically.
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

    // MARK: - Remote I/O helpers

    /// `ssh host cat -- <quoted_path>`. Nil on non-zero exit (typically "no such file").
    /// Uses direct argv (no `sh -c`) so we avoid the re-tokenization trap entirely.
    private nonisolated func remoteReadString(_ path: String) -> String? {
        guard let data = remoteReadData(path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated func remoteReadData(_ path: String) -> Data? {
        let result = runner.run([
            "cat", "--", SSHSessionConfig.shellQuote(path)
        ])
        return result.succeeded ? result.stdout : nil
    }

    /// Writes need a shell for the `mkdir && cat >` redirect, so the inner script
    /// is wrapped with `wrapForRemoteShell` to keep it as a single sh -c argument
    /// after SSH's argv join + remote shell re-tokenization.
    private nonisolated func remoteWriteString(_ content: String, to path: String) {
        let parent = (path as NSString).deletingLastPathComponent
        let script = "mkdir -p \(SSHSessionConfig.shellQuote(parent)) && cat > \(SSHSessionConfig.shellQuote(path))"
        _ = runner.run([
            "sh", "-c", SSHSessionConfig.wrapForRemoteShell(script)
        ], stdin: Data(content.utf8))
    }

    private nonisolated func remoteListSubdirectories(_ dir: String) -> [String] {
        let script = "find \(SSHSessionConfig.shellQuote(dir)) -mindepth 1 -maxdepth 1 -type d 2>/dev/null"
        let result = runner.run([
            "sh", "-c", SSHSessionConfig.wrapForRemoteShell(script)
        ])
        guard result.succeeded else { return [] }
        return result.stdoutString
            .split(separator: "\n")
            .map { (path: Substring) -> String in
                String(path).split(separator: "/").last.map(String.init) ?? ""
            }
            .filter { !$0.isEmpty }
    }
}
