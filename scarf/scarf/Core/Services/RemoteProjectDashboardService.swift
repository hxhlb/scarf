import Foundation
import os

/// SSH-backed implementation of `ProjectDashboardServicing`.
///
/// The project registry (`~/.hermes/scarf/projects.json`) and per-project dashboard
/// JSON files all live on the remote host's filesystem. Reads use `ssh host cat`;
/// writes use `ssh host sh -c 'cat > <path>'` with content streamed over stdin.
struct RemoteProjectDashboardService: ProjectDashboardServicing {
    nonisolated let locator: any HermesLocator
    nonisolated let runner: SSHCommandRunner
    private static let logger = Logger(subsystem: "com.scarf", category: "RemoteProjectDashboardService")

    init(remote: RemoteHermes, locator: any HermesLocator) {
        self.locator = locator
        let transport = RemoteHermesTransport(remote: remote)
        self.runner = SSHCommandRunner(ssh: transport.ssh)
    }

    // MARK: - Registry

    func loadRegistry() -> ProjectRegistry {
        guard let data = remoteReadData(locator.projectsRegistry) else {
            return ProjectRegistry(projects: [])
        }
        do {
            return try JSONDecoder().decode(ProjectRegistry.self, from: data)
        } catch {
            Self.logger.error("Failed to decode remote project registry: \(error.localizedDescription)")
            return ProjectRegistry(projects: [])
        }
    }

    func saveRegistry(_ registry: ProjectRegistry) {
        guard let data = try? JSONEncoder().encode(registry) else { return }
        let pretty: Data
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let formatted = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            pretty = formatted
        } else {
            pretty = data
        }
        remoteWriteData(pretty, to: locator.projectsRegistry)
    }

    // MARK: - Dashboard

    func loadDashboard(for project: ProjectEntry) -> ProjectDashboard? {
        guard let data = remoteReadData(project.dashboardPath) else { return nil }
        do {
            return try JSONDecoder().decode(ProjectDashboard.self, from: data)
        } catch {
            Self.logger.error("Failed to decode remote dashboard for \(project.name): \(error.localizedDescription)")
            return nil
        }
    }

    func dashboardExists(for project: ProjectEntry) -> Bool {
        let script = "test -e \(SSHSessionConfig.shellQuote(project.dashboardPath)) && echo 1 || echo 0"
        let result = runner.run([
            "sh", "-c", SSHSessionConfig.wrapForRemoteShell(script)
        ], timeout: 10)
        return result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    func dashboardModificationDate(for project: ProjectEntry) -> Date? {
        // Try Linux `stat -c`, fall back to macOS `stat -f`; swallow both on non-existent file.
        let script = "stat -c %Y \(SSHSessionConfig.shellQuote(project.dashboardPath)) 2>/dev/null || stat -f %m \(SSHSessionConfig.shellQuote(project.dashboardPath)) 2>/dev/null"
        let result = runner.run([
            "sh", "-c", SSHSessionConfig.wrapForRemoteShell(script)
        ], timeout: 10)
        guard result.succeeded else { return nil }
        let trimmed = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let epoch = TimeInterval(trimmed), epoch > 0 else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    // MARK: - Helpers

    /// Direct `cat -- <path>` via argv — no `sh -c` wrapper so SSH doesn't
    /// re-tokenize away the file argument.
    private nonisolated func remoteReadData(_ path: String) -> Data? {
        let result = runner.run([
            "cat", "--", SSHSessionConfig.shellQuote(path)
        ])
        return result.succeeded ? result.stdout : nil
    }

    private nonisolated func remoteWriteData(_ data: Data, to path: String) {
        let parent = (path as NSString).deletingLastPathComponent
        let script = "mkdir -p \(SSHSessionConfig.shellQuote(parent)) && cat > \(SSHSessionConfig.shellQuote(path))"
        _ = runner.run([
            "sh", "-c", SSHSessionConfig.wrapForRemoteShell(script)
        ], stdin: data)
    }
}
