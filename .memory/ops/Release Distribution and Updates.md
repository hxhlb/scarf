---
title: Release Distribution and Updates
type: note
permalink: scarf/ops/release-distribution-and-updates
tags:
- release
- sparkle
- distribution
source_sha: 427321d742d63298100f9e444f96fd1524d7a46c
source_paths: scripts/release.sh, README.md
---

## Observations
- [distribution] Releases ship two zips: `Scarf-vX.X.X-Universal.zip` (arm64 + x86_64) and `Scarf-vX.X.X-ARM64.zip` (Apple Silicon only). Both are Developer ID signed and notarized. #binaries
- [auto-update] Sparkle handles auto-updates: appcast on `gh-pages` branch, EdDSA-signed entries. Users can disable or trigger manual checks from Settings → General → Updates or the menu bar icon. #sparkle
- [credentials] Release prerequisites (Alan's machine): Developer ID Application cert (team `3Q6X2L86C4`) in login Keychain, notarytool keychain profile `scarf-notary`, Sparkle EdDSA private key in Keychain item `https://sparkle-project.org`, `gh-pages` branch + GitHub Pages enabled. #credentials
- [gatekeeper] If Gatekeeper rejects on first launch ("Scarf.app is damaged"), only remove the quarantine xattr — never strip all xattrs or re-sign. Every release passes `codesign --verify --strict --deep` and `spctl --assess --type execute`. #troubleshooting

## Relations
- extends [[Build and Release Workflow]]