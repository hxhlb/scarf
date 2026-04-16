import Foundation

/// Signature every ACP client must implement.
///
/// Unlike the other services, ACP does NOT need a Local/Remote split. The concrete
/// `ACPClient` is transport-polymorphic: when constructed with a `RemoteHermesTransport`
/// it spawns `ssh user@host hermes acp` and pipes stdio over the SSH connection; the
/// actor itself handles both cases identically. This protocol exists for testability
/// and to document the contract a future transport (e.g. WebSocket) would need to meet.
protocol ACPClienting: Actor {
    var isConnected: Bool { get }
    var currentSessionId: String? { get }
    var statusMessage: String { get }
    var isHealthy: Bool { get }
    var events: AsyncStream<ACPEvent> { get }

    func start() async throws
    func stop() async

    func newSession(cwd: String) async throws -> String
    func loadSession(cwd: String, sessionId: String) async throws -> String
    func resumeSession(cwd: String, sessionId: String) async throws -> String

    func sendPrompt(sessionId: String, text: String) async throws -> ACPPromptResult
    func cancel(sessionId: String) async throws
    func respondToPermission(requestId: Int, optionId: String)
}
