---
title: Scarf Project Layout
type: note
permalink: scarf/architecture/scarf-project-layout
tags:
- layout
- paths
source_sha: 6fb7fd2c33ce792fdcfa792583438e96f9fd5c81
reviewed: 2026-05-29
---

## Observations
- [path] Xcode project: scarf/scarf.xcodeproj — open with Xcode 16.0+ #build
- [path] Main app source: scarf/scarf/ with subdirs Core/Services, Core/Models, Features/<Name>, Navigation/ #source
- [path] Core/Services (Mac-specific): ACPClient+Mac, HermesFileService, HermesFileWatcher, HermesProxyService, ProjectTemplateService, ProjectAgentContextService, NousSubscriptionService, and others #services
- [path] ScarfCore services (cross-platform): HermesDataService, HermesLogService, HermesCapabilities, KanbanService, ModelCatalogService, ModelPresetService, SessionAttributionService, CuratorService, and others #services
- [path] Feature modules under Features/: Activity, Chat, Common, CredentialPools, Cron, Curator, Dashboard, Gateway, Health, Insights, Kanban, Logs, MCPServers, Memory, Models, Personalities, Platforms, Plugins, Profiles, Projects, Proxy, QuickCommands, Servers, Sessions, Settings, Skills, Templates, Tools, Webhooks #features
- [path] ScarfDesign Swift package: scarf/Packages/ScarfDesign/ — shared design tokens for both macOS and iOS targets #design
- [path] ScarfCore Swift package: scarf/Packages/ScarfCore/ — shared services including HermesCapabilities #core
- [path] Internal dev docs (PRD, Architecture, Discovery, I18N): scarf/docs/ — not public #docs
- [path] Standards reference (read-only): scarf/standards/ #docs
- [path] Repo root: BUILDING.md, CLAUDE.md, CONTRIBUTING.md, README.md, releases/, scripts/, site/, templates/, tools/, wiki/, design/ #root

## Relations
- implements [[Scarf Architecture Rules]]