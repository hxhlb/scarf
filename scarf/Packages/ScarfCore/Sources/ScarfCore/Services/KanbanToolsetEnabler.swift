import Foundation
#if canImport(os)
import os
#endif

/// Mutates the `kanban` toolset on/off for a given Hermes platform.
/// Wraps `hermes tools enable kanban --platform <name>` so callers
/// don't have to learn the CLI shape.
///
/// **Why a separate actor from `KanbanToolsetDetector`.** Read paths
/// run on every chat appear; mutation paths run once per onboarding
/// flow. Keeping them as separate actors means the detector's read
/// loop never blocks on a write txn — important since Hermes's
/// `tools enable` shells out and can take ~500ms on cold starts.
public actor KanbanToolsetEnabler {
    #if canImport(os)
    private static let logger = Logger(
        subsystem: "com.scarf",
        category: "KanbanToolsetEnabler"
    )
    #endif

    public enum EnableResult: Sendable, Equatable {
        /// CLI exited 0. The caller should refresh the detector and
        /// (if appropriate) post a "Restart your chat to pick this up"
        /// hint — the agent's tool list is fixed at session start, so
        /// existing chats keep their stale schema.
        case enabled
        /// CLI exited non-zero or wasn't reachable. The associated
        /// message is the trimmed stderr (or transport error) so
        /// callers can surface it inline rather than a generic "an
        /// error occurred."
        case failed(message: String)
    }

    private let context: ServerContext

    public init(context: ServerContext) {
        self.context = context
    }

    /// Enable the `kanban` toolset on the given platform. Default `cli`
    /// is what ACP chats run under, so the common path is
    /// `enabler.enable()` with no args.
    public func enable(platform: String = "cli") async -> EnableResult {
        await runToolsCommand(action: "enable", platform: platform)
    }

    public func disable(platform: String = "cli") async -> EnableResult {
        await runToolsCommand(action: "disable", platform: platform)
    }

    private func runToolsCommand(
        action: String,
        platform: String
    ) async -> EnableResult {
        let context = self.context
        let result: EnableResult = await Task.detached(priority: .utility) {
            let transport = context.makeTransport()
            let executable = context.paths.hermesBinary
            do {
                let proc = try transport.runProcess(
                    executable: executable,
                    args: ["tools", action, "kanban", "--platform", platform],
                    stdin: nil,
                    timeout: 15
                )
                if proc.exitCode == 0 {
                    return .enabled
                }
                let stderr = proc.stderrString.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let stdout = proc.stdoutString.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let message = stderr.isEmpty
                    ? (stdout.isEmpty ? "exit \(proc.exitCode)" : stdout)
                    : stderr
                return .failed(message: message)
            } catch let error as TransportError {
                let diag = error.diagnosticStderr.isEmpty
                    ? (error.errorDescription ?? "transport error")
                    : error.diagnosticStderr
                return .failed(message: diag)
            } catch {
                return .failed(message: error.localizedDescription)
            }
        }.value
        #if canImport(os)
        switch result {
        case .enabled:
            Self.logger.info("kanban toolset \(action, privacy: .public) ok on \(platform, privacy: .public)")
        case .failed(let message):
            Self.logger.warning("kanban toolset \(action, privacy: .public) failed on \(platform, privacy: .public): \(message, privacy: .public)")
        }
        #endif
        return result
    }
}
