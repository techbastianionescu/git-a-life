---
name: doc
description: Document or audit the current project using a fixed six-file structure (README.md, docs/ARCHITECTURE.md, docs/PRINCIPLES.md, docs/CONVENTIONS.md, docs/CONTEXT.md, docs/decisions/). Invoked by the user typing /doc, optionally with a mode (init, update, audit, decision). Use to bootstrap docs, refresh stale docs, find drift between docs and code, or capture an architectural decision.
---

# /doc — project documentation skill

Produces or maintains documentation under a fixed six-file structure split across four layers: human-readable, decision history, technical reference, and AI session brief. Designed to prevent both under-documentation and over-documentation by giving every piece of information exactly one home.

## Invocation

The user types `/doc` followed by an optional mode:

| Command | What it does |
| --- | --- |
| `/doc` | No mode — show an interactive picker (see "No-mode behavior" below). |
| `/doc init` | First-time setup. Generates the docs scaffold from your current repo. |
| `/doc update` | Refresh existing docs. Compares repo vs. docs, proposes targeted edits where they've drifted. Never edits ADRs. |
| `/doc audit` | Read-only drift check. Lists what's broken, stale, or missing in your docs. Writes nothing. |
| `/doc decision "<title>"` | Log an architectural decision. Asks 4 short questions and creates a new ADR file in `docs/decisions/`. |

If the user passes any other arg, ask once for clarification — do not guess.

### No-mode behavior

When `/doc` is invoked without a mode, do **not** print the modes as plain text. Use the `AskUserQuestion` tool to render an interactive single-select picker. Do not output any preamble before the tool call.

Tool arguments:
- `question`: `"Which /doc mode do you want to run?"`
- `header`: `"/doc mode"` (≤ 12 chars)
- `multiSelect`: `false`
- `options`, in this order:
  - `{ label: "init", description: "First-time setup — generate the docs scaffold from your current repo." }`
  - `{ label: "update", description: "Refresh existing docs to match the current repo. ADRs are never touched." }`
  - `{ label: "audit", description: "Read-only check. Lists what's broken, stale, or missing. Writes nothing." }`
  - `{ label: "decision", description: "Log an architectural decision. Asks 4 short questions and creates a new ADR file." }`

After the user picks, dispatch into the matching mode below. If they pick `decision`, ask for the title next (per the `decision` mode rules) — the picker does not collect it.

## The six artifacts

Documentation lives in exactly these locations. Never create others without explicit user approval. Each file has a distinct purpose, audience, and edit cadence.

### 1. `README.md` — project root (human / vision layer)

Operator-facing. The "what is this and how do I run it" layer. Section order is fixed:

1. **One-line description** — what the project IS, in one sentence.
2. **Stack** — frameworks and key libraries with pinned versions (e.g., "Angular 13.3", not "Angular").
3. **Prerequisites** — required Node/Python/etc. versions, Docker, env vars, accounts.
4. **Quick start** — clone → install → run, in 3 commands max.
5. **Commands** — install / dev / build / test / lint / deploy. Only list commands that actually exist in `package.json` (or equivalent).
6. **Services & ports** — what runs where.
7. **Project structure** — top-level folders, 1 line each. No deeper than one level.
8. **Common tasks** — "how do I add a route", "how do I run a migration". Only tasks the user actually performs.
9. **Troubleshooting** — known gotchas only. No speculation.

**Hard cap: 150 lines.** If the README exceeds 150 lines, content must move to ARCHITECTURE.md or be cut. This cap is non-negotiable — it is the primary forcing function against bloat.

### 2. `docs/ARCHITECTURE.md` — technical reference (current state)

System-level docs. Describes how the system works *right now*, not the journey of decisions. Created **lazily** — only generate when the project has at least one of:
- More than one deployable service or runtime
- Non-trivial layering (controllers / services / repositories, or equivalent)
- External integrations worth explaining (third-party APIs, queues, external DBs)

If none of these apply, omit the file entirely. Do not create empty scaffolding.

Sections:
- **Components** — what pieces exist and what each owns.
- **Data flow** — how a request travels through the system. One numbered flow or one diagram, not both.
- **External dependencies** — APIs, queues, databases, third-party services.
- **Cross-references to ADRs** — when a part of the system traces back to a recorded decision, link to the ADR file (e.g., "see `docs/decisions/003-db-per-service.md`"). Do NOT restate the rationale — that lives in the ADR.

ARCHITECTURE.md is rewritten freely as the system evolves. It always describes the present.

### 3. `docs/PRINCIPLES.md` — hard rules

Non-negotiable design principles that govern every decision below them. Each principle gets a short heading and 2-4 sentences explaining what the rule is and why it can't be broken.

Created **lazily** — only generate when the user has explicit principles. Do not invent principles by paraphrasing the README. Empty scaffolding is worse than no file.

Edit cadence: rare. A principle change is itself an architectural decision and should be recorded as an ADR.

