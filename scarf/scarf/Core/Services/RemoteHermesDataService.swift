import Foundation
import os

/// SSH-backed implementation of `HermesDataServicing`.
///
/// Runs `sqlite3 -json <state.db>` on the remote host and pipes SQL over stdin
/// so we don't have to wrestle with nested shell quoting. Each query round-trips
/// over SSH once; decoded via a small set of `JSONRow` Codable intermediaries that
/// mirror the sqlite3-json output and convert to the model types in one step.
///
/// This is the only remote data backend today — no Hermes-side server process
/// is required, just sshd and sqlite3 on the remote host. If Hermes publishes an
/// HTTP query API in a future release, individual methods can switch to the fast
/// path without changing the facade or ViewModels.
actor RemoteHermesDataService: HermesDataServicing {
    nonisolated let locator: any HermesLocator
    private let runner: SSHCommandRunner
    private let logger = Logger(subsystem: "com.scarf", category: "RemoteHermesDataService")

    private var isOpen = false
    private var hasV07Schema = false

    init(remote: RemoteHermes, locator: any HermesLocator) {
        self.locator = locator
        let transport = RemoteHermesTransport(remote: remote)
        self.runner = SSHCommandRunner(ssh: transport.ssh)
    }

    // MARK: - Lifecycle

    func open() -> Bool {
        if isOpen { return true }
        // Confirm the DB exists + detect schema version in one round-trip.
        let probe = runSQL("PRAGMA table_info(sessions);")
        guard let rows = try? decodeRows([PragmaTableInfoRow].self, from: probe),
              !rows.isEmpty else {
            return false
        }
        hasV07Schema = rows.contains { $0.name == "reasoning_tokens" }
        isOpen = true
        return true
    }

    func close() {
        isOpen = false
        hasV07Schema = false
    }

    // MARK: - Session queries

    private var sessionColumns: String {
        var cols = "id, source, user_id, model, title, parent_session_id, started_at, ended_at, end_reason, message_count, tool_call_count, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, estimated_cost_usd"
        if hasV07Schema {
            cols += ", reasoning_tokens, actual_cost_usd, cost_status, billing_provider"
        }
        return cols
    }

    func fetchSessions(limit: Int) -> [HermesSession] {
        let sql = "SELECT \(sessionColumns) FROM sessions WHERE parent_session_id IS NULL ORDER BY started_at DESC LIMIT \(limit);"
        return fetchSessionRows(sql)
    }

    func fetchSessionsInPeriod(since: Date) -> [HermesSession] {
        let sql = "SELECT \(sessionColumns) FROM sessions WHERE parent_session_id IS NULL AND started_at >= \(since.timeIntervalSince1970) ORDER BY started_at DESC;"
        return fetchSessionRows(sql)
    }

    func fetchSubagentSessions(parentId: String) -> [HermesSession] {
        let sql = "SELECT \(sessionColumns) FROM sessions WHERE parent_session_id = \(Self.sqlQuote(parentId)) ORDER BY started_at ASC;"
        return fetchSessionRows(sql)
    }

    func fetchSession(id: String) -> HermesSession? {
        let sql = "SELECT \(sessionColumns) FROM sessions WHERE id = \(Self.sqlQuote(id)) LIMIT 1;"
        return fetchSessionRows(sql).first
    }

    func fetchSessionPreviews(limit: Int) -> [String: String] {
        let sql = """
            SELECT m.session_id AS session_id, substr(m.content, 1, \(QueryDefaults.previewContentLength)) AS preview
            FROM messages m
            INNER JOIN (
                SELECT session_id, MIN(id) as min_id
                FROM messages
                WHERE role = 'user' AND content <> ''
                GROUP BY session_id
            ) first ON m.id = first.min_id
            ORDER BY m.timestamp DESC
            LIMIT \(limit);
        """
        let data = runSQL(sql)
        guard let rows = try? decodeRows([PreviewRow].self, from: data) else { return [:] }
        var out: [String: String] = [:]
        for r in rows { out[r.session_id] = r.preview ?? "" }
        return out
    }

    func fetchMostRecentlyActiveSessionId() -> String? {
        let data = runSQL("SELECT session_id FROM messages ORDER BY timestamp DESC LIMIT 1;")
        return (try? decodeRows([SessionIdRow].self, from: data))?.first?.session_id
    }

    func fetchMostRecentlyStartedSessionId(after: Date?) -> String? {
        let sql: String
        if let after {
            sql = "SELECT id FROM sessions WHERE parent_session_id IS NULL AND started_at > \(after.timeIntervalSince1970) ORDER BY started_at DESC LIMIT 1;"
        } else {
            sql = "SELECT id FROM sessions WHERE parent_session_id IS NULL ORDER BY started_at DESC LIMIT 1;"
        }
        let data = runSQL(sql)
        return (try? decodeRows([IdRow].self, from: data))?.first?.id
    }

    // MARK: - Message queries

    private var messageColumns: String {
        var cols = "id, session_id, role, content, tool_call_id, tool_calls, tool_name, timestamp, token_count, finish_reason"
        if hasV07Schema {
            cols += ", reasoning"
        }
        return cols
    }

    func fetchMessages(sessionId: String) -> [HermesMessage] {
        let sql = "SELECT \(messageColumns) FROM messages WHERE session_id = \(Self.sqlQuote(sessionId)) ORDER BY timestamp ASC;"
        return fetchMessageRows(sql)
    }

    func searchMessages(query: String, limit: Int) -> [HermesMessage] {
        let sanitized = sanitizeFTSQuery(query)
        guard !sanitized.isEmpty else { return [] }
        let msgCols = messageColumns
            .split(separator: ",")
            .map { "m." + $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: ", ")
        let sql = """
            SELECT \(msgCols)
            FROM messages_fts fts
            JOIN messages m ON m.id = fts.rowid
            WHERE messages_fts MATCH \(Self.sqlQuote(sanitized))
            ORDER BY rank
            LIMIT \(limit);
        """
        return fetchMessageRows(sql)
    }

    func fetchToolResult(callId: String) -> String? {
        let sql = "SELECT content FROM messages WHERE role = 'tool' AND tool_call_id = \(Self.sqlQuote(callId)) LIMIT 1;"
        let data = runSQL(sql)
        return (try? decodeRows([ContentRow].self, from: data))?.first?.content
    }

    func fetchRecentToolCalls(limit: Int) -> [HermesMessage] {
        let sql = "SELECT \(messageColumns) FROM messages WHERE tool_calls IS NOT NULL AND tool_calls != '[]' AND tool_calls != '' ORDER BY timestamp DESC LIMIT \(limit);"
        return fetchMessageRows(sql)
    }

    func fetchMessageFingerprint(sessionId: String) -> MessageFingerprint {
        let sql = "SELECT COUNT(*) AS count, COALESCE(MAX(id), 0) AS maxId, COALESCE(MAX(timestamp), 0.0) AS maxTimestamp FROM messages WHERE session_id = \(Self.sqlQuote(sessionId));"
        let data = runSQL(sql)
        guard let rows = try? decodeRows([FingerprintRow].self, from: data),
              let row = rows.first else { return .empty }
        return MessageFingerprint(count: row.count, maxId: row.maxId, maxTimestamp: row.maxTimestamp)
    }

    func fetchMessageCount(sessionId: String) -> Int {
        let sql = "SELECT COUNT(*) AS count FROM messages WHERE session_id = \(Self.sqlQuote(sessionId));"
        let data = runSQL(sql)
        return (try? decodeRows([CountRow].self, from: data))?.first?.count ?? 0
    }

    // MARK: - Stats

    func fetchStats() -> SessionStats {
        let sql: String
        if hasV07Schema {
            sql = """
                SELECT
                    COUNT(*) AS totalSessions,
                    COALESCE(SUM(message_count),0) AS totalMessages,
                    COALESCE(SUM(tool_call_count),0) AS totalToolCalls,
                    COALESCE(SUM(input_tokens),0) AS totalInputTokens,
                    COALESCE(SUM(output_tokens),0) AS totalOutputTokens,
                    COALESCE(SUM(estimated_cost_usd),0.0) AS totalCostUSD,
                    COALESCE(SUM(reasoning_tokens),0) AS totalReasoningTokens,
                    COALESCE(SUM(actual_cost_usd),0.0) AS totalActualCostUSD
                FROM sessions;
            """
        } else {
            sql = """
                SELECT
                    COUNT(*) AS totalSessions,
                    COALESCE(SUM(message_count),0) AS totalMessages,
                    COALESCE(SUM(tool_call_count),0) AS totalToolCalls,
                    COALESCE(SUM(input_tokens),0) AS totalInputTokens,
                    COALESCE(SUM(output_tokens),0) AS totalOutputTokens,
                    COALESCE(SUM(estimated_cost_usd),0.0) AS totalCostUSD
                FROM sessions;
            """
        }
        let data = runSQL(sql)
        guard let rows = try? decodeRows([StatsRow].self, from: data),
              let row = rows.first else { return .empty }
        return SessionStats(
            totalSessions: row.totalSessions,
            totalMessages: row.totalMessages,
            totalToolCalls: row.totalToolCalls,
            totalInputTokens: row.totalInputTokens,
            totalOutputTokens: row.totalOutputTokens,
            totalCostUSD: row.totalCostUSD,
            totalReasoningTokens: row.totalReasoningTokens ?? 0,
            totalActualCostUSD: row.totalActualCostUSD ?? 0
        )
    }

    func fetchUserMessageCount(since: Date) -> Int {
        let sql = """
            SELECT COUNT(*) AS count FROM messages m
            JOIN sessions s ON m.session_id = s.id
            WHERE m.role = 'user' AND s.parent_session_id IS NULL AND s.started_at >= \(since.timeIntervalSince1970);
        """
        let data = runSQL(sql)
        return (try? decodeRows([CountRow].self, from: data))?.first?.count ?? 0
    }

    func fetchToolUsage(since: Date) -> [(name: String, count: Int)] {
        let sql = """
            SELECT m.tool_name AS name, COUNT(*) AS count
            FROM messages m
            JOIN sessions s ON m.session_id = s.id
            WHERE m.tool_name IS NOT NULL AND m.tool_name <> '' AND s.parent_session_id IS NULL AND s.started_at >= \(since.timeIntervalSince1970)
            GROUP BY m.tool_name
            ORDER BY count DESC;
        """
        let data = runSQL(sql)
        guard let rows = try? decodeRows([ToolUsageRow].self, from: data) else { return [] }
        return rows.map { (name: $0.name ?? "", count: $0.count) }
    }

    func fetchSessionStartHours(since: Date) -> [Int: Int] {
        return aggregateStartedAt(since: since) { ts in
            Calendar.current.component(.hour, from: Date(timeIntervalSince1970: ts))
        }
    }

    func fetchSessionDaysOfWeek(since: Date) -> [Int: Int] {
        return aggregateStartedAt(since: since) { ts in
            (Calendar.current.component(.weekday, from: Date(timeIntervalSince1970: ts)) + 5) % 7
        }
    }

    private func aggregateStartedAt(since: Date, bucket: (Double) -> Int) -> [Int: Int] {
        let sql = "SELECT started_at AS value FROM sessions WHERE parent_session_id IS NULL AND started_at >= \(since.timeIntervalSince1970);"
        let data = runSQL(sql)
        guard let rows = try? decodeRows([TimestampRow].self, from: data) else { return [:] }
        var out: [Int: Int] = [:]
        for row in rows {
            let b = bucket(row.value)
            out[b, default: 0] += 1
        }
        return out
    }

    // MARK: - DB metadata

    func stateDBModificationDate() -> Date? {
        // Take the max of .db and .db-wal mtime so a WAL-only write still shows fresh.
        // `stat -c` is Linux / GNU coreutils; `stat -f` is macOS / BSD. The `||`
        // chain falls through, and `echo 0` keeps the shell expression well-formed
        // when neither succeeds (e.g. file doesn't exist).
        let script = """
            a=$(stat -c %Y \(SSHSessionConfig.shellQuote(locator.stateDB)) 2>/dev/null || stat -f %m \(SSHSessionConfig.shellQuote(locator.stateDB)) 2>/dev/null || echo 0)
            b=$(stat -c %Y \(SSHSessionConfig.shellQuote(locator.stateDB + "-wal")) 2>/dev/null || stat -f %m \(SSHSessionConfig.shellQuote(locator.stateDB + "-wal")) 2>/dev/null || echo 0)
            if [ "$a" -ge "$b" ]; then echo $a; else echo $b; fi
            """
        let result = runner.run([
            "sh", "-c", SSHSessionConfig.wrapForRemoteShell(script)
        ], timeout: 10)
        let trimmed = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let epoch = TimeInterval(trimmed), epoch > 0 else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    nonisolated func stateDBSize() -> Int64? {
        let script = "wc -c < \(SSHSessionConfig.shellQuote(locator.stateDB)) 2>/dev/null"
        let result = runner.run([
            "sh", "-c", SSHSessionConfig.wrapForRemoteShell(script)
        ], timeout: 10)
        guard result.succeeded else { return nil }
        let trimmed = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int64(trimmed)
    }

    // MARK: - SQL runner + decoders

    /// Ship SQL to the remote and return sqlite3's `-json` output as raw bytes.
    /// SQL rides over stdin so we never have to escape it for the remote shell.
    private func runSQL(_ sql: String, timeout: TimeInterval = 30) -> Data {
        let result = runner.run(
            ["sqlite3", "-json", "-readonly", locator.stateDB],
            stdin: Data(sql.utf8),
            timeout: timeout
        )
        if !result.succeeded {
            logger.warning("Remote sqlite3 failed: \(result.stderrString.prefix(200))")
            return Data()
        }
        return result.stdout
    }

    private func decodeRows<T: Decodable>(_ type: [T].Type, from data: Data) throws -> [T] {
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([T].self, from: data)
    }

    private func fetchSessionRows(_ sql: String) -> [HermesSession] {
        let data = runSQL(sql)
        guard let rows = try? decodeRows([JSONSessionRow].self, from: data) else { return [] }
        return rows.map { $0.toModel(hasV07Schema: hasV07Schema) }
    }

    private func fetchMessageRows(_ sql: String) -> [HermesMessage] {
        let data = runSQL(sql)
        guard let rows = try? decodeRows([JSONMessageRow].self, from: data) else { return [] }
        return rows.map { $0.toModel(hasV07Schema: hasV07Schema) }
    }

    // MARK: - String escaping

    /// SQL-quote a string literal by doubling embedded single quotes.
    /// `sqlQuote("O'Brien")` → `'O''Brien'`
    nonisolated static func sqlQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "''") + "'"
    }

    /// Same sanitizer the local service uses — wraps each token in double quotes to
    /// neutralize FTS5 operators in user search input.
    private func sanitizeFTSQuery(_ raw: String) -> String {
        raw.split(separator: " ")
            .map { token in
                let stripped = String(token).replacingOccurrences(of: "\"", with: "")
                return stripped.isEmpty ? nil : "\"\(stripped)\""
            }
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

// MARK: - JSON row types

/// `sqlite3 -json` output for `PRAGMA table_info(...)`.
private nonisolated struct PragmaTableInfoRow: Decodable, Sendable {
    let name: String
}

private nonisolated struct PreviewRow: Decodable, Sendable {
    let session_id: String
    let preview: String?
}

private nonisolated struct SessionIdRow: Decodable, Sendable {
    let session_id: String
}

private nonisolated struct IdRow: Decodable, Sendable {
    let id: String
}

private nonisolated struct ContentRow: Decodable, Sendable {
    let content: String
}

private nonisolated struct CountRow: Decodable, Sendable {
    let count: Int
}

private nonisolated struct TimestampRow: Decodable, Sendable {
    let value: Double
}

private nonisolated struct ToolUsageRow: Decodable, Sendable {
    let name: String?
    let count: Int
}

private nonisolated struct FingerprintRow: Decodable, Sendable {
    let count: Int
    let maxId: Int
    let maxTimestamp: Double
}

private nonisolated struct StatsRow: Decodable, Sendable {
    let totalSessions: Int
    let totalMessages: Int
    let totalToolCalls: Int
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCostUSD: Double
    let totalReasoningTokens: Int?
    let totalActualCostUSD: Double?
}

/// Mirrors the session column list the Local service pulls from SQLite.
/// Column names match the DB schema (snake_case) because `sqlite3 -json` uses them
/// as JSON keys.
private nonisolated struct JSONSessionRow: Decodable, Sendable {
    let id: String
    let source: String
    let user_id: String?
    let model: String?
    let title: String?
    let parent_session_id: String?
    let started_at: Double?
    let ended_at: Double?
    let end_reason: String?
    let message_count: Int
    let tool_call_count: Int
    let input_tokens: Int
    let output_tokens: Int
    let cache_read_tokens: Int
    let cache_write_tokens: Int
    let estimated_cost_usd: Double?
    let reasoning_tokens: Int?
    let actual_cost_usd: Double?
    let cost_status: String?
    let billing_provider: String?

    func toModel(hasV07Schema: Bool) -> HermesSession {
        HermesSession(
            id: id,
            source: source,
            userId: user_id,
            model: model,
            title: title,
            parentSessionId: parent_session_id,
            startedAt: started_at.map { Date(timeIntervalSince1970: $0) },
            endedAt: ended_at.map { Date(timeIntervalSince1970: $0) },
            endReason: end_reason,
            messageCount: message_count,
            toolCallCount: tool_call_count,
            inputTokens: input_tokens,
            outputTokens: output_tokens,
            cacheReadTokens: cache_read_tokens,
            cacheWriteTokens: cache_write_tokens,
            estimatedCostUSD: estimated_cost_usd,
            reasoningTokens: hasV07Schema ? (reasoning_tokens ?? 0) : 0,
            actualCostUSD: hasV07Schema ? actual_cost_usd : nil,
            costStatus: hasV07Schema ? cost_status : nil,
            billingProvider: hasV07Schema ? billing_provider : nil
        )
    }
}

private nonisolated struct JSONMessageRow: Decodable, Sendable {
    let id: Int
    let session_id: String
    let role: String
    let content: String
    let tool_call_id: String?
    let tool_calls: String?
    let tool_name: String?
    let timestamp: Double?
    let token_count: Int?
    let finish_reason: String?
    let reasoning: String?

    func toModel(hasV07Schema: Bool) -> HermesMessage {
        let calls = parseToolCalls(tool_calls)
        return HermesMessage(
            id: id,
            sessionId: session_id,
            role: role,
            content: content,
            toolCallId: tool_call_id,
            toolCalls: calls,
            toolName: tool_name,
            timestamp: timestamp.map { Date(timeIntervalSince1970: $0) },
            tokenCount: token_count,
            finishReason: finish_reason,
            reasoning: hasV07Schema ? reasoning : nil
        )
    }

    private func parseToolCalls(_ json: String?) -> [HermesToolCall] {
        guard let json, !json.isEmpty,
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([HermesToolCall].self, from: data)) ?? []
    }
}
