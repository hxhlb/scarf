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

**Memory engine.** Memophant ships an in-repo native MCP server (`memophant-mcp`) that
replaces the basic-memory CLI as the primary read/write surface. When the server is
registered with this client, the tools below show up directly — call them rather than
shelling out. basic-memory remains installed during the transition window as fallback
(handy when you need bm-only features the native server hasn't ported yet).

- Native MCP tools (preferred): `search_notes`, `read_note`, `view_note`, `write_note`,
  `edit_note`, `move_note`, `delete_note`, `list_directory`, `list_memory_projects`,
  `recent_activity`, `build_context`. All accept a `project` argument (default
  scarf). Tool shapes match basic-memory's 1:1 so prompts targeting bm work
  unchanged.
- Fallback (only if the MCP tools above are not present in this session):
  `basic-memory tool search-notes --project scarf "<query>"` and friends.

**1. Basic Memory (`.memory/`) — structured atomic facts.** A searchable knowledge graph
of observations and relations. Search it before assuming; it is the source of truth for past
decisions and learnings.
- Search: invoke `search_notes(query: "<text>", project: "scarf")` via MCP.
- Record durable facts/decisions as you work: `write_note(title, content, folder, project: "scarf")`
  (they're committed with the repo and visible to every session).
- Grammar: each note is markdown with `## Observations` (`- [category] fact text #tag`) and
  `## Relations` (`- relation_type [[Target Note]]`).
- Reindex happens automatically after every write_note / edit_note; for direct file edits,
  use the Memophant app's "Reindex" action or restart the MCP server.
- Optional provenance frontmatter — `source_paths` (repo files a note depends on) + `source_sha`
  (HEAD when written) — lets Memory Health flag the note when that code later changes.

**2. Wiki (`wiki/`) — long-form reference docs.** Guides, architecture deep-dives, runbooks, and
design notes. Deliberately kept OUT of this auto-loaded file to save context — search it on demand
rather than reading it wholesale.
- Search: `search_notes(query: "<text>", project: "scarf-wiki")` via MCP, or grep:
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
- Search: `search_notes(query: "<text>", project: "scarf-design")` via MCP, or grep:
  `grep -rn "<query>" design/`.
- Plain `.md` files (any name) — add your own or import a design skill; no special structure required.

**4. Code (`code/` + `memophant code` CLI) — structural queries, not blind grep.** The code layer
gives every session a queryable map of THIS repo's source. Two halves: curated `code/` markdown
overviews (module purpose, key types, public surface) for orientation, and an indexed SQLite map
of symbols/imports under `.memophant/code/` (gitignored) for sub-second structural queries.
**Prefer `memophant code <verb>` over `grep` for any structural question** — it's deterministic,
cheap, and saves context. Fall back to `grep` only when the index is stale (see `status`), the
language isn't yet supported (Phase 1 indexes Swift only), or you need a verb that's still Phase 2
(refs / callers / callees).
- **Invocation:** Memophant installs a project-local shim at `./.memophant/code/memophant`. Use
  `memophant code <verb>` if it's on your PATH, otherwise `./.memophant/code/memophant code <verb>`
  from the repo root. (One-time PATH install: `ln -s "$(pwd)/.memophant/code/memophant" ~/.local/bin/memophant`.)
- Find a symbol: `memophant code find <SymbolName>` → file:line of every definition.
- Find references: `memophant code refs <SymbolName>` → every call/use site.
- File outline: `memophant code outline <path>` → the symbol tree inside a file.
- Imports: `memophant code imports <path>` → what a file imports + what imports a file.
- Semantic / curated search: `memophant code search "<intent>"` → FTS over symbols + curated notes.
- Index health: `memophant code status` → `clean | n files stale | rebuilding`, plus HEAD drift.
- Curated overviews: `search_notes(query: "<text>", project: "scarf-code")` via MCP, or
  `grep -rn "<query>" code/`. Authored as markdown like wiki/design pages — module purposes,
  architecture maps, "where to start when touching X".
- Symbols + curated notes both surface under `memophant code search`; use it as the default
  structural-discovery verb when you don't already know the symbol name.

**5. Tasks (`TASKS.md`) — the work board.** A repo-resident kanban in plain Markdown: `## Todo`,
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
