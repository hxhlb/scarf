import Foundation
import os

/// Stateless configuration for opening SSH connections to a remote host.
///
/// Each `makeProcess(remoteCommand:)` call produces a fresh `Process` that runs
/// `/usr/bin/ssh` with control-master multiplexing enabled — the first invocation
/// establishes a long-lived master connection at `controlPath`, and subsequent
/// invocations reuse it so there's only one TCP handshake per connection.
///
/// `shutdownMaster()` tears down the master explicitly — call it on app quit or
/// when swapping active connections so stale master sockets don't accumulate.
nonisolated struct SSHSessionConfig: Sendable, Equatable {
    let host: String
    let user: String
    let port: Int
    let identityFile: String?
    let controlPath: String
    let aliveInterval: Int

    init(
        host: String,
        user: String,
        port: Int = 22,
        identityFile: String? = nil,
        controlPath: String,
        aliveInterval: Int = 30
    ) {
        self.host = host
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.controlPath = controlPath
        self.aliveInterval = aliveInterval
    }

    var sshTarget: String { "\(user)@\(host)" }

    /// Flags that should appear on every `ssh` invocation using this session —
    /// control-master multiplexing, keepalive, and (optionally) the identity file.
    var baseArgs: [String] {
        var args = [
            "-T",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=5m",
            "-o", "ServerAliveInterval=\(aliveInterval)",
            "-o", "ServerAliveCountMax=3",
            "-o", "BatchMode=yes",
            "-p", String(port)
        ]
        if let identityFile, !identityFile.isEmpty {
            args += ["-i", identityFile]
        }
        return args
    }

    /// Construct a ready-to-run `Process` that runs `ssh <flags> user@host <remoteCommand...>`.
    ///
    /// `remoteCommand` is passed to the remote user's login shell as a single command line —
    /// tokens are forwarded individually via argv, but the remote shell will still re-tokenize.
    /// For arguments that can contain spaces or shell metacharacters, quote them upstream.
    func makeProcess(remoteCommand: [String]) -> Process {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        proc.arguments = baseArgs + [sshTarget] + remoteCommand
        return proc
    }

    /// Close the control-master connection. Best-effort; errors are logged and swallowed.
    func shutdownMaster() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        proc.arguments = [
            "-o", "ControlPath=\(controlPath)",
            "-O", "exit",
            sshTarget
        ]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            Logger(subsystem: "com.scarf", category: "SSHSessionConfig")
                .warning("shutdownMaster failed: \(error.localizedDescription)")
        }
    }

    /// Default directory for control-master sockets. Permissions are tightened to 0700
    /// because a writable socket would let any local user multiplex over the connection.
    static var defaultControlPathDirectory: String {
        NSHomeDirectory() + "/.scarf/ssh"
    }

    /// Ensure the control-master directory exists with mode 0700. Call once at startup
    /// before the first SSH process spawns.
    @discardableResult
    static func ensureControlPathDirectory() -> Bool {
        let dir = defaultControlPathDirectory
        do {
            try FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            // createDirectory won't re-tighten perms on an existing dir, so enforce here.
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir)
            return true
        } catch {
            Logger(subsystem: "com.scarf", category: "SSHSessionConfig")
                .error("Failed to create control-path directory \(dir): \(error.localizedDescription)")
            return false
        }
    }

    /// Control-path file for a specific remote. Keep it short — macOS unix socket paths
    /// are capped at 104 chars, and OpenSSH further reserves room for the `%C` hash suffix.
    static func controlPath(for remoteId: UUID) -> String {
        // Use first 8 chars of UUID to stay well under the 104-char socket limit.
        let shortId = remoteId.uuidString.prefix(8)
        return defaultControlPathDirectory + "/m-\(shortId)"
    }

    /// Wrap a single argument in POSIX single quotes, escaping embedded single quotes
    /// using the `'\''` idiom. Use this for any value interpolated into a remote
    /// shell command — paths, SQL, search queries — otherwise the remote login
    /// shell will re-tokenize on spaces / special chars.
    ///
    /// Note: single quotes suppress variable expansion. Don't use this on strings
    /// that contain `$HOME` or other shell variables you want expanded — those
    /// should be pre-resolved to absolute paths before quoting.
    ///
    /// Example: `shellQuote("O'Brien")` → `'O'\''Brien'`
    static func shellQuote(_ arg: String) -> String {
        "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Wrap an entire shell script so it survives SSH's argv-flattening intact.
    ///
    /// When Swift's `Process` calls `ssh host sh -c <script>`, ssh joins all argv
    /// elements with spaces into a single line and sends that to the remote login
    /// shell. The remote shell then tokenizes *again* — which means a naked
    /// `sh -c "cat -- '/path'"` argv gets split into 5 tokens, and `sh -c` only
    /// sees `cat` as its script (no file arg, reads stdin, returns empty).
    ///
    /// This helper wraps the whole script in outer single quotes, escaping inner
    /// single quotes with the POSIX `'\''` trick, so the remote shell re-assembles
    /// the script into a single `sh -c` argument.
    ///
    /// Usage: `runner.run(["sh", "-c", SSHSessionConfig.wrapForRemoteShell(inner)])`.
    static func wrapForRemoteShell(_ innerScript: String) -> String {
        "'" + innerScript.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
