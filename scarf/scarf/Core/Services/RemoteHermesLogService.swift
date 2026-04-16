import Foundation
import os

/// SSH-backed implementation of `HermesLogServicing`.
///
/// Local version maintains a `FileHandle` and reads `availableData` push-style.
/// Over SSH we can't keep a remote file handle across calls, so we track a byte
/// offset and use `tail -c +<offset+1>` to fetch new bytes on each poll. Initial
/// window comes from `tail -n <count>`.
actor RemoteHermesLogService: HermesLogServicing {
    private let runner: SSHCommandRunner
    private var currentPath: String?
    private var currentOffset: Int = 0
    private var entryCounter = 0
    private let logger = Logger(subsystem: "com.scarf", category: "RemoteHermesLogService")

    init(remote: RemoteHermes) {
        let transport = RemoteHermesTransport(remote: remote)
        self.runner = SSHCommandRunner(ssh: transport.ssh)
    }

    func openLog(path: String) {
        currentPath = path
        currentOffset = remoteFileSize(path) ?? 0
    }

    func closeLog() {
        currentPath = nil
        currentOffset = 0
    }

    func readLastLines(count: Int) -> [LogEntry] {
        guard let path = currentPath else { return [] }
        let script = "tail -n \(count) \(SSHSessionConfig.shellQuote(path)) 2>/dev/null"
        let result = runner.run([
            "sh", "-c", SSHSessionConfig.wrapForRemoteShell(script)
        ])
        guard result.succeeded else { return [] }
        let lines = result.stdoutString
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        return lines.map { line in
            entryCounter += 1
            return HermesLogParser.parse(line, id: entryCounter)
        }
    }

    func readNewLines() -> [LogEntry] {
        guard let path = currentPath else { return [] }
        // `tail -c +N` reads starting at byte N (1-indexed). We want bytes AFTER
        // the last offset we saw, so start at offset+1.
        let script = "tail -c +\(currentOffset + 1) \(SSHSessionConfig.shellQuote(path)) 2>/dev/null"
        let result = runner.run([
            "sh", "-c", SSHSessionConfig.wrapForRemoteShell(script)
        ])
        guard result.succeeded, !result.stdout.isEmpty else { return [] }
        currentOffset += result.stdout.count
        let lines = result.stdoutString
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        return lines.map { line in
            entryCounter += 1
            return HermesLogParser.parse(line, id: entryCounter)
        }
    }

    func seekToEnd() {
        guard let path = currentPath else { return }
        currentOffset = remoteFileSize(path) ?? currentOffset
    }

    /// `wc -c < path` is POSIX-portable (Linux + macOS) and avoids `stat`'s
    /// platform-specific format flags.
    private func remoteFileSize(_ path: String) -> Int? {
        let script = "wc -c < \(SSHSessionConfig.shellQuote(path)) 2>/dev/null"
        let result = runner.run([
            "sh", "-c", SSHSessionConfig.wrapForRemoteShell(script)
        ])
        guard result.succeeded else { return nil }
        return Int(result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
