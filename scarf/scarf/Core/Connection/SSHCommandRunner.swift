import Foundation
import os

/// Shared helper for running one-shot commands on the remote host through
/// `SSHSessionConfig`. Captures stdout/stderr, enforces a wall-clock timeout,
/// optionally writes stdin. Every Remote* service funnels its subprocess work
/// through here so timeout handling and process cleanup stay in one place.
nonisolated struct SSHCommandRunner: Sendable {
    let ssh: SSHSessionConfig
    private static let logger = Logger(subsystem: "com.scarf", category: "SSHCommandRunner")

    init(ssh: SSHSessionConfig) {
        self.ssh = ssh
    }

    nonisolated struct Result: Sendable {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data

        var stdoutString: String { String(data: stdout, encoding: .utf8) ?? "" }
        var stderrString: String { String(data: stderr, encoding: .utf8) ?? "" }
        var succeeded: Bool { exitCode == 0 }
    }

    /// Run a remote command. Tokens in `remoteCommand` are passed to SSH as argv;
    /// SSH re-tokenizes them through the remote login shell, so any caller who
    /// needs to preserve spaces or metacharacters in an argument must pre-quote
    /// it with `SSHSessionConfig.shellQuote(_:)`.
    @discardableResult
    func run(
        _ remoteCommand: [String],
        stdin: Data? = nil,
        timeout: TimeInterval = 60
    ) -> Result {
        let process = ssh.makeProcess(remoteCommand: remoteCommand)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        defer {
            try? stdoutPipe.fileHandleForReading.close()
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForWriting.close()
            try? stdinPipe.fileHandleForReading.close()
            try? stdinPipe.fileHandleForWriting.close()
        }

        do {
            try process.run()
        } catch {
            Self.logger.error("ssh spawn failed: \(error.localizedDescription)")
            return Result(
                exitCode: -1,
                stdout: Data(),
                stderr: Data(error.localizedDescription.utf8)
            )
        }

        if let stdin {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: stdin)
        }
        try? stdinPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            Self.logger.warning("ssh command timed out after \(timeout)s: \(remoteCommand.joined(separator: " "))")
        }
        process.waitUntilExit()

        let out = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let err = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return Result(exitCode: process.terminationStatus, stdout: out, stderr: err)
    }
}