### 4. `docs/CONVENTIONS.md` — code-level standards

The "how do we write code here" layer. Distinct from PRINCIPLES (which govern design) — CONVENTIONS govern syntax, structure, and ergonomics. Topics:
- **Naming** — class, file, function patterns; layer-to-layer parity.
- **File / class internal order** — constants → fields → constructor → public → private.
- **Section dividers and comments** — what style, what to comment, what not to.
- **Error handling** — exceptions vs. result types, return shapes.
- **Commit messages** — convention (e.g., `feat:`, `fix:`), branch naming.

Created **lazily** — only generate when the user has explicit conventions to record. Often derived from a personal `~/.claude/CLAUDE.md` or project-level CLAUDE.md.

### 5. `docs/CONTEXT.md` — AI session brief (GENERATED ARTIFACT)

A digest of the other five artifacts in one document, designed for an AI agent (Claude Code or similar) to read once at session start and have full context.

**This file is generated by `/doc update`, not authored by hand.** The header MUST include this notice:

```markdown
> **Generated artifact.** Regenerated by `/doc update`. Edit the source files (`README.md`, `docs/ARCHITECTURE.md`, `docs/PRINCIPLES.md`, `docs/CONVENTIONS.md`, ADRs) — never edit `CONTEXT.md` directly.
```

Sections:
1. **Project at a glance** — README §1 condensed.
2. **Stack & deployment topology** — README §2-§6 condensed.
3. **Architecture summary** — ARCHITECTURE.md condensed to bullets.
4. **Principles** — PRINCIPLES.md verbatim (these are short).
5. **Conventions** — CONVENTIONS.md condensed to bullets.
6. **Decisions index** — one bullet per ADR: `[NNN] Title — one-line summary` linking to the file.
7. **Glossary** — only project-specific terms. No general programming jargon.

Created lazily — only when the project has at least 2 of the other 4 source docs filled.

### 6. `docs/decisions/00N-short-name.md` — decision history (append-only)

One ADR per file. Numbered sequentially. Each ADR uses this template:

```markdown
# ADR NNN — <Title>

**Date:** YYYY-MM-DD
**Status:** Accepted
**Deciders:** <names>

## Context
<what forced this decision — constraints, problem, prior state>

## Options considered
<each option with pros/cons; reject options inline>

## Decision
<one sentence: what we chose>

## Rationale
<why we chose it; tradeoff named explicitly>

## Consequences
<what changes downstream — code, ops, future ADRs>
```

If existing ADRs in the project use translated field names (e.g., `Fecha`, `Estado`, `Decisores`, `Contexto`, `Decisión`, `Motivo`, `Consecuencias`), match the existing convention. Read at least one existing ADR before generating a new one.

Rules:
- **One file per decision.** Do NOT use a single flat `DECISIONS.md`.
- **Append-only.** Never edit past ADRs except: (a) typos, (b) updating the `Status` field when an ADR is superseded.
- **Reversed decisions get a new ADR** that supersedes the old. The old one's `Status` is updated to `Superseded by NNN`. Never delete.
- **Numbering is gapless and sequential.** First ADR is `001`, then `002`, etc. Padded to 3 digits.
- **Filename:** `NNN-short-name.md` — slug in kebab-case, English or matching existing convention.
- A `000-template.md` file lives in the folder as the canonical template.

## Mode behavior

### `init`

1. **Check for existing docs first.** If any of the six artifacts exist with non-trivial content, stop and ask:
   > "`<file>` already exists. Run `/doc update` to refresh it, `/doc audit` to check for drift, or confirm you want to overwrite."
   Do not overwrite without explicit confirmation.
2. Read the repo: `package.json` (or equivalent), framework signals, folder structure, lockfile for versions, compose/k8s files for services, existing `.env.example` for required vars, any `CLAUDE.md` files for conventions.
3. **Decide scope:**
   - **Always generate:** `README.md` and `docs/decisions/` folder with `000-template.md`.
   - **Generate `ARCHITECTURE.md`** if the project shows architectural complexity (>1 service, layered code, external integrations).
   - **Generate `PRINCIPLES.md` and `CONVENTIONS.md`** only if the user has explicit material to draw from (a `CLAUDE.md`, prior docs, or explicit user input). Otherwise skip them and tell the user: "Run `/doc update` later when you have principles or conventions to record."
   - **Generate `CONTEXT.md`** only after at least 2 other docs are filled. On first init, usually skip.
4. Fill each section from observable repo state. Where information is not derivable from the repo, insert `<!-- TODO: ... -->` placeholders. **Never invent.**
5. Show the proposed file(s) as a diff. Wait for confirmation before writing.

### `update`

