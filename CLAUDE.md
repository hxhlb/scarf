# Scarf — macOS GUI for the Hermes AI Agent

## Build

```bash
xcodebuild -project scarf/scarf.xcodeproj -scheme scarf -configuration Debug build
```

<!-- memophant:begin -->
## Memory System (managed by Memophant)

This project uses a layered memory system so any Claude session is productive immediately.
Memophant (a macOS app) manages it, but everything is plain files + the `basic-memory` CLI, so
you can use it directly. This block is regenerated between the `memophant` markers — edit
anything outside them freely.

**Use this repo's memory as the single source of truth — every session, any model.** Read it
before starting work, and record durable decisions and learnings as **Basic Memory notes or wiki
pages** — not in this file, and not in any session-private or model-specific memory — so every
session stays consistent and nothing is lost. Keep CLAUDE.md (and any AGENTS.md / GEMINI.md /
.cursorrules / etc.) **minimal**: a pointer to this system, not a place facts accumulate.

**1. Basic Memory (`.memory/`) — structured atomic facts.** A searchable knowledge graph
of observations and relations. Search it before assuming; it is the source of truth for past
decisions and learnings.
- Search: `basic-memory tool search-notes --project scarf "<query>"` (or the basic-memory MCP).
- Record durable facts/decisions as you work: `basic-memory tool write-note --project scarf …`
  (they're then committed with the repo and visible to every session).
- Grammar: each note is markdown with `## Observations` (`- [category] fact text #tag`) and
  `## Relations` (`- relation_type [[Target Note]]`).
- After editing a note file directly, reindex: `basic-memory reindex --project scarf`.
- Optional provenance frontmatter — `source_paths` (repo files a note depends on) + `source_sha`
  (HEAD when written) — lets Memory Health flag the note when that code later changes.

**2. Wiki (`wiki/`) — long-form reference docs.** Guides, architecture deep-dives, runbooks, and
design notes. Deliberately kept OUT of this auto-loaded file to save context — search it on demand
rather than reading it wholesale.
- Search: `basic-memory tool search-notes --project scarf-wiki "<query>"`, or grep:
  `grep -rn "<query>" wiki/`.
- Pages are markdown with dashed filenames; links are `[Title](Page-Name)`. `Home.md` is the
  landing page and `_Sidebar.md` is the navigation.

**Maintaining the wiki.** Update it when work changes user-visible behavior, adds a feature or
service, changes architecture, or ships a release. Skip for bug fixes with no observable change,
pure refactors, typos, and test-only changes.
- The wiki is meant to be publishable, so every commit/publish runs a mandatory two-tier
  secret-scan (token/key patterns block; secret-like assignments warn). **Never commit secrets to
  the wiki.** Details in `wiki/Wiki-Maintenance.md`.

**3. Design (`design/`) — the design system.** A folder of robust design Markdown (design system,
principles, component specs, UX/HIG conventions) you reference before any UI or design work. Kept
OUT of this auto-loaded file to save context — search it on demand.
- Search: `basic-memory tool search-notes --project scarf-design "<query>"`, or grep:
  `grep -rn "<query>" design/`.
- Plain `.md` files (any name) — add your own or import a design skill; no special structure required.

**4. Tasks (`TASKS.md`) — the work board.** A repo-resident kanban in plain Markdown: `## Todo`,
`## Doing`, `## Done` sections, each a checklist (`- [ ]` / `- [x]`). It travels with the repo and
is yours to edit directly.
- **Read `TASKS.md` at the start of work.** When you pick up a task, move its line into `## Doing`;
  when you finish, move it into `## Done` (and flip the checkbox to `- [x]`).
- Add tasks you discover to `## Todo`. Keep titles short; optional `(source: <note>)` /
  `(added: YYYY-MM-DD)` annotations are preserved.
- Memophant renders this as a live kanban, so your edits to `TASKS.md` show up on the board as you
  work — keep it current.

**Memophant (the app)** is the management surface: browse, search, and edit notes, wiki and design
pages, track and run tasks on the kanban, migrate existing docs into memory, and commit/publish
with the secret-scan.
<!-- memophant:end -->
