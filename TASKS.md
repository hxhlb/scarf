# Tasks

> Repo-resident task board managed by Memophant and Claude sessions. Move items between
> sections as work progresses; checklist state mirrors the section.

## Todo


## Doing


## Done

- [x] P1 — Capabilities gate diagnostic: HermesCapabilitiesPanel in Health view + foreground re-detection on app-active. Verified `hermes --version` returns `Hermes Agent v0.15.1 (2026.5.29)` and parses correctly — root cause of empty slash menu is pre-session collapse (P2), not gate failure. (completed: 2026-05-29)
- [x] P2 — Slash menu: pre-session shows the full agent-command set greyed-out with tooltip "Available once a chat is open" instead of collapsing to just `/new`. `disabledSlashCommandNames` gained `hasActiveSession`; `availableCommands` no longer filters `/steer` on session presence. 36 SlashMenuLogicTests pass including 2 new pre-session cases. (completed: 2026-05-29)
- [x] P3 — New-project wizard hand-off: structured `SKILL:` / `PROJECT_PATH:` kickoff prompt that agents recognize as an invocation marker (vs. the old polite "use the skill" sentence); `SkillBootstrapService.ensureBundledSkillsInstalled()` preflight in `NewProjectViewModel.commit()` guarantees the bundled skill is on disk before `session/new` so Hermes loads it on session start. (completed: 2026-05-29)
- [x] P4 — AGENTS.md `scarf-project` block: appended a "Scarf platform reference" section covering dashboard widget vocabulary, project-scoped slash commands, Kanban tenant convention, model presets, typed config schema, cron jobs, skill loading, and template export — so the agent knows what Scarf can do beyond bare Hermes. `ProjectTemplateInstaller` now also refreshes the block on install (previously only chat-start did). 13 ProjectAgentContextServiceTests pass including secret-safety + byte-idempotency; 7 ProjectTemplateInstallerTests pass. (completed: 2026-05-29)

