---
title: Hermes Integration
type: note
permalink: scarf/integration/hermes-integration
tags:
- hermes
- integration
---

## Observations
- [path] Hermes home: ~/.hermes/ — Scarf reads this directly (sandbox disabled) #paths
- [path] Key files: state.db (SQLite WAL, read-only), config.yaml, memories/MEMORY.md, memories/USER.md, sessions/session_*.json, cron/jobs.json, logs/errors.log, logs/gateway.log, .env (secrets), skill-bundles/*.yaml #paths
- [transport] Chat uses ACP (Agent Client Protocol) — `hermes acp` subprocess over stdio JSON-RPC. Remote ACP tunnels as `ssh -T host -- hermes acp` #acp
- [remote] Remote Hermes reached via system SSH (~/.ssh/config, ssh-agent, ProxyJump, ControlMaster). File I/O via scp/sftp. SQLite served from atomic `sqlite3 .backup` snapshots cached in ~/Library/Caches/scarf/snapshots/<server-id>/ #remote
- [remote-reqs] Remote host requires: SSH key-based auth, sqlite3 on PATH, pgrep on PATH, ~/.hermes/ readable by SSH user. Diagnostics sheet runs 14 checks in one SSH session #remote
- [version-target] Current target: Hermes v0.15.0 (v2026.5.28, 'The Velocity Release'). Minimum supported: v0.6.0. All v0.15 surfaces are capability-gated #versioning
- [capability-gating] HermesCapabilities (ScarfCore) detects version once per server connection via `hermes --version` (semver + YYYY.M.D parse), produces HermesCapabilitiesStore injected via .environment() on ContextBoundRoot (Mac) and ScarfGoTabRoot (iOS). UI reads gated flags via typed environment key #capabilities
- [convention] Add a capability flag at the top of HermesCapabilities whenever Scarf gains a release-gated UI surface; group by MARK: v0.X (vYYYY.M.D) flags. Pre-target hosts hide new affordances rather than throw on unknown CLI subcommands #capabilities
- [log-parsing] HermesLogService.parseLine treats the session_id tag between level and logger name as optional — older untagged lines still parse #logs

## Relations
- consumed_by [[Scarf Project Overview]]