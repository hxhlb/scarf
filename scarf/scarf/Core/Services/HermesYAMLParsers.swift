import Foundation

/// Shared YAML parsers for Hermes config + skill descriptors.
/// Extracted from the file-service layer so Local and Remote implementations
/// can both call them without duplicating the parse logic.
enum HermesYAMLParsers {
    /// Parse a `~/.hermes/config.yaml` document into a typed `HermesConfig`.
    nonisolated static func parseConfig(_ yaml: String) -> HermesConfig {
        var values: [String: String] = [:]
        var currentSection = ""
        var dockerEnv: [String: String] = [:]
        var commandAllowlist: [String] = []
        var inDockerEnv = false
        var inAllowlist = false

        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let indent = line.prefix(while: { $0 == " " }).count

            // Detect end of nested blocks when indent returns to section level
            if indent <= 2 && (inDockerEnv || inAllowlist) {
                inDockerEnv = false
                inAllowlist = false
            }

            if inDockerEnv, indent >= 4, let colonIdx = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let val = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                dockerEnv[key] = val
                continue
            }

            if inAllowlist, indent >= 4, trimmed.hasPrefix("- ") {
                commandAllowlist.append(String(trimmed.dropFirst(2)))
                continue
            }

            if indent == 0 && trimmed.hasSuffix(":") {
                currentSection = String(trimmed.dropLast())
                continue
            }

            if let colonIdx = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let val = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

                if key == "docker_env" && val.isEmpty {
                    inDockerEnv = true
                    continue
                }
                if key == "permanent_allowlist" && val.isEmpty {
                    inAllowlist = true
                    continue
                }

                values[currentSection + "." + key] = val
            }
        }

        return HermesConfig(
            model: values["model.default"] ?? "unknown",
            provider: values["model.provider"] ?? "unknown",
            maxTurns: Int(values["agent.max_turns"] ?? "") ?? 0,
            personality: values["display.personality"] ?? "default",
            terminalBackend: values["terminal.backend"] ?? "local",
            memoryEnabled: values["memory.memory_enabled"] == "true",
            memoryCharLimit: Int(values["memory.memory_char_limit"] ?? "") ?? 0,
            userCharLimit: Int(values["memory.user_char_limit"] ?? "") ?? 0,
            nudgeInterval: Int(values["memory.nudge_interval"] ?? "") ?? 0,
            streaming: values["display.streaming"] != "false",
            showReasoning: values["display.show_reasoning"] == "true",
            verbose: values["agent.verbose"] == "true",
            autoTTS: values["voice.auto_tts"] != "false",
            silenceThreshold: Int(values["voice.silence_threshold"] ?? "") ?? QueryDefaults.defaultSilenceThreshold,
            reasoningEffort: values["agent.reasoning_effort"] ?? "medium",
            showCost: values["display.show_cost"] == "true",
            approvalMode: values["approvals.mode"] ?? "manual",
            browserBackend: values["browser.backend"] ?? "",
            memoryProvider: values["memory.provider"] ?? "",
            dockerEnv: dockerEnv,
            commandAllowlist: commandAllowlist,
            memoryProfile: values["memory.profile"] ?? "",
            serviceTier: values["agent.service_tier"] ?? "normal",
            gatewayNotifyInterval: Int(values["agent.gateway_notify_interval"] ?? "") ?? 600,
            forceIPv4: values["network.force_ipv4"] == "true",
            contextEngine: values["context.engine"] ?? "compressor",
            interimAssistantMessages: values["display.interim_assistant_messages"] != "false",
            honchoInitOnSessionStart: values["honcho.initOnSessionStart"] == "true"
        )
    }

    /// Pull the `required_config:` list out of a skill's `skill.yaml`.
    nonisolated static func parseSkillRequiredConfig(_ content: String) -> [String] {
        var result: [String] = []
        var inRequiredConfig = false
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = line.prefix(while: { $0 == " " }).count
            if trimmed == "required_config:" || trimmed.hasPrefix("required_config:") {
                inRequiredConfig = true
                continue
            }
            if inRequiredConfig {
                if indent < 2 && !trimmed.isEmpty {
                    break
                }
                if trimmed.hasPrefix("- ") {
                    result.append(String(trimmed.dropFirst(2)))
                }
            }
        }
        return result
    }
}
