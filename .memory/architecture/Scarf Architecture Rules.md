---
title: Scarf Architecture Rules
type: note
permalink: scarf/architecture/scarf-architecture-rules
tags:
- architecture
- rules
---

## Observations
- [pattern] MVVM-F (Model-View-ViewModel-Feature): each feature is a self-contained module under Features/<Name>/{Views,ViewModels} #mvvm-f
- [rule] Features never import sibling features — cross-feature communication only via Core/Services or AppCoordinator #isolation
- [navigation] Single @Observable AppCoordinator owns all navigation state, injected via .environment() at the app root #navigation
- [dependencies] No external Swift package dependencies in core app — uses system SQLite3, Foundation JSON, AttributedString markdown. Exceptions: SwiftTerm (terminal), Sparkle (updates), Citadel (iOS SSH) #dependencies
- [concurrency] Swift 6 strict concurrency: @MainActor is the default isolation; services use nonisolated + async/await #swift6
- [sandbox] App sandbox is disabled so Scarf can read ~/.hermes/ directly #sandbox
- [data-access] Read-only access to ~/.hermes/state.db (WAL mode). Scarf writes only to memory files (MEMORY.md, USER.md), cron jobs.json, and config.yaml — never to the SQLite DB #db #data
- [code-quality] Zero-warning build required; no commented-out code, TODOs, or deferred functionality in PRs; one feature/fix per PR #quality
- [structure] Xcode project uses PBXFileSystemSynchronizedRootGroup — files auto-discovered from disk, no manual project.pbxproj membership edits needed for new files #xcode

## Relations
- implemented_by [[Scarf Project Layout]]
- relates_to [[Scarf Design System (ScarfDesign)]]