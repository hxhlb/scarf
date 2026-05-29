---
title: Scarf Project Layout
type: note
permalink: scarf/architecture/scarf-project-layout
tags:
- layout
- paths
---

## Observations
- [path] Xcode project: scarf/scarf.xcodeproj — open with Xcode 16.0+ #build
- [path] Main app source: scarf/scarf/scarf/ with subdirs Core/Services, Core/Models, Features/<Name>, Navigation/ #source
- [path] Core/Services contains HermesDataService, HermesFileService, HermesLogService, ACPClient, HermesFileWatcher, HermesProxyService, HermesCapabilities #services
- [path] Feature modules under Features/: Dashboard, Sessions, Activity, Chat, Memory, Skills, Cron, Logs, Settings, Platforms, Personalities, QuickCommands, CredentialPools, Plugins, Webhooks, Profiles, Tools, MCPServers, GatewayControl, Health, Insights, Kanban, Proxy #features
- [path] ScarfDesign Swift package: scarf/Packages/ScarfDesign/ — shared design tokens for both macOS and iOS targets #design
- [path] ScarfCore Swift package: scarf/Packages/ScarfCore/ — shared services including HermesCapabilities #core
- [path] Internal dev docs (PRD, Architecture, Discovery, I18N): scarf/docs/ — not public #docs
- [path] Standards reference (read-only): scarf/standards/ #docs
- [path] Repo root: BUILDING.md, CLAUDE.md, CONTRIBUTING.md, README.md, releases/, scripts/, site/, templates/, tools/, wiki/, design/ #root

## Relations
- implements [[Scarf Architecture Rules]]