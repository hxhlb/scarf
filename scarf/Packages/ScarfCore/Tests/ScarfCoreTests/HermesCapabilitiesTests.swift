import Testing
import Foundation
@testable import ScarfCore

/// Pure parser tests for `HermesCapabilities`. The detection store
/// (`HermesCapabilitiesStore`) is exercised separately under integration
/// tests since it spawns `hermes --version`.
@Suite struct HermesCapabilitiesTests {

    // MARK: - Version line parsing

    @Test func parseV013ReleaseLine() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.13.0 (2026.5.7)")
        #expect(caps.semver == HermesCapabilities.SemVer(major: 0, minor: 13, patch: 0))
        #expect(caps.dateVersion == HermesCapabilities.DateVersion(year: 2026, month: 5, day: 7))
        #expect(caps.detected)
    }

    @Test func parseV015ReleaseLine() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.15.0 (2026.5.28)")
        #expect(caps.semver == HermesCapabilities.SemVer(major: 0, minor: 15, patch: 0))
        #expect(caps.dateVersion == HermesCapabilities.DateVersion(year: 2026, month: 5, day: 28))
        #expect(caps.detected)
    }

    @Test func parseV012ReleaseLine() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.12.0 (2026.4.30)")
        #expect(caps.semver == HermesCapabilities.SemVer(major: 0, minor: 12, patch: 0))
        #expect(caps.dateVersion == HermesCapabilities.DateVersion(year: 2026, month: 4, day: 30))
        #expect(caps.detected)
    }

    @Test func parseV011ReleaseLine() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.11.0 (2026.4.23)")
        #expect(caps.semver == HermesCapabilities.SemVer(major: 0, minor: 11, patch: 0))
        #expect(caps.dateVersion == HermesCapabilities.DateVersion(year: 2026, month: 4, day: 23))
    }

    @Test func parseSemverWithoutDate() {
        // Some older Hermes builds emit only the semver suffix.
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.10.5")
        #expect(caps.semver == HermesCapabilities.SemVer(major: 0, minor: 10, patch: 5))
        #expect(caps.dateVersion == nil)
    }

    @Test func parseFullStdoutBlock() {
        // Real `hermes --version` output is multi-line; the version sits on
        // the first line and the rest is metadata.
        let stdout = """
        Hermes Agent v0.12.0 (2026.4.30)
        Project: /Users/alan/.hermes/hermes-agent
        Python: 3.11.15
        OpenAI SDK: 2.31.0
        Up to date
        """
        let caps = HermesCapabilities.parse(stdout)
        #expect(caps.semver?.minor == 12)
        #expect(caps.dateVersion?.year == 2026)
    }

    @Test func parseRejectsUnrelatedOutput() {
        let caps = HermesCapabilities.parse("hermes: command not found")
        #expect(caps.semver == nil)
        #expect(!caps.detected)
    }

    @Test func parseHandlesEmptyString() {
        let caps = HermesCapabilities.parse("")
        #expect(caps == .empty)
    }

    @Test func parseHandlesPartialSemver() {
        // "v0.11" without the patch component shouldn't accidentally match.
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.11")
        #expect(caps.semver == nil)
    }

    // MARK: - SemVer ordering

    @Test func semverOrdering() {
        let v0_11_0 = HermesCapabilities.SemVer(major: 0, minor: 11, patch: 0)
        let v0_12_0 = HermesCapabilities.SemVer(major: 0, minor: 12, patch: 0)
        let v0_12_5 = HermesCapabilities.SemVer(major: 0, minor: 12, patch: 5)
        let v1_0_0 = HermesCapabilities.SemVer(major: 1, minor: 0, patch: 0)
        #expect(v0_11_0 < v0_12_0)
        #expect(v0_12_0 < v0_12_5)
        #expect(v0_12_5 < v1_0_0)
    }

    // MARK: - Capability flags

    @Test func v013FlagsAllOn() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.13.0 (2026.5.7)")
        // v0.12 surfaces remain on.
        #expect(caps.hasCurator)
        #expect(caps.hasKanban)
        #expect(caps.hasACPImagePrompts)
        #expect(!caps.hasFlushMemoriesAux)
        // v0.13 surfaces light up.
        #expect(caps.hasGoals)
        #expect(caps.hasACPQueue)
        #expect(caps.hasACPSteerOnIdle)
        #expect(caps.hasKanbanDiagnostics)
        #expect(caps.hasCuratorArchive)
        #expect(caps.hasGoogleChatPlatform)
        #expect(caps.hasGatewayAllowlists)
        #expect(caps.hasGatewayBusyAckToggle)
        #expect(caps.hasGatewayRestartNotification)
        #expect(caps.hasGatewayList)
        #expect(caps.hasMCPSSETransport)
        #expect(caps.hasCronNoAgent)
        #expect(caps.hasWebToolsBackendSplit)
        #expect(caps.hasProfileNoSkills)
        #expect(caps.hasContextCompressionCount)
        #expect(caps.hasNewWithSessionName)
        #expect(caps.hasUpdateNonInteractive)
        #expect(caps.hasOpenRouterResponseCache)
        #expect(caps.hasImageGenModel)
        #expect(caps.hasDisplayLanguage)
        #expect(caps.hasXAIVoiceCloning)
        #expect(caps.hasVideoAnalyze)
        #expect(caps.hasTransformLLMOutputHook)
        #expect(caps.hasACPSetSessionModel)
    }

    @Test func v012FlagsAllOn() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.12.0 (2026.4.30)")
        // v0.12 surfaces on.
        #expect(caps.hasCurator)
        #expect(caps.hasFallbackCommand)
        #expect(caps.hasKanban)
        #expect(caps.hasOneShot)
        #expect(caps.hasSkillURLInstall)
        #expect(caps.hasACPImagePrompts)
        #expect(caps.hasUpdateCheck)
        #expect(caps.hasPiperTTS)
        #expect(caps.hasVercelTerminal)
        #expect(caps.hasCuratorAux)
        #expect(caps.hasTeamsPlatform)
        #expect(caps.hasYuanbaoPlatform)
        #expect(caps.hasCronWorkdir)
        #expect(caps.hasPromptCacheTTL)
        #expect(caps.hasRedactionToggle)
        // flush_memories was REMOVED in v0.12 — flag inverts.
        #expect(!caps.hasFlushMemoriesAux)
        // v0.13 surfaces stay off on a v0.12 host.
        #expect(!caps.hasGoals)
        #expect(!caps.hasACPQueue)
        #expect(!caps.hasKanbanDiagnostics)
        #expect(!caps.hasCuratorArchive)
        #expect(!caps.hasGoogleChatPlatform)
        #expect(!caps.hasGatewayAllowlists)
        #expect(!caps.hasMCPSSETransport)
        #expect(!caps.hasCronNoAgent)
        #expect(!caps.hasWebToolsBackendSplit)
        #expect(!caps.hasProfileNoSkills)
        #expect(!caps.hasContextCompressionCount)
        #expect(!caps.hasOpenRouterResponseCache)
        #expect(!caps.hasImageGenModel)
        #expect(!caps.hasDisplayLanguage)
        #expect(!caps.hasXAIVoiceCloning)
        #expect(!caps.hasACPSetSessionModel)
    }

    @Test func v011FlagsAllOff() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.11.0 (2026.4.23)")
        #expect(!caps.hasCurator)
        #expect(!caps.hasFallbackCommand)
        #expect(!caps.hasKanban)
        #expect(!caps.hasOneShot)
        #expect(!caps.hasSkillURLInstall)
        #expect(!caps.hasACPImagePrompts)
        #expect(!caps.hasUpdateCheck)
        #expect(!caps.hasPiperTTS)
        #expect(!caps.hasVercelTerminal)
        #expect(!caps.hasCuratorAux)
        #expect(!caps.hasTeamsPlatform)
        #expect(!caps.hasYuanbaoPlatform)
        #expect(!caps.hasCronWorkdir)
        #expect(!caps.hasPromptCacheTTL)
        #expect(!caps.hasRedactionToggle)
        // flush_memories aux row was still alive on v0.11.
        #expect(caps.hasFlushMemoriesAux)
    }

    @Test func emptyCapabilitiesAllOff() {
        // Undetected installs should hide every gated UI surface.
        let caps = HermesCapabilities.empty
        #expect(!caps.hasCurator)
        #expect(!caps.hasFlushMemoriesAux)   // unknown → hide either way
        #expect(!caps.detected)
    }

    @Test func v014FlagsAllOn() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.14.0 (2026.5.16)")
        // v0.12 + v0.13 surfaces remain on.
        #expect(caps.hasCurator)
        #expect(caps.hasACPImagePrompts)
        #expect(caps.hasGoals)
        #expect(caps.hasKanbanDiagnostics)
        #expect(caps.hasCuratorArchive)
        #expect(caps.hasACPSetSessionModel)
        #expect(!caps.hasFlushMemoriesAux)
        // v0.14 slash commands.
        #expect(caps.hasSubgoal)
        #expect(caps.hasYOLOSlashCommand)
        #expect(caps.hasSessionsSlashCommand)
        #expect(caps.hasCodexRuntimeSlashCommand)
        // v0.14 providers.
        #expect(caps.hasGrokOAuthProvider)
        #expect(caps.hasNovitaProvider)
        // v0.14 platforms.
        #expect(caps.hasLINEPlatform)
        #expect(caps.hasSimpleXPlatform)
        // v0.14 web-tool backends.
        #expect(caps.hasBraveFreeSearchBackend)
        #expect(caps.hasDDGSearchBackend)
        // v0.14 config + plugin additions.
        #expect(caps.hasMCPParallelToolCalls)
        #expect(caps.hasDockerExtraArgs)
        #expect(caps.hasDisplayTimestamps)
        #expect(caps.hasCronDeliverAll)
        #expect(caps.hasDiscordHistoryBackfill)
        #expect(caps.hasOpenRouterParetoCoder)
        #expect(caps.hasCustomProviderAPIMode)
        #expect(caps.hasPluginToolOverride)
        // v0.14 new feature surfaces.
        #expect(caps.hasHermesProxy)
        #expect(caps.hasACPSetupBrowser)
        #expect(caps.hasFileMutationVerifier)
        #expect(caps.hasYOLOWarning)
        #expect(caps.hasQwenCloudDisplayName)
        #expect(caps.hasCrossSessionClaudeCache)
        // Convenience predicate.
        #expect(caps.isV014OrLater)
    }

    @Test func v013HostHidesV014Flags() {
        // Every v0.14 flag must stay off on a pristine v0.13 host so the
        // UI degrades silently.
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.13.0 (2026.5.7)")
        #expect(!caps.hasSubgoal)
        #expect(!caps.hasYOLOSlashCommand)
        #expect(!caps.hasSessionsSlashCommand)
        #expect(!caps.hasCodexRuntimeSlashCommand)
        #expect(!caps.hasGrokOAuthProvider)
        #expect(!caps.hasNovitaProvider)
        #expect(!caps.hasLINEPlatform)
        #expect(!caps.hasSimpleXPlatform)
        #expect(!caps.hasBraveFreeSearchBackend)
        #expect(!caps.hasDDGSearchBackend)
        #expect(!caps.hasMCPParallelToolCalls)
        #expect(!caps.hasDockerExtraArgs)
        #expect(!caps.hasDisplayTimestamps)
        #expect(!caps.hasCronDeliverAll)
        #expect(!caps.hasDiscordHistoryBackfill)
        #expect(!caps.hasOpenRouterParetoCoder)
        #expect(!caps.hasCustomProviderAPIMode)
        #expect(!caps.hasPluginToolOverride)
        #expect(!caps.hasHermesProxy)
        #expect(!caps.hasACPSetupBrowser)
        #expect(!caps.hasFileMutationVerifier)
        #expect(!caps.hasYOLOWarning)
        #expect(!caps.hasQwenCloudDisplayName)
        #expect(!caps.hasCrossSessionClaudeCache)
        #expect(!caps.isV014OrLater)
    }

    @Test func v014PatchReleaseStillEnablesAllFlags() {
        // A v0.14.3 patch release should still enable every v0.14 flag.
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.14.3 (2026.6.20)")
        #expect(caps.hasSubgoal)
        #expect(caps.hasGrokOAuthProvider)
        #expect(caps.hasLINEPlatform)
        #expect(caps.hasHermesProxy)
        #expect(caps.isV014OrLater)
    }

    @Test func v0_13_patchReleaseStillEnablesAllFlags() {
        // A v0.13.4 patch release should still enable every v0.13 flag.
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.13.4 (2026.5.20)")
        #expect(caps.hasGoals)
        #expect(caps.hasACPQueue)
        #expect(caps.hasKanbanDiagnostics)
        #expect(caps.hasGoogleChatPlatform)
    }

    @Test func v015FlagsAllOn() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.15.0 (2026.5.28)")
        // Earlier-version surfaces stay on.
        #expect(caps.hasCurator)
        #expect(caps.hasACPImagePrompts)
        #expect(caps.hasGoals)
        #expect(caps.hasKanbanDiagnostics)
        #expect(caps.hasACPSetSessionModel)
        #expect(caps.hasSubgoal)
        #expect(caps.hasYOLOSlashCommand)
        #expect(caps.hasGrokOAuthProvider)
        #expect(caps.hasHermesProxy)
        #expect(caps.hasCrossSessionClaudeCache)
        // v0.15 Kanban surfaces.
        #expect(caps.hasKanbanSessionFilter)
        #expect(caps.hasKanbanV015)
        // v0.15 web + TTS.
        #expect(caps.hasXAIWebSearchBackend)
        #expect(caps.hasXAITTSAutoSpeechTags)
        // v0.15 platform + auth + secrets.
        #expect(caps.hasNtfyPlatform)
        #expect(caps.hasAzureEntraAuth)
        #expect(caps.hasBitwarden)
        // v0.15 verbs.
        #expect(caps.hasHermesAudit)
        #expect(caps.hasXAIModelRetirement)
        // v0.15 MCP + skill surfaces.
        #expect(caps.hasMCPClientCerts)
        #expect(caps.hasMCPCatalog)
        #expect(caps.hasSkillBundles)
        #expect(caps.hasSkillHubFreshness)
        // v0.15 ACP additions.
        #expect(caps.hasSessionEditAutoApproval)
        // Convenience predicate.
        #expect(caps.isV015OrLater)
    }

    @Test func v014HostHidesV015Flags() {
        // Every v0.15 flag must stay off on a pristine v0.14 host so the
        // UI degrades silently. v0.14 flags themselves remain on as a
        // belt-and-braces guard against accidental gate flipping.
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.14.0 (2026.5.16)")
        #expect(!caps.hasKanbanSessionFilter)
        #expect(!caps.hasKanbanV015)
        #expect(!caps.hasXAIWebSearchBackend)
        #expect(!caps.hasNtfyPlatform)
        #expect(!caps.hasXAITTSAutoSpeechTags)
        #expect(!caps.hasAzureEntraAuth)
        #expect(!caps.hasBitwarden)
        #expect(!caps.hasHermesAudit)
        #expect(!caps.hasXAIModelRetirement)
        #expect(!caps.hasMCPClientCerts)
        #expect(!caps.hasMCPCatalog)
        #expect(!caps.hasSkillBundles)
        #expect(!caps.hasSkillHubFreshness)
        #expect(!caps.hasSessionEditAutoApproval)
        #expect(!caps.isV015OrLater)
        // v0.14 surfaces stay alive on a v0.14 host.
        #expect(caps.hasSubgoal)
        #expect(caps.hasHermesProxy)
        #expect(caps.isV014OrLater)
    }

    @Test func v0_15_patchReleaseStillEnablesAllFlags() {
        // v0.15.2 (the latest patch as of 2026-06-05) should still enable
        // every v0.15 flag — patches don't roll back capability gates.
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.15.2 (2026.5.29)")
        #expect(caps.hasKanbanSessionFilter)
        #expect(caps.hasKanbanV015)
        #expect(caps.hasBitwarden)
        #expect(caps.hasMCPCatalog)
        #expect(caps.hasSessionEditAutoApproval)
        #expect(caps.isV015OrLater)
    }

    // MARK: - isV013OrLater convenience predicate

    @Test func isV013OrLater_v013HostTrue() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.13.0 (2026.5.7)")
        #expect(caps.isV013OrLater)
    }

    @Test func isV013OrLater_v012HostFalse() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.12.0 (2026.4.30)")
        #expect(!caps.isV013OrLater)
    }

    @Test func isV013OrLater_emptyFalse() {
        let caps = HermesCapabilities.empty
        #expect(!caps.isV013OrLater)
    }

    @Test func isV013OrLater_v014HostTrue() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.14.0 (2026.5.16)")
        #expect(caps.isV013OrLater)
    }

    // MARK: - isV014OrLater convenience predicate

    @Test func isV014OrLater_v014HostTrue() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.14.0 (2026.5.16)")
        #expect(caps.isV014OrLater)
    }

    @Test func isV014OrLater_v013HostFalse() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.13.0 (2026.5.7)")
        #expect(!caps.isV014OrLater)
    }

    @Test func isV014OrLater_emptyFalse() {
        let caps = HermesCapabilities.empty
        #expect(!caps.isV014OrLater)
    }

    // MARK: - isV015OrLater convenience predicate

    @Test func isV015OrLater_v015HostTrue() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.15.0 (2026.5.28)")
        #expect(caps.isV015OrLater)
    }

    @Test func isV015OrLater_v014HostFalse() {
        let caps = HermesCapabilities.parseLine("Hermes Agent v0.14.0 (2026.5.16)")
        #expect(!caps.isV015OrLater)
    }

    @Test func isV015OrLater_emptyFalse() {
        let caps = HermesCapabilities.empty
        #expect(!caps.isV015OrLater)
    }
}
