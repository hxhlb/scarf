import Foundation

/// Public facade for session/messages data. Dispatches to `LocalHermesDataService`
/// (direct SQLite against `~/.hermes/state.db`) or `RemoteHermesDataService`
/// (`ssh host sqlite3 -json -readonly` with SQL on stdin) based on the connection.
///
/// Callers `await` every method — the facade hops through to the backing actor.
/// Default init reads from `ConnectionProvider.current`.
struct HermesDataService: Sendable {
    let impl: any HermesDataServicing

    /// Bind to whichever Hermes is currently active. Default init consults
    /// `ConnectionProvider.current` so VMs constructed fresh after a connection
    /// switch (`.id(activeConnection)` rebuild in the view tree) automatically
    /// pick up the new target — no per-VM env plumbing required.
    init(connection: HermesConnection = ConnectionProvider.current) {
        switch connection {
        case .local:
            self.impl = LocalHermesDataService()
        case .remote(let r):
            self.impl = RemoteHermesDataService(
                remote: r,
                locator: RemoteHermesLocator.forRemote(r)
            )
        }
    }

    /// Escape hatch for callers that need the locator (path display, diagnostics).
    nonisolated var locator: any HermesLocator { impl.locator }

    // MARK: - Lifecycle

    func open() async -> Bool { await impl.open() }
    func close() async { await impl.close() }

    // MARK: - Session queries

    func fetchSessions(limit: Int = QueryDefaults.sessionLimit) async -> [HermesSession] {
        await impl.fetchSessions(limit: limit)
    }
    func fetchSessionsInPeriod(since: Date) async -> [HermesSession] {
        await impl.fetchSessionsInPeriod(since: since)
    }
    func fetchSubagentSessions(parentId: String) async -> [HermesSession] {
        await impl.fetchSubagentSessions(parentId: parentId)
    }
    func fetchSession(id: String) async -> HermesSession? {
        await impl.fetchSession(id: id)
    }
    func fetchSessionPreviews(limit: Int = QueryDefaults.sessionPreviewLimit) async -> [String: String] {
        await impl.fetchSessionPreviews(limit: limit)
    }
    func fetchMostRecentlyActiveSessionId() async -> String? {
        await impl.fetchMostRecentlyActiveSessionId()
    }
    func fetchMostRecentlyStartedSessionId(after: Date? = nil) async -> String? {
        await impl.fetchMostRecentlyStartedSessionId(after: after)
    }

    // MARK: - Message queries

    func fetchMessages(sessionId: String) async -> [HermesMessage] {
        await impl.fetchMessages(sessionId: sessionId)
    }
    func searchMessages(query: String, limit: Int = QueryDefaults.messageSearchLimit) async -> [HermesMessage] {
        await impl.searchMessages(query: query, limit: limit)
    }
    func fetchToolResult(callId: String) async -> String? {
        await impl.fetchToolResult(callId: callId)
    }
    func fetchRecentToolCalls(limit: Int = QueryDefaults.toolCallLimit) async -> [HermesMessage] {
        await impl.fetchRecentToolCalls(limit: limit)
    }
    func fetchMessageFingerprint(sessionId: String) async -> MessageFingerprint {
        await impl.fetchMessageFingerprint(sessionId: sessionId)
    }
    func fetchMessageCount(sessionId: String) async -> Int {
        await impl.fetchMessageCount(sessionId: sessionId)
    }

    // MARK: - Stats

    func fetchStats() async -> SessionStats {
        await impl.fetchStats()
    }
    func fetchUserMessageCount(since: Date) async -> Int {
        await impl.fetchUserMessageCount(since: since)
    }
    func fetchToolUsage(since: Date) async -> [(name: String, count: Int)] {
        await impl.fetchToolUsage(since: since)
    }
    func fetchSessionStartHours(since: Date) async -> [Int: Int] {
        await impl.fetchSessionStartHours(since: since)
    }
    func fetchSessionDaysOfWeek(since: Date) async -> [Int: Int] {
        await impl.fetchSessionDaysOfWeek(since: since)
    }

    // MARK: - DB metadata

    func stateDBModificationDate() async -> Date? { await impl.stateDBModificationDate() }
    nonisolated func stateDBSize() -> Int64? { impl.stateDBSize() }
}