1. Read all existing docs.
2. Read current repo state (same signals as `init`).
3. Build a drift list:
   - Commands in README that no longer exist in `package.json`
   - Ports in README that don't match config
   - Stack versions that have bumped
   - New top-level folders not mentioned in "Project structure"
   - Services or files referenced in ARCHITECTURE that no longer exist
   - Conventions in CONVENTIONS.md that current code violates (e.g., file order, naming patterns)
4. Propose **targeted edits** to README, ARCHITECTURE, PRINCIPLES, and CONVENTIONS — not full rewrites. Show a diff per section that needs changing.
5. **Regenerate `CONTEXT.md` from scratch** as a digest of the other artifacts. This is the one file that gets a full rewrite each update — show the new file as a complete replacement, not a diff.
6. **Never touch files under `docs/decisions/`.** ADRs are append-only. The only ADR edit allowed is updating a `Status` field when one is superseded — and that happens via the `decision` mode, not `update`.
7. Wait for confirmation before writing.

### `audit`

**Read-only. This mode never writes to disk.**

Produce a punch list grouped by file:

```
README.md
  ❌ Broken: <specific contradiction with code>
  ⚠️ Stale: <doc area where the code has changed recently>
  ❓ Missing: <required section empty or marked TODO>

docs/ARCHITECTURE.md
  ...

docs/PRINCIPLES.md
  ...

docs/CONVENTIONS.md
  ...

docs/CONTEXT.md
  ⚠️ Out of sync: <which source doc has newer content not yet reflected here>

docs/decisions/
  ❓ Missing supersede link: ADR NNN reverses ADR MMM but MMM still says Status: Accepted
  ⚠️ Numbering gap: ADR 005 → 007 (006 missing)
```

End with a one-line summary: `Audit: <N broken>, <N stale>, <N missing>`.

If the user wants to act on the report, they invoke `/doc update` separately — audit and update are intentionally separate so reading the report is not coupled to writing changes.

### `decision "<title>"`

If no title was passed, ask for one first.

Then:

1. **Determine the next ADR number.** Read `docs/decisions/` and find the highest existing NNN. Next ADR is NNN+1. Pad to 3 digits.
2. **Read at least one existing ADR** to detect language convention (English vs. translated field names). If `docs/decisions/` is empty (or only contains `000-template.md`), default to English.
3. Ask the four questions, **one at a time**, waiting for each answer:
   - **Context** — what forced this decision? (constraint, deadline, problem)
   - **Options** — what alternatives did you consider? (list 2-4 briefly)
   - **Decision** — what did you choose, in one sentence?
   - **Rationale & tradeoff** — why this option, and what are you giving up?
4. Format using the template above (matching the project's language convention) with today's date in `YYYY-MM-DD` format. Status: `Accepted`. Deciders: ask if multiple, otherwise omit.
5. **If this ADR supersedes a prior one,** ask the user which ADR is being superseded. Plan a second edit: change the prior ADR's `Status` field to `Superseded by NNN`. Show this edit as part of the diff.
6. Filename: `NNN-<short-slug>.md` where `<short-slug>` is derived from the title (kebab-case, max 5 words).
7. Show the proposed file (and any superseding edit) as a diff. Wait for confirmation. Write on confirmation.
8. Show the new file path back to the user. Done. Do not over-summarize.

## Discipline rules — apply in every mode

- **Never invent.** If the repo doesn't tell you something, ask the user or insert a `<!-- TODO -->`. Plausible-sounding fabrication is the worst failure mode of doc generation.
- **No filler sections.** "Introduction," "Overview," "Background" — cut them. Every section answers a question someone actually asks.
- **Match the language of existing project docs.** If the project's existing docs are in Spanish (or any other language), generate new docs in the same language. Don't mix.
- **Never modify source files.** This skill does not generate inline comments, docstrings, or JSDoc. Code-level documentation is a coding-time discipline, not a doc-time one.
- **No speculative content.** No "Future work," "Roadmap," or "Possible extensions" sections.
- **Always show a diff before writing.** Modes `init`, `update`, and `decision` propose changes; the user confirms before any file is written.
- **Plain language.** "Runs on port 4200" beats "exposes a development server bound to TCP/4200."
- **Lazy generation.** Don't create empty scaffold files. A missing ARCHITECTURE.md is fine; an empty one is noise.

## Conventions

- **Date format:** `YYYY-MM-DD`.
- **Code blocks:** language-tagged (` ```bash`, ` ```ts`, ` ```json`).
- **Links:** prefer relative paths inside the repo.
- **Headings:** sentence case ("Quick start"), not Title Case ("Quick Start").
- **Lists:** hyphens, not asterisks.
- **ADR numbering:** zero-padded to 3 digits (`001`, `002`, ..., `099`, `100`).

## What this skill does NOT do

- Does not write tests for documentation.
- Does not generate code comments or docstrings.
- Does not enforce documentation in CI (that's a separate concern).
- Does not document third-party libraries — only this project.
- Does not invent decisions the user hasn't actually made.
- Does not edit ADRs in `update` or `audit` mode — they are append-only.
