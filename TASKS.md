# Tasks

> Repo-resident task board managed by Memophant and Claude sessions. Move items between
> sections as work progresses; checklist state mirrors the section.

## Todo

- [ ] Edit existing remote server connections (id: t-edit-srv) (source: gh#105 part 2) (added: 2026-06-02)
- [ ] Scarf v2.9.1 - 100% CPU usage on single core — pending ScarfMon ring-buffer JSON from reporter to identify the loop subsystem (id: t-82d62d) (source: gh#102) (added: 2026-06-02)

## Doing


## Done

- [x] iOS: chat "connection failed" on app-switcher round-trip — `pauseInBackground` demotes `.ready → .reconnecting(0/max)`; `verifyAndResume` drives `attemptReconnect` directly when client is nil; reconnect success clears stale `acpError`; in-flight send catch restores draft text on backgrounding-induced failure (id: t-7ab110) (source: gh#108) (completed: 2026-06-02)
- [x] iOS: send-button silent no-op + missing keyboard-dismiss button after app-switcher — same `pauseInBackground` fix as gh#108; hoisted `.toolbar(.keyboard)` from TextField subtree to body-root (iOS 26.5 stopped surfacing keyboard-placement toolbars declared deep in composer subtrees) (id: t-2d876e) (source: gh#107) (completed: 2026-06-02)
- [x] macOS: manual "Hermes binary" override in Add Remote Server (Advanced disclosure) — user-supplied `hermesBinaryHint` wins over the auto-probe; TestConnectionProbe sources login rc files and resolves the hint's first token via `command -v` before falling back to surfacing the hint verbatim. Edit-server affordance still open (id: t-8c6da7) (source: gh#105 part 1) (completed: 2026-06-02)
- [x] P1 — Capabilities gate diagnostic: HermesCapabilitiesPanel in Health view + foreground re-detection on app-active. Verified `hermes --version` returns `Hermes Agent v0.15.1 (2026.5.29)` and parses correctly — root cause of empty slash menu is pre-session collapse (P2), not gate failure. (completed: 2026-05-29)
- [x] P2 — Slash menu: pre-session shows the full agent-command set greyed-out with tooltip "Available once a chat is open" instead of collapsing to just `/new`. `disabledSlashCommandNames` gained `hasActiveSession`; `availableCommands` no longer filters `/steer` on session presence. 36 SlashMenuLogicTests pass including 2 new pre-session cases. (completed: 2026-05-29)
- [x] P3 — New-project wizard hand-off: structured `SKILL:` / `PROJECT_PATH:` kickoff prompt that agents recognize as an invocation marker (vs. the old polite "use the skill" sentence); `SkillBootstrapService.ensureBundledSkillsInstalled()` preflight in `NewProjectViewModel.commit()` guarantees the bundled skill is on disk before `session/new` so Hermes loads it on session start. (completed: 2026-05-29)
- [x] P4 — AGENTS.md `scarf-project` block: appended a "Scarf platform reference" section covering dashboard widget vocabulary, project-scoped slash commands, Kanban tenant convention, model presets, typed config schema, cron jobs, skill loading, and template export — so the agent knows what Scarf can do beyond bare Hermes. `ProjectTemplateInstaller` now also refreshes the block on install (previously only chat-start did). 13 ProjectAgentContextServiceTests pass including secret-safety + byte-idempotency; 7 ProjectTemplateInstallerTests pass. (completed: 2026-05-29)
