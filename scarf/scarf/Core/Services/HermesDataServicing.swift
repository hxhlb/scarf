import Foundation

/// Signature every local or remote session/messages data backend must implement.
/// Local = direct SQLite reads against `~/.hermes/state.db`.
/// Remote = HTTP calls through the tunneled Hermes API.
protocol HermesDataServicing: Sendable {
    /// Exposed so callers that need to render paths (UI, diagnostics) can reach
    /// the active locator without knowing the underlying implementation.
    nonisolated var locator: any HermesLocator { get }

    // MARK: - Lifecycle

    func open() async -> Bool
    func close() async

    // MARK: - Session queries

    func fetchSessions(limit: Int) async -> [HermesSession]
    func fetchSessionsInPeriod(since: Date) async -> [HermesSession]
    func fetchSubagentSessions(parentId: String) async -> [HermesSession]
    func fetchSession(id: String) async -> HermesSession?
    func fetchSessionPreviews(limit: Int) async -> [String: String]
    func fetchMostRecentlyActiveSessionId() async -> String?
    func fetchMostRecentlyStartedSessionId(after: Date?) async -> String?

    // MARK: - Message queries

    func fetchMessages(sessionId: String) async -> [HermesMessage]
    func searchMessages(query: String, limit: Int) async -> [HermesMessage]
    func fetchToolResult(callId: String) async -> String?
    func fetchRecentToolCalls(limit: Int) async -> [HermesMessage]
    func fetchMessageFingerprint(sessionId: String) async -> MessageFingerprint
    func fetchMessageCount(sessionId: String) async -> Int

    // MARK: - Stats

    func fetchStats() async -> SessionStats
    func fetchUserMessageCount(since: Date) async -> Int
    func fetchToolUsage(since: Date) async -> [(name: String, count: Int)]
    func fetchSessionStartHours(since: Date) async -> [Int: Int]
    func fetchSessionDaysOfWeek(since: Date) async -> [Int: Int]

    // MARK: - DB metadata

    func stateDBModificationDate() async -> Date?
    nonisolated func stateDBSize() -> Int64?
}

// MARK: - Supporting types (module scope so both Local and Remote implementations
// and external callers can reference them without going through a class type name).

nonisolated struct MessageFingerprint: Equatable, Sendable {
    let count: Int
    let maxId: Int
    let maxTimestamp: Double

    static let empty = MessageFingerprint(count: 0, maxId: 0, maxTimestamp: 0)
}

nonisolated struct SessionStats: Sendable {
    let totalSessions: Int
    let totalMessages: Int
    let totalToolCalls: Int
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCostUSD: Double
    let totalReasoningTokens: Int
    let totalActualCostUSD: Double

    static let empty = SessionStats(
        totalSessions: 0, totalMessages: 0, totalToolCalls: 0,
        totalInputTokens: 0, totalOutputTokens: 0, totalCostUSD: 0,
        totalReasoningTokens: 0, totalActualCostUSD: 0
    )
}
