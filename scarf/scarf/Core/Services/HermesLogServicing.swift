import Foundation

/// Signature every local or remote log-tailing service must implement.
/// Local = `FileHandle(forReadingAtPath:)` + `availableData` incremental reads.
/// Remote = `ssh host tail -n <count>` for the initial window, then
/// `ssh host tail -c +<offset>` for incremental reads against a running byte cursor.
protocol HermesLogServicing: Sendable {
    func openLog(path: String) async
    func closeLog() async
    func readLastLines(count: Int) async -> [LogEntry]
    func readNewLines() async -> [LogEntry]
    func seekToEnd() async
}
