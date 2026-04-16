import Foundation

struct LogEntry: Identifiable, Sendable {
    let id: Int
    let timestamp: String
    let level: LogLevel
    let sessionId: String?
    let logger: String
    let message: String
    let raw: String

    enum LogLevel: String, Sendable, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case critical = "CRITICAL"

        var color: String {
            switch self {
            case .debug: return "secondary"
            case .info: return "primary"
            case .warning: return "orange"
            case .error: return "red"
            case .critical: return "red"
            }
        }
    }
}

/// Public facade for log tailing. Dispatches to `LocalHermesLogService` for the
/// local Hermes and `RemoteHermesLogService` (SSH `tail`) for remote connections.
struct HermesLogService: Sendable {
    let impl: any HermesLogServicing

    init(connection: HermesConnection = ConnectionProvider.current) {
        switch connection {
        case .local:
            self.impl = LocalHermesLogService()
        case .remote(let r):
            self.impl = RemoteHermesLogService(remote: r)
        }
    }

    func openLog(path: String) async { await impl.openLog(path: path) }
    func closeLog() async { await impl.closeLog() }
    func readLastLines(count: Int = QueryDefaults.logLineLimit) async -> [LogEntry] {
        await impl.readLastLines(count: count)
    }
    func readNewLines() async -> [LogEntry] { await impl.readNewLines() }
    func seekToEnd() async { await impl.seekToEnd() }
}
