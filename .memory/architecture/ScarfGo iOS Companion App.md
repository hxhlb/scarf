---
title: ScarfGo iOS Companion App
type: note
permalink: scarf/architecture/scarf-go-i-os-companion-app
tags:
- ios
- scarfgo
- ssh
source_sha: 427321d742d63298100f9e444f96fd1524d7a46c
source_paths: README.md, scarf/scarf.xcodeproj/project.pbxproj, scarf/Packages/ScarfDesign
---

## Observations
- [structure] ScarfGo is a separate iOS target (`scarf mobile`) in the same Xcode project. Both `scarf` (Mac) and `scarf mobile` import the shared `ScarfDesign` and `ScarfCore` Swift packages under `scarf/Packages/`. #targets
- [design] ScarfGo uses pure-Swift SSH via Citadel — no `ssh` binary on iOS. Generates Ed25519 keypair on device; private key stored in iOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, excluded from iCloud sync. #security
- [scope] Feature surface: multi-server, project-scoped chat, session resume, memory editor, cron list, skills tree, settings (read-only). All sessions are scoped to a project via the same Scarf-managed AGENTS.md block the Mac app writes. #features
- [distribution] Public TestFlight: https://testflight.apple.com/join/qCrRpcTz . Requires iOS 18.0+. #distribution
- [constraint] iOS Dynamic Type clamped at scene root in `ScarfIOSApp.swift`: `.dynamicTypeSize(.xSmall ... .accessibility2)`. iOS adopts native `.navigationTitle` + `.large` instead of `ScarfPageHeader` on tab roots. #accessibility

## Relations
- relates_to [[iOS Platform Rules]]
- relates_to [[Multi-Server Architecture (Scarf 2.0+)]]
- shares_with [[Scarf Design System (ScarfDesign)]]