import Foundation

/// Local file-tailing implementation of `HermesLogServicing`.
/// Opens the given path with `FileHandle(forReadingAtPath:)` and incrementally
/// reads new bytes via `availableData`. Parses each line into a `LogEntry`.
actor LocalHermesLogService: HermesLogServicing {
    private var fileHandle: FileHandle?
    private var currentPath: String?
    private var entryCounter = 0

    func openLog(path: String) {
        closeLog()
        currentPath = path
        fileHandle = FileHandle(forReadingAtPath: path)
    }

    func closeLog() {
        do {
            try fileHandle?.close()
        } catch {
            print("[Scarf] Failed to close log handle: \(error.localizedDescription)")
        }
        fileHandle = nil
        currentPath = nil
    }

    func readLastLines(count: Int) -> [LogEntry] {
        guard let path = currentPath,
              let data = FileManager.default.contents(atPath: path) else { return [] }
        let content = String(data: data, encoding: .utf8) ?? ""
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        let lastLines = Array(lines.suffix(count))
        return lastLines.map { parseLine($0) }
    }

    func readNewLines() -> [LogEntry] {
        guard let handle = fileHandle else { return [] }
        let data = handle.availableData
        guard !data.isEmpty else { return [] }
        let content = String(data: data, encoding: .utf8) ?? ""
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.map { parseLine($0) }
    }

    func seekToEnd() {
        fileHandle?.seekToEndOfFile()
    }

    private func parseLine(_ line: String) -> LogEntry {
        entryCounter += 1
        return HermesLogParser.parse(line, id: entryCounter)
    }
}
