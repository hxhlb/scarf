---
title: Hermes Version Compatibility Target
type: note
permalink: scarf/integration/hermes-version-compatibility-target
tags:
- hermes
- compatibility
- versioning
source_sha: 427321d742d63298100f9e444f96fd1524d7a46c
source_paths: README.md, CLAUDE.md, scarf/Packages/ScarfCore/Sources/ScarfCore/Services/HermesCapabilities.swift, scarf/scarf/Core/Services/HermesLogService.swift
---

## Observations
- [target] Current Scarf (v2.10) targets Hermes v0.15.0 / v2026.5.28 ("The Velocity Release"). Recommended Hermes version for full feature support. #current
- [compatibility] Minimum supported Hermes: v0.6.0 (2026-03-30). All versions v0.6.0 through v0.15.0 are verified. Older Hermes versions degrade gracefully — new behavior is capability-gated. #minimum
- [schema] Scarf reads Hermes's SQLite state.db and parses CLI output from `hermes status`, `hermes doctor`, `hermes tools`, `hermes sessions`, `hermes gateway`, `hermes pairing`. Automatic schema detection provides backward compatibility. #schema
- [parsing] Log lines may carry an optional `[session_id]` tag between level and logger name; `HermesLogService.parseLine` treats the session tag as an optional capture group so older untagged lines still parse. #logs
- [sync-checklist] On each Hermes bump, keep in sync: `overlayOnlyProviders` / `modelAliases` / `demotedProviders` / `imageGenModels` (vs hermes_cli/providers.py + models.py + xai_retirement.py), the platform roster (vs plugins/platforms/ + gateway/platforms/), and the search/TTS backend lists. #maintenance

## Relations
- implements [[Hermes Capability Gating Pattern]]
- supersedes [[Hermes v0.15 Capability Gating Decisions]]