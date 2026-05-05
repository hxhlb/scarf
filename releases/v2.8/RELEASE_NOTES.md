## What's in 2.8.0

A focused release on **two project-side gaps** that came up in real use:

1. **Cron jobs can finally use Keychain-backed secrets.** Previously, cron prompts that referenced a `secret`-typed config field got the literal `keychain://...` URI back when reading `config.json`, producing 401s. v2.8 mirrors resolved values into `~/.hermes/.env` under namespaced env-var names, and the bundled skill teaches the agent to reach for them via `$SCARF_<SLUG>_<FIELD>`. Hermes already reloads `.env` per cron tick, so credential rotation is free. ([#75](https://github.com/awizemann/scarf/issues/75)-adjacent.)
2. **New Project from Scratch wizard.** A new toolbar entry that scaffolds a Scarf-standard project skeleton (`<project>/.scarf/dashboard.json` + AGENTS.md marker block), registers it, and hands off to a chat session that activates the bundled `scarf-template-author` skill. The skill drives the substantive setup conversationally — widgets, optional config schema, optional cron — and writes the final files itself.
3. **Bug fix: Configuration form layout recursion** ([#75](https://github.com/awizemann/scarf/issues/75)). Per-stage frame sizes on `ConfigEditorSheet` produced `_NSDetectedLayoutRecursion` for projects whose form transitioned between stages with different intrinsic heights. Fixed by stabilizing the outer frame at the editing stage's intrinsic size so transitions only swap content, never resize the container.

### Cron + Keychain — `$SCARF_<SLUG>_<FIELD>` env vars

Until v2.8, the documented (and broken) pattern for cron prompts that needed a secret looked like:

> *"Read `api_token` from `<project>/.scarf/config.json` and call the API with that as a bearer token."*

Hermes loaded `config.json`, saw `{"api_token": "keychain://com.scarf.template.foo/api_token:abc123"}`, and forwarded the URI as the literal token. The provider returned 401. Hermes has no `keychain://` resolver and doesn't substitute env vars into prompt text — both are intentional design points on the Hermes side.

**v2.8 leans on what Hermes does have**: [`cron/scheduler.py:897-903`](https://github.com/hermes-agent) reloads `~/.hermes/.env` fresh on every cron tick. Anything in that file becomes a real `os.environ` entry the agent can read via the terminal or `code_exec` tool. Scarf now mirrors a project's resolved Keychain values into `~/.hermes/.env` under a marker-bounded block keyed by the template's slug:

```sh
# scarf-secrets:begin local-news-aggregator
SCARF_LOCAL_NEWS_AGGREGATOR_API_TOKEN=actual-value
SCARF_LOCAL_NEWS_AGGREGATOR_RSS_URL=https://example.com/feed
# scarf-secrets:end local-news-aggregator
```

The mirror runs at every state-change point: install, post-install Configuration save, uninstall, "Remove from List", and on app launch (reconciliation pass over registered projects). Source of truth stays in the Keychain — `config.json` keeps `keychain://` URIs unchanged. Mode 0600 enforced on `~/.hermes/.env`, same as the existing `ANTHROPIC_API_KEY` and friends.

**Cron prompts now reference these env vars directly:**

```json
{
  "name": "Daily news digest",
  "schedule": "0 9 * * *",
  "prompt": "Use the terminal: curl -sS -H \"Authorization: Bearer $SCARF_LOCAL_NEWS_AGGREGATOR_API_TOKEN\" \"$SCARF_LOCAL_NEWS_AGGREGATOR_RSS_URL\" -o {{PROJECT_DIR}}/.scarf/feed.xml. Then summarise the top 5 items into {{PROJECT_DIR}}/.scarf/digest.md."
}
```

Naming convention: `SCARF_<UPPER_SLUG>_<UPPER_FIELDKEY>`. Both halves uppercased; non-alphanumerics fold to `_`; leading/trailing/consecutive underscores trimmed. Stable across releases.

#### Migration — existing projects

**Automatic part — no action needed.** On the first launch of v2.8, Scarf walks the project registry and writes a managed block per schemaful project into `~/.hermes/.env`. Idempotent — projects whose values haven't changed produce no write.

**You may need to fix cron prompts you wrote against the old (broken) pattern.** If you have an existing cron job that references a Keychain-backed secret, the prompt will still produce 401s until you update it to use the env-var convention. Two ways:

1. **Manually**, via Scarf's Cron sidebar — open the job, edit the prompt to reference `$SCARF_<UPPER_SLUG>_<UPPER_FIELDKEY>` via the terminal or `code_exec` tool. The bundled `scarf-template-author` skill (now v1.1.0) documents the convention with worked examples.
2. **Via the agent.** With the project loaded in chat, ask: *"Update my Local News cron job's prompt to use the new env var convention."* The skill knows the convention and the project's slug; it'll edit the cron job for you.

We considered an automatic prompt-rewriter on upgrade, but cron prompts are free-form and a heuristic rewrite has a non-trivial chance of breaking custom phrasings. The documented + agent-assisted path is safer for v2.8; we'll revisit a "scan + fix" UI in v2.9 if the docs path doesn't catch users.

#### What about `.env` rotation?

User rotates a secret in Scarf's Configuration sheet → new value lands in the Keychain (via the form's commit step) → Scarf re-mirrors to `~/.hermes/.env` → next cron tick (Hermes reloads `.env` per tick) sees the new value. **No cron-job edit needed.**

### New Project from Scratch wizard

Three project entry points now coexist:

- **Browse Catalog… / Install from File / Install from URL** — install a `.scarftemplate` bundle (existing).
- **Add Project (sidebar `+`)** — register an existing directory by name + path (existing).
- **New Project from Scratch…** — _new_, scaffolds a fresh Scarf-standard project skeleton and hands off to chat for the rest.

The wizard asks for project name, folder name (auto-derived from the name but editable), parent directory, and an optional one-liner about what the project is for. On commit, [`ProjectScaffolder`](../../scarf/scarf/Core/Services/ProjectScaffolder.swift) creates `<parent>/<slug>/.scarf/dashboard.json` (one placeholder text widget) plus a stub `AGENTS.md` (just the Scarf-managed marker block — `ProjectAgentContextService` populates between the markers on first chat). The project is registered in the sidebar before the chat opens.

A new ACP session opens with the project's path as `cwd`, and Scarf auto-sends a kickoff prompt that activates the bundled `scarf-template-author` skill — *"I just created a new Scarf project at /Users/.../local-news. Use the scarf-template-author skill to walk me through configuring it."* The skill drives the substantive setup conversationally: choosing widgets, designing an optional config schema, optionally registering cron jobs, writing AGENTS.md template content. It writes the final `dashboard.json` / `manifest.json` / `AGENTS.md` content in the project directory itself.

The wizard intentionally stays minimal — every "configure" decision lives in the chat handoff, not in the form, because the agent does it better than a multi-step form.

#### Skill bootstrap

The wizard depends on the `scarf-template-author` skill being installed at `~/.hermes/skills/scarf-template-author/`. v2.8 ships a [bundled copy of the skill](../../scarf/scarf/Resources/BuiltinSkills.bundle/scarf-template-author/SKILL.md) inside `Scarf.app/Contents/Resources/BuiltinSkills.bundle/` and copies it into `~/.hermes/skills/` on app launch — idempotent + version-gated, so a user-edited newer destination stays untouched. No Template Author template install required.

### Bug fix — Configuration form layout recursion (#75)

Per-stage frames on `ConfigEditorSheet` (`.loading: 320pt`, `.editing: 480pt`, `.succeeded / .notConfigurable / .failed: 280pt`) caused AppKit to relayout the sheet container mid-flight on stage transitions, producing `_NSDetectedLayoutRecursion` and a blank form. Fixed by stabilizing the outer VStack frame at `560 x 480` (matching `TemplateConfigSheet`'s intrinsic size) so transitions only swap content, never resize the container.

### Schema mirrors

`SecretsEnvBlock` (the marker-block helper for `~/.hermes/.env`) lives in ScarfCore alongside `ProjectContextBlock` (the AGENTS.md helper). Both follow the same shape — `applyBlock` / `removeBlock` operating on bounded marker regions, byte-identity preservation outside the block, idempotent re-apply.

### Compatibility

- macOS 14+ (unchanged).
- Hermes target: still **v2026.4.30 (v0.12.0)**. No new Hermes capability gates added.
- **Mac-only.** ScarfGo (iOS) doesn't have a Keychain-env-mirror story today; the wizard is also Mac-only for v1.
- Existing `~/.hermes/.env` content is preserved byte-identically — Scarf only writes inside its `# scarf-secrets:begin <slug>` / `# scarf-secrets:end <slug>` regions.
- Existing `.scarftemplate` bundles install unchanged. Catalog manifest schemaVersion stays at 1/2/3 — no bump.

### What's deferred

- **Automatic cron-prompt rewriting on upgrade.** Heuristic rewrites of free-form prompts are risky — see "Migration" above for the docs-and-agent path that ships in v2.8. Revisit a "scan + fix" UI in v2.9 if real users miss the migration.
- **iOS New Project wizard + iOS Keychain-env mirror.** ScarfGo's project surface is read-only today; the wizard's chat-handoff pattern depends on Mac-only ACP plumbing.
- **Resolution-layer unit tests.** The `KeychainEnvMirror.mirror(project:)` path that resolves `keychain://` URIs would either pollute the user's login keychain on test runs or require a mock-keychain abstraction; the splice-only seam (`mirror(slug:entries:envPath:)`) is fully unit-tested instead, with the resolution path covered by manual end-to-end verification.
