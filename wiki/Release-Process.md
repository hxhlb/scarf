---
title: Release-Process
type: note
permalink: scarf-wiki/release-process
---

# Release Process

> **Two release tracks as of v2.5.** The Mac app ships through GitHub Releases + Sparkle (this page). ScarfGo (iOS) ships through TestFlight / App Store Connect — see [`releases/v<version>/TESTFLIGHT_CHECKLIST.md`](https://github.com/awizemann/scarf/blob/main/releases/v2.5.0/TESTFLIGHT_CHECKLIST.md) and [`APP_STORE_METADATA.md`](https://github.com/awizemann/scarf/blob/main/releases/v2.5.0/APP_STORE_METADATA.md). The two tracks are independent and don't share a single command — they share the version number by convention.

Mac releases are produced by a single local script: [`scripts/release.sh`](https://github.com/awizemann/scarf/blob/main/scripts/release.sh) in the main repo. **The script is the source of truth** — this page is a public-facing summary; do not duplicate prerequisites or step-by-step internals here.

## Modes

```bash
./scripts/release.sh <VERSION>           # full release: notarize → appcast → gh-pages → tag
./scripts/release.sh <VERSION> --draft   # builds + notarizes, but skips appcast/tag
```

A full release bumps the version, archives Universal (arm64 + x86_64) + ARM64-only variants, signs with Developer ID, notarizes via `xcrun notarytool`, staples, EdDSA-signs the appcast entry with Sparkle's key, pushes the appcast to `gh-pages`, and creates a GitHub release with both zips attached.

**Post-package verification gate** _(v2.5.1+)._ After every variant's final `ditto`, the script extracts the packaged zip into a temp dir and runs `codesign --verify --strict --deep --verbose=4` + `spctl --assess --type execute --verbose` on the extracted bundle. Either failure aborts the release. This catches any regression in the shipped artifact (stapler edge cases, post-staple modifications, framework-seal drift) before users see "Scarf.app is damaged" reports — issue [#49](https://github.com/awizemann/scarf/issues/49).

A draft release stops after the GitHub release is uploaded, so the current version stays "latest" until explicitly promoted.

## Release notes

Notes go in `releases/v<VERSION>/RELEASE_NOTES.md` **before** running the script. The script auto-includes the file in the version-bump commit and uses it as the GitHub release body. If absent, a placeholder is used.

## Promotion (draft → real)

After running with `--draft`:

1. Edit the GitHub release → uncheck **Set as draft** → Publish.
2. Push the bump commit: `git push origin main`.
3. Tag and push: `git tag v<VERSION> && git push origin v<VERSION>`.
4. Merge the appcast entry (`releases/v<VERSION>/appcast-entry.xml`) into `gh-pages` `appcast.xml`, commit, push.

## Sparkle signing key

Releases are EdDSA-signed by Sparkle. The private key lives in the user's macOS Keychain under `https://sparkle-project.org`; the public key is embedded in `Info.plist` as `SUPublicEDKey`. **If the private key is lost, no installed Scarf can ever update again.** There is no recovery — every existing user would have to manually download a new build.

## Where things live

- Release script: [`scripts/release.sh`](https://github.com/awizemann/scarf/blob/main/scripts/release.sh) (full prerequisites in the file header)
- Per-version notes + appcast entry: `releases/v<version>/`
- Appcast feed: `https://awizemann.github.io/scarf/appcast.xml`
- Releases page: <https://github.com/awizemann/scarf/releases>

## After a full release

- Bump the **Latest release** line on [Home](Home).
- Append the new version to [Release Notes Index](Release-Notes-Index).
- If the version includes ScarfGo changes: separately archive + upload via Xcode Organizer per [`TESTFLIGHT_CHECKLIST.md`](https://github.com/awizemann/scarf/blob/main/releases/v2.5.0/TESTFLIGHT_CHECKLIST.md). The Mac release script doesn't touch iOS.

## iOS release flow (separate from `release.sh`)

ScarfGo ships through:

1. **Xcode → Product → Archive** for the `scarf mobile` scheme (Any iOS Device destination).
2. **Organizer → Distribute App → App Store Connect → Upload** — automatic re-sign.
3. App Store Connect processes the binary (~5–15 min). Once ready, add it to a TestFlight group + submit for **Beta App Review** (24–48h queue).
4. After Beta Review approval, the public TestFlight URL ([testflight.apple.com/join/qCrRpcTz](https://testflight.apple.com/join/qCrRpcTz)) accepts new joiners. Until then it shows "not accepting new testers."
5. Public App Store submission is a separate review (24–72h) using the same processed build — see [`APP_STORE_METADATA.md`](https://github.com/awizemann/scarf/blob/main/releases/v2.5.0/APP_STORE_METADATA.md) for the description, keywords, support URL, and privacy URL fields.

The iOS `MARKETING_VERSION` should match the Mac `MARKETING_VERSION` for the same release; the iOS `CURRENT_PROJECT_VERSION` (build number) increments independently per Apple's monotonic-build-number rule. There's no automation for iOS bumping yet — manual edit in the Xcode target before archiving.

---
_Last updated: 2026-04-27 — Scarf v2.5.1 (post-package verification gate)_