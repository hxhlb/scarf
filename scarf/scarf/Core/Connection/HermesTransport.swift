import Foundation

/// Produces `Process` objects that run the `hermes` CLI.
/// The local transport spawns the binary directly; future remote transports will
/// wrap the invocation in `ssh user@host hermes ...` without the caller noticing.
protocol HermesTransport: Sendable {
    /// Absolute path to the `hermes` executable that the next `makeHermesProcess`
    /// call will launch. Nil when no Hermes binary can be located for this transport.
    nonisolated var hermesBinaryPath: String? { get }

    /// Construct a ready-to-run `Process` whose argument list starts with `hermes`
    /// followed by `args`. Pipes / env vars are left to the caller.
    /// Returns nil when no Hermes binary can be located.
    nonisolated func makeHermesProcess(args: [String]) -> Process?
}

/// Default transport that runs `hermes` from the user's local PATH-like search list.
/// Consolidates the binary-resolution fallback in one place: `~/.local/bin/hermes`,
/// then Homebrew paths. Returns nil when none of the candidates exist.
struct LocalHermesTransport: HermesTransport {
    nonisolated init() {}

    nonisolated var hermesBinaryPath: String? {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/hermes",
            "/opt/homebrew/bin/hermes",
            "/usr/local/bin/hermes"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated func makeHermesProcess(args: [String]) -> Process? {
        guard let path = hermesBinaryPath else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        return proc
    }
}
