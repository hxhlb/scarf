---
title: Build and Release Workflow
type: note
permalink: scarf/ops/build-and-release-workflow
tags:
- build
- release
- ci
---

## Observations
- [build] Debug build: `xcodebuild -project scarf/scarf.xcodeproj -scheme scarf -configuration Debug build`. For unsigned CLI debug build without Apple Developer account: ./scripts/local-build.sh #build
- [tooling] Requires Xcode 16.0+ to build from source #tooling
- [release-rule] NEVER run manual `xcodebuild archive` / `notarytool` / `gh release create` steps. Always use ./scripts/release.sh — manual steps skip or misorder critical actions #release #rule
- [release-cmd] Full release: `./scripts/release.sh <version>` — bumps version, archives Universal (arm64+x86_64) and ARM64-only variants, signs with Developer ID, notarizes via xcrun notarytool (keychain profile `scarf-notary`), staples, EdDSA-signs Sparkle appcast, pushes appcast to gh-pages, creates GitHub release with both zips #release
- [release-cmd] Draft release: `./scripts/release.sh <version> --draft` — builds + notarizes + uploads, skips appcast/tag so current version stays 'latest' until promoted #release
- [release-notes] Write release notes to releases/v<version>/RELEASE_NOTES.md BEFORE running the script — auto-included in version-bump commit and used as GitHub release body. Absent → placeholder used #release
- [canonical-prompts] Triggering phrases: 'Release v1.6.2', 'Release v1.6.2 as draft', 'Prepare v1.6.2 release notes from recent commits, then release' #release
- [prereqs] One-time setup on Alan's machine: Developer ID Application cert in login Keychain (team 3Q6X2L86C4), notarytool keychain profile `scarf-notary`, Sparkle EdDSA private key in Keychain item `https://sparkle-project.org`, gh-pages branch + GitHub Pages enabled #setup
- [distribution] Two artifacts per release: Scarf-vX.X.X-Universal.zip (arm64+x86_64) and Scarf-vX.X.X-ARM64.zip (smaller, Apple Silicon only). Auto-updates via Sparkle (daily check + manual) #distribution

## Relations
- documented_in [[Wiki Maintenance Workflow]]