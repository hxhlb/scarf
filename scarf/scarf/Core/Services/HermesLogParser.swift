import Foundation

/// Parser for Hermes log lines (v0.9.0+ format).
///
/// Format: `YYYY-MM-DD HH:MM:SS,MMM LEVEL [session_id] logger: message`
/// The `[session_id]` tag is optional — earlier releases and out-of-session
/// lines omit it, so the parser treats it as optional via `(?:...)?` group.
enum HermesLogParser {
    nonisolated(unsafe) private static let regex: NSRegularExpression? = {
        let pattern = #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3})\s+(DEBUG|INFO|WARNING|ERROR|CRITICAL)\s+(?:\[([^\]]+)\]\s+)?(\S+?):\s+(.*)$"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    /// Parse one log line. `id` is assigned by the caller (service keeps a counter).
    /// Unparseable lines become level `.info` with empty timestamp and the raw line
    /// as the message.
    nonisolated static func parse(_ line: String, id: Int) -> LogEntry {
        if let regex,
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            let timestamp = String(line[Range(match.range(at: 1), in: line)!])
            let levelStr = String(line[Range(match.range(at: 2), in: line)!])
            let sessionId: String? = {
                let range = match.range(at: 3)
                guard range.location != NSNotFound, let r = Range(range, in: line) else { return nil }
                return String(line[r])
            }()
            let logger = String(line[Range(match.range(at: 4), in: line)!])
            let message = String(line[Range(match.range(at: 5), in: line)!])
            return LogEntry(
                id: id,
                timestamp: timestamp,
                level: LogEntry.LogLevel(rawValue: levelStr) ?? .info,
                sessionId: sessionId,
                logger: logger,
                message: message,
                raw: line
            )
        }
        return LogEntry(id: id, timestamp: "", level: .info, sessionId: nil, logger: "", message: line, raw: line)
    }
}
