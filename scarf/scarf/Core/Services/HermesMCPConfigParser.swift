import Foundation

/// Pure-value YAML parser and patcher for the `mcp_servers:` block in `config.yaml`.
/// All methods are `nonisolated static` so both local and remote service implementations
/// can call them without actor isolation concerns.
nonisolated enum HermesMCPConfigParser {

    // MARK: - Block location

    private struct MCPBlockLocation {
        let prefix: [String]
        let block: [String]   // includes the "mcp_servers:" header line
        let suffix: [String]
    }

    private nonisolated static func extractMCPBlock(yaml: String) -> MCPBlockLocation {
        let lines = yaml.components(separatedBy: "\n")
        var blockStart = -1
        var blockEnd = lines.count
        for (index, line) in lines.enumerated() {
            if blockStart < 0 {
                if line.hasPrefix("mcp_servers:") {
                    blockStart = index
                }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = line.prefix(while: { $0 == " " }).count
            if indent == 0 && trimmed.contains(":") {
                blockEnd = index
                break
            }
        }
        if blockStart < 0 {
            return MCPBlockLocation(prefix: lines, block: [], suffix: [])
        }
        return MCPBlockLocation(
            prefix: Array(lines[0..<blockStart]),
            block: Array(lines[blockStart..<blockEnd]),
            suffix: Array(lines[blockEnd..<lines.count])
        )
    }

    // MARK: - Parser

    /// Parse the `mcp_servers:` block from a full YAML string into model objects.
    nonisolated static func parseMCPServersBlock(yaml: String) -> [HermesMCPServer] {
        let location = extractMCPBlock(yaml: yaml)
        guard location.block.count > 1 else { return [] }

        var servers: [HermesMCPServer] = []

        var currentName: String?
        var fields: [String: String] = [:]
        var argsList: [String] = []
        var envMap: [String: String] = [:]
        var headersMap: [String: String] = [:]
        var includeList: [String] = []
        var excludeList: [String] = []
        var resources = false
        var prompts = false
        var subSection: String?

        func flush() {
            guard let name = currentName else { return }
            let transport: MCPTransport = fields["url"] != nil ? .http : .stdio
            let enabledStr = fields["enabled"]?.lowercased()
            let enabled = enabledStr != "false"
            let timeout = fields["timeout"].flatMap(Int.init)
            let connectTimeout = fields["connect_timeout"].flatMap(Int.init)
            let server = HermesMCPServer(
                name: name,
                transport: transport,
                command: fields["command"].map { unquote($0) },
                args: argsList,
                url: fields["url"].map { unquote($0) },
                auth: fields["auth"].map { unquote($0) },
                env: envMap,
                headers: headersMap,
                timeout: timeout,
                connectTimeout: connectTimeout,
                enabled: enabled,
                toolsInclude: includeList,
                toolsExclude: excludeList,
                resourcesEnabled: resources,
                promptsEnabled: prompts,
                hasOAuthToken: false
            )
            servers.append(server)

            currentName = nil
            fields = [:]
            argsList = []
            envMap = [:]
            headersMap = [:]
            includeList = []
            excludeList = []
            resources = false
            prompts = false
            subSection = nil
        }

        for rawLine in location.block.dropFirst() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = rawLine.prefix(while: { $0 == " " }).count

            if indent == 2 && trimmed.hasSuffix(":") && !trimmed.contains(" ") {
                flush()
                currentName = String(trimmed.dropLast())
                subSection = nil
                continue
            }

            guard currentName != nil else { continue }

            if indent == 4 {
                if trimmed.hasPrefix("- ") && subSection == "args" {
                    argsList.append(unquote(String(trimmed.dropFirst(2))))
                    continue
                }
                subSection = nil
                if trimmed.hasSuffix(":") {
                    subSection = String(trimmed.dropLast())
                    continue
                }
                if let colonIdx = trimmed.firstIndex(of: ":") {
                    let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                    let value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    fields[key] = value
                }
                continue
            }

            if indent >= 6 {
                switch subSection {
                case "args":
                    if trimmed.hasPrefix("- ") {
                        argsList.append(unquote(String(trimmed.dropFirst(2))))
                    }
                case "env":
                    if let colonIdx = trimmed.firstIndex(of: ":") {
                        let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                        let value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                        envMap[key] = unquote(value)
                    }
                case "headers":
                    if let colonIdx = trimmed.firstIndex(of: ":") {
                        let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                        let value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                        headersMap[key] = unquote(value)
                    }
                case "tools":
                    if trimmed == "include:" {
                        subSection = "tools.include"
                    } else if trimmed == "exclude:" {
                        subSection = "tools.exclude"
                    } else if trimmed.hasPrefix("resources:") {
                        resources = trimmed.lowercased().hasSuffix("true")
                    } else if trimmed.hasPrefix("prompts:") {
                        prompts = trimmed.lowercased().hasSuffix("true")
                    }
                case "tools.include":
                    if trimmed.hasPrefix("- ") {
                        includeList.append(unquote(String(trimmed.dropFirst(2))))
                    }
                case "tools.exclude":
                    if trimmed.hasPrefix("- ") {
                        excludeList.append(unquote(String(trimmed.dropFirst(2))))
                    }
                default:
                    break
                }
            }
        }

        flush()
        return servers
    }

    // MARK: - Test output parser

    /// Extract tool names from `hermes mcp test` CLI output.
    nonisolated static func parseToolListFromTestOutput(_ output: String) -> [String] {
        var tools: [String] = []
        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { continue }
            let candidate = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            // Take only the identifier before any separator (":" or whitespace).
            let token = candidate.split(whereSeparator: { ":(".contains($0) || $0.isWhitespace }).first.map(String.init) ?? candidate
            if !token.isEmpty, token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
                tools.append(token)
            }
        }
        return tools
    }

    // MARK: - Patcher

    /// Locate the entry for `name` inside the `mcp_servers:` block, let `mutate` modify its
    /// lines, then return the full patched YAML string.  Returns `nil` when the entry is not found.
    nonisolated static func patchMCPServerField(
        yaml: String,
        name: String,
        mutate: (inout [String]) -> Void
    ) -> String? {
        let location = extractMCPBlock(yaml: yaml)
        guard !location.block.isEmpty else { return nil }

        var block = location.block

        var entryStart = -1
        var entryEnd = block.count
        for (index, line) in block.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix(while: { $0 == " " }).count
            if entryStart < 0 {
                if indent == 2 && trimmed == "\(name):" {
                    entryStart = index
                }
                continue
            }
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if indent <= 2 {
                entryEnd = index
                break
            }
        }
        guard entryStart >= 0 else { return nil }

        var entryLines = Array(block[entryStart..<entryEnd])
        mutate(&entryLines)

        block.replaceSubrange(entryStart..<entryEnd, with: entryLines)

        var combined: [String] = []
        combined.append(contentsOf: location.prefix)
        combined.append(contentsOf: block)
        combined.append(contentsOf: location.suffix)
        return combined.joined(separator: "\n")
    }

    // MARK: - YAML mutators

    nonisolated static func replaceOrInsertScalar(key: String, value: String, in lines: inout [String]) {
        // entry header is at lines[0] at indent 2. Scalars live at indent 4.
        for index in 1..<lines.count {
            let line = lines[index]
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if indent == 4, trimmed.hasPrefix(key + ":") || trimmed == key + ":" {
                lines[index] = "    \(key): \(value)"
                return
            }
            if indent <= 2 && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                break
            }
        }
        // Insert right after header.
        lines.insert("    \(key): \(value)", at: 1)
    }

    nonisolated static func removeScalar(key: String, in lines: inout [String]) {
        var removeIndex: Int?
        for index in 1..<lines.count {
            let line = lines[index]
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if indent == 4, trimmed.hasPrefix(key + ":") || trimmed == key + ":" {
                removeIndex = index
                break
            }
            if indent <= 2 && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                break
            }
        }
        if let removeIndex {
            lines.remove(at: removeIndex)
        }
    }

    nonisolated static func replaceOrInsertList(header: String, items: [String], in lines: inout [String]) {
        var headerIndex: Int?
        var removeEnd: Int?
        for index in 1..<lines.count {
            let line = lines[index]
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if indent == 4 && trimmed == "\(header):" {
                headerIndex = index
                continue
            }
            if headerIndex != nil {
                // List items can appear at indent 4 (as "    - item") OR indent 6 depending on style.
                if trimmed.hasPrefix("- ") && indent >= 4 {
                    continue
                } else if trimmed.isEmpty || trimmed.hasPrefix("#") {
                    continue
                } else if indent >= 6 {
                    continue
                } else {
                    removeEnd = index
                    break
                }
            }
        }

        if items.isEmpty {
            if let headerIndex, let end = removeEnd {
                lines.removeSubrange(headerIndex..<end)
            } else if let headerIndex {
                lines.removeSubrange(headerIndex..<lines.count)
            }
            return
        }

        var newLines: [String] = ["    \(header):"]
        for item in items {
            newLines.append("    - \(yamlScalar(item))")
        }

        if let headerIndex {
            let end = removeEnd ?? lines.count
            lines.replaceSubrange(headerIndex..<end, with: newLines)
        } else {
            var insertAt = lines.count
            for index in 1..<lines.count {
                let line = lines[index]
                let indent = line.prefix(while: { $0 == " " }).count
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if indent <= 2 && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    insertAt = index
                    break
                }
            }
            lines.insert(contentsOf: newLines, at: insertAt)
        }
    }

    nonisolated static func replaceOrInsertSubMap(header: String, map: [String: String], in lines: inout [String]) {
        var headerIndex: Int?
        var removeEnd: Int?
        for index in 1..<lines.count {
            let line = lines[index]
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if indent == 4 && trimmed == "\(header):" {
                headerIndex = index
                continue
            }
            if headerIndex != nil {
                if indent >= 6 {
                    continue
                } else if trimmed.isEmpty || trimmed.hasPrefix("#") {
                    continue
                } else {
                    removeEnd = index
                    break
                }
            }
        }

        var newLines: [String] = []
        if map.isEmpty {
            if let headerIndex, let end = removeEnd {
                lines.removeSubrange(headerIndex..<end)
            } else if let headerIndex {
                lines.removeSubrange(headerIndex..<lines.count)
            }
            return
        }

        newLines.append("    \(header):")
        for key in map.keys.sorted() {
            let value = map[key] ?? ""
            newLines.append("      \(key): \(yamlScalar(value))")
        }

        if let headerIndex {
            let end = removeEnd ?? lines.count
            lines.replaceSubrange(headerIndex..<end, with: newLines)
        } else {
            // Insert just before the first indent<=2 line we find after the header, else at end.
            var insertAt = lines.count
            for index in 1..<lines.count {
                let line = lines[index]
                let indent = line.prefix(while: { $0 == " " }).count
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if indent <= 2 && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    insertAt = index
                    break
                }
            }
            lines.insert(contentsOf: newLines, at: insertAt)
        }
    }

    nonisolated static func replaceOrInsertToolsBlock(
        include: [String],
        exclude: [String],
        resources: Bool,
        prompts: Bool,
        in lines: inout [String]
    ) {
        var headerIndex: Int?
        var removeEnd: Int?
        for index in 1..<lines.count {
            let line = lines[index]
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if indent == 4 && trimmed == "tools:" {
                headerIndex = index
                continue
            }
            if headerIndex != nil {
                if indent >= 6 {
                    continue
                } else if trimmed.isEmpty || trimmed.hasPrefix("#") {
                    continue
                } else {
                    removeEnd = index
                    break
                }
            }
        }

        var newLines: [String] = ["    tools:"]
        newLines.append("      include:")
        for tool in include { newLines.append("        - \(yamlScalar(tool))") }
        newLines.append("      exclude:")
        for tool in exclude { newLines.append("        - \(yamlScalar(tool))") }
        newLines.append("      resources: \(resources ? "true" : "false")")
        newLines.append("      prompts: \(prompts ? "true" : "false")")

        if let headerIndex {
            let end = removeEnd ?? lines.count
            lines.replaceSubrange(headerIndex..<end, with: newLines)
        } else {
            var insertAt = lines.count
            for index in 1..<lines.count {
                let line = lines[index]
                let indent = line.prefix(while: { $0 == " " }).count
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if indent <= 2 && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    insertAt = index
                    break
                }
            }
            lines.insert(contentsOf: newLines, at: insertAt)
        }
    }

    // MARK: - Scalar helpers

    nonisolated static func yamlScalar(_ value: String) -> String {
        if value.isEmpty { return "\"\"" }
        let needsQuoting = value.contains(":") || value.contains("#") || value.contains("\"")
            || value.hasPrefix(" ") || value.hasSuffix(" ") || value.hasPrefix("-")
            || ["true", "false", "null", "yes", "no"].contains(value.lowercased())
        if needsQuoting {
            let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }

    nonisolated static func unquote(_ value: String) -> String {
        var v = value
        if (v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2) || (v.hasPrefix("'") && v.hasSuffix("'") && v.count >= 2) {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }
}
