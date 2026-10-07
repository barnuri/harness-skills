---
name: arch-design
description: >
  (BN) Write an architecture or feature design document using the shared design template, and
  render it to a self-contained HTML artifact and an optional Word export. Use when asked for a
  design doc, technical spec, architecture proposal, or feature design. Triggers: "design this",
  "write a design for X", "create a spec", "document this approach", "plan how to build X".
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# Architecture Design Skill

You help engineers produce design documents that survive a real review: accurate, specific, and
honest about trade-offs. The structure is the **shared design template** — do not invent your own
section list, and do not add or rename sections. Optional sections may be deleted when they do not
apply, and Design Alternatives may be moved to the end once its decisions are settled — the shared
template sanctions that one relocation.

There are three outputs, from one source:

| File | Who it is for | How it is produced |
|---|---|---|
| `design.md` | agents and engineers; the **source of truth** | authored by you |
| `design.html` | product and R&D reviewers | `scripts/render_design_html.py` |
| `design.docx` | the design review meeting; the comment channel for non-engineers | `scripts/render_design_docx.py` (on request) |

Recipients install nothing. `design.html` is a single self-contained file — inline CSS, system
fonts, no CDN, no server, no network at open time. It can be emailed, opened by double-click, and
printed to PDF. `design.docx` opens in Word with track changes and comments.

## The design/plan contract

This is the rule that matters most, because it is the one that is easy to violate by accident.

**`design.md` answers what and why. It must never contain a plan.** No task IDs, no checkboxes, no
phases, no ordering, no `[P]` parallel flags, no per-file edit instructions, no per-item status.

`code-gen` re-derives `plan.md` and `tasks.md` by reading `design.md`, so the design must be dense
enough to plan from: numbered atomic requirements `R1…Rn` (the join key downstream tasks cite),
real repo paths in backticks, real field names, decisions marked as decided, dependencies named,
open `Q:` lines left visible, and a rough effort estimate per component.

The **Implementation Plan** section sits directly on this boundary: name the components,
their dependencies, and the effort — never sequence them.

Full rationale and the per-section notes: [section-guidance.md](references/section-guidance.md).

## Step 1 — Gather context

Ask only what is genuinely ambiguous. At minimum you need: what is being designed, why it is
needed, which area it belongs to, and any prior decisions or constraints. If the request already
answers these, go straight to writing.

## Open Questions — Ask, Don't Guess

Whenever a `Q:` line would go into the document, **ask the user with `AskUserQuestion` before
writing it** — that is the default, not the fallback. A `Q:` line is for a question only someone
outside this session can answer (another team, product, an unavailable owner); anything the user
sitting here can decide should be decided now and written as a decision row, not deferred.

Phrase each question with 2–4 concrete options and a one-line consequence per option; the harness
appends "Other" for free text. Batch questions that surface together into one call (up to 4). Use
plain prose only when the answer cannot be shaped as options. Never guess and never leave a
bracket placeholder.

On reply: delete the `Q:` line, add one row to the decisions table under Proposed Approach, and
note the reasoning in Document history.

**Autonomous run — the only exception.** If the user explicitly asked for an unattended run
("autonomous", "don't ask anything", "no questions", "unattended"), skip `AskUserQuestion`
entirely. For each question that would have blocked, pick the option you would have recommended,
write it as a decision row marked `⚙️ Assumed (autonomous)` with a one-line rationale, and list
every such assumption in the final summary. Autonomous mode is opt-in per request and does not
persist to the next one; it never authorizes editing text already `Approved` — that still stops
and asks.

## Step 2 — Resolve the location

Drafts live in `agent-spec/<slug>/design.md`. Invoke the `session-slug` skill to resolve the slug —
never derive it yourself.

When `status:` flips to `Approved`, **promote** the document: copy it to
`docs/architecture/<area>/<kebab-case-name>.md`, using the `area` field from the front matter as
the subdirectory. Scan `docs/architecture/` first and reuse an existing subdirectory when one fits;
create a new kebab-case one only if none does. Be specific with the filename —
`policy-search-lazy-loading.md`, not `design.md`.

## Step 3 — Write the document

Read [template.md](references/template.md) and follow it section for section. Fill every section
with **real content**. If a value is unknown, write it as an explicit `Q:` line or
"TBD — needs input from <team>" rather than leaving a bracket placeholder; `code-gen` treats a `Q:`
line as a blocking question and will ask rather than guess.

Remove a section only when it genuinely does not apply, and say why in one line.

**No implementation code.** Schemas, id formats, and interface shapes belong in the document;
function bodies do not. A design doc is a blueprint, not a PR.

**Stop at the requirements until product signs off, then freeze them.** A design has two phases and
the boundary is the approval of `Detailed Requirements (Customer-Facing)`.

- **Before sign-off, write nothing after that section.** Background, requirements, limitations, out
  of scope — then stop, with a short note saying the rest is deliberately unwritten. A reviewer
  asked to approve requirements should not be reading an implementation plan; every extra section
  is surface for a debate that has to happen again once the requirements move.
- **Park settled decisions beside the document — never the open questions.** Decisions accumulate
  while the requirements are in review; keep them in a sibling file (`decisions-and-open-questions.md`)
  and fold them in after approval. An open `Q:` that blocks a requirement is the opposite: the
  approver is the person who answers it, so it stays in the review copy, inside the section it
  blocks. Moving it out hides the reason the document cannot be approved yet.
  - **Test:** who answers this? Product or a stakeholder → it stays in the document. The
    engineering team, on its own → it is a downstream design question and can wait in the sibling
    file.
  - Write those questions for the approver, not for the team: plain words, a concrete example with
    real dates or numbers, and the options spelled out. No `D<n>` references — the approver has not
    read the decisions file and should not have to.
- **After sign-off the requirements section is frozen.** Append new `R<n>` items; never edit,
  renumber or delete an approved one. Downstream tasks and tests cite those numbers.
- **A real change to an approved requirement goes back for re-approval**, with its own Document
  history row. Silently rewording an approved `R<n>` is the worst failure mode this skill has —
  the reviewer approved text that no longer exists.

**When work would change an approved section, stop and raise it. Do not edit it.** This is the one
rule in this skill that overrides "just do the task". Approval is a commitment made to people
outside the session, and an agent that quietly edits approved text breaks it without anyone
noticing.

A section counts as approved when the Approvals table has a date against it, or `status:` reads
`Approved`. When a later request, a design decision, or an implementation detail would contradict
something already approved:

1. **Do not make the edit**, even when the new text is clearly better.
2. **Say exactly what would have to change** — which `R<n>` or which section, the current wording,
   the wording the work implies, and what forced it.
3. **Ask whether to re-open it.** Re-approval is the user's call to make with product, never the
   agent's to assume.
4. **Do every part of the task that does not touch approved text**, and report what you left
   undone and why. A blocked requirement does not block the rest of the work.

Write the new requirement as an appended `R<n>` marked "pending approval" when that lets the work
continue. Never renumber, never reword in place, never delete.

**Compress a decision the moment it is made, and keep it out of the requirements.** While a
question is open it earns prose — the options, the trade-off, what breaks either way. Once it is
answered, that prose has done its job: cut it to **one line in a decisions table** and move the
reasoning to a Document history row. Decisions accrete faster than anything else in a design, and
a requirements section that collects them stops being readable — a reviewer looking for "what must
this do" should never have to read a paragraph about a rejected alternative to find it.

- **Requirements sections hold requirements.** `R<n>` lines, limitations, worked examples. No `D<n>`
  prose, no superseded decisions, no debate.
- **Decisions live under Proposed Approach**, as a table: `| # | Decision | Why |`, one line each,
  ordered by number. The Why column is a short phrase, not a paragraph.
- **The reasoning goes to Document history**, which renders collapsed and is the document's change
  log. Nothing is lost; it is one click away instead of in the reading path.
- **A superseded decision keeps its number and gets one struck-through line** (`~~D7: …~~
  Superseded by D12`). Never delete it and never renumber — later text cites these.
- **Never renumber a `D<n>`**, for the same reason as `R<n>`: prose, review comments and the
  history table all cite them.

Mark a chosen Design Alternative with the GitHub-compatible badge markup documented in
[section-guidance.md](references/section-guidance.md) — never bare `style="color:…"` (GitHub strips
it) or `<u>` (not on GitHub's allowed-tag list). Keep the rejected alternatives; the record of what
was rejected and why is the most valuable part of the document.

Process rules — who owns the review, the 2-day pre-read, when to reschedule:
[review-process.md](references/review-process.md). That file is guidance for the author; never
paste it into a design document.

## Step 4 — Render

**Two different roots are in play** — the scripts live under this skill, the document lives in the
project workspace. Always write the script path in full and leave the document path relative to
the workspace; a bare `scripts/…` resolves from neither directory:

```bash
# <skill-dir> = the folder containing this SKILL.md
python3 "<skill-dir>/scripts/render_design_html.py" "agent-spec/<slug>/design.md"
python3 "<skill-dir>/scripts/render_design_docx.py" "agent-spec/<slug>/design.md"   # on request
```

The scripts resolve their own assets from `__file__`, so they work under any harness. Do not
reference a plugin-root environment variable; it is unset outside Claude Code.

The HTML renderer is stdlib-only and needs no installation. The docx renderer bootstraps
`python-docx` into a venv beside the skill on first run; that is author-side only and never reaches
a recipient.

### Every output is standalone

All three files are sent to people as-is, so none may depend on anything else:

- `design.md` — no links to skill files (`section-guidance.md`, `review-process.md`, …). Those are
  author guidance; a recipient opening the markdown would hit a dead path.
- `design.html` — one file: CSS inlined, system fonts, no CDN, no server, no network at open time.
- `design.docx` — opens in Word with no add-in.

### What the renderer does to the document

Three things happen automatically. Do not hand-write any of them into the markdown.

- **Document history collapses.** It renders as a closed `<details>` with the `<h2>` as its
  summary, so a reviewer opening the file lands on the content instead of scrolling past a change
  log. The heading keeps its anchor and its table-of-contents entry, and print/PDF expands it.
- **`jira:` and `epic:` front matter become links** when a browse URL is configured, via the
  `jira_base_url:` front-matter field or the `DESIGN_JIRA_BASE_URL` env var (check `local.md`
  for this install's value). Write the bare key (`PROJ-123`); with
  `jira_base_url: https://issues.example.com/browse/` the renderer links it to
  `https://issues.example.com/browse/PROJ-123` and still displays only the key. With no URL
  configured the key renders as plain text. Paste a full browse URL and it is reduced to the key
  for display. A value that is neither stays plain text, so `TBD` is safe.
- **`Q:` lines become open-question callouts** and are indexed into the review panel. `Q3:` keeps
  your number; bare `Q:` auto-numbers. See [section-guidance.md](references/section-guidance.md).

### Review annotations live inside the HTML

`design.html` ships a self-contained review layer. A reviewer selects any text and **right-clicks**
it to get **Comment** and **Copy**; the comment is stored **inside the file**. They press **Save
file** and email the result back; a second reviewer opens that file, sees the existing comments, and
adds their own. Nothing to install, no server, no account.

- **Right-click, not auto-open.** Selecting text does nothing on its own — reviewers select to
  re-read and to quote at least as often as to annotate, so the composer waits to be asked. With no
  selection under the cursor, the browser's own menu is left alone. `Cmd/Ctrl+Alt+M` opens the
  composer from the keyboard, which right-click cannot do. In reading mode the menu offers Copy only.

- **Autosave writes back to the same file.** In Chromium the first comment opens one save dialog;
  accepting it overwrites the file in place, and every later comment writes silently. The handle is
  keyed by URL and kept in IndexedDB, so reopening that file resumes autosave — on the reviewer's
  next click if the browser asks for permission again. Other browsers keep the comments in the
  browser and the footer says the file still needs an explicit save.
- **Identity** — the browser cannot read a computer account, so each reviewer enters their full
  name once. It is kept under one global key, and every local HTML file shares one `file://` origin
  in Chrome, Edge and Firefox, so the name carries to every design document they open. Safari
  blocks that storage unless local-file restrictions are disabled; there it lasts one window and
  the dialog says so.
- **Reading mode** hides every comment and highlight, like Word's *No Markup*. **Dark mode** is
  there too. Both preferences persist across files.
- **The panel carries both.** The launcher is labelled **Review** and its badge counts open
  questions *and* open comments, so a `0` means nothing is outstanding. Inside, the document's
  unresolved `Q:` lines come first under **Open questions**, reviewer comments below under
  **Comments**. If a question is missing from the panel, its line is not being detected — `Q:` or
  `Q<n>:` must start the paragraph.
- **Copy for agent** puts a complete, standalone prompt on the clipboard: which document, which
  markdown file is the source of truth, how to re-render, and every open comment with its section
  anchor and quoted text. Paste it into a session and the agent needs nothing else.
- Comments that have been handed over are marked `sent`, so the next round only carries what is new.

**The markdown is always the source of truth.** Apply review comments to `design.md`, never to the
HTML by hand, then re-render carrying the comments across:

```bash
python3 "<skill-dir>/scripts/render_design_html.py" "agent-spec/<slug>/design.md" \
  --comments "agent-spec/<slug>/design.html"
```

To read a returned file without loading 80 KB of HTML into context:

```bash
python3 "<skill-dir>/scripts/read_design_comments.py" <returned.html> --status open
```

`--no-annotate` renders a clean copy with no review layer, for printing or archiving.

### Diagrams and open questions are HTML-only

Write diagrams as ```mermaid fenced blocks. **Every arrow carries its initiator** — label each edge
`<initiator> → <target>` with the trigger, state the overall call direction in one sentence above the
diagram, and add an edge table beneath it so the direction survives the Word export. Full rules:
[section-guidance.md](references/section-guidance.md#architecture--flows).

**Diagrams are parsed before the file is written.** The renderer runs every mermaid block through
the same vendored bundle the browser uses and fails with the parse error rather than shipping a
document with a red "Syntax error in text" bomb in it — an invalid diagram is otherwise invisible
until a human opens the HTML. It bootstraps `jsdom` into `.mermaid-check/` beside the skill on first
run, and skips silently when `node` is unavailable. Two edge syntaxes that look right and are not:
`A -- yes --> |"label"| B` (a text label and a pipe label on one edge — write
`A -->|"yes · label"| B`), and a `classDef` with a `fill:` but no `color:` — mermaid supplies the
text colour from the active theme, so a light fill without an explicit dark `color:` is white-on-pale
the moment the reader flips to dark mode. Always write both.

**Diagrams re-render on the dark-mode toggle.** Mermaid has no runtime theme switch — a diagram keeps
whatever colours it was drawn with, so one rendered under the light theme keeps `#333` edges and pale
label chips on a near-black page and the arrows all but vanish. The renderer stores each block's
source, and re-runs mermaid with `theme: 'dark'` on every change of `body.theme-dark`, watched with a
`MutationObserver`. That is deliberately independent of `annotate.js`, so it also works under
`--no-annotate`. Check a document in **both** modes before sending it.

The vendored bundle is inlined **only** when the
document actually contains one. Sizes: about 18 KB with `--no-annotate`, about 80 KB with the
review layer, about 3.6 MB once a diagram is present. Never reference a CDN or `mermaid.ink` —
that breaks offline opening and sends internal design content to a third party.

**Word cannot render mermaid, and has no styling for `Q:` callouts.** The docx export writes the
diagram source as plain text. When a review needs the diagrams, send the HTML alongside the Word
file, or print the HTML to PDF. Say which file carries what when you hand them over.

After changing either script, run its test:

```bash
bash scripts/render_design_html.test.sh
bash scripts/render_design_docx.test.sh
```

## Step 5 — Confirm

Tell the user the full path of every file written, and offer to iterate on any section. If the
document still has open `Q:` lines, say so explicitly — those are what block the design being
approved.

If anything in this round touched, or wanted to touch, an already-approved section, lead with that.
It matters more than the file list: it is the one outcome the user cannot discover by reading the
rendered document, because approved text that changed still looks approved.

## Writing style

A design document is read by people under time pressure, most of them not the author. Length is not
thoroughness — a reviewer who skims a long document approves it without reading it, which is worse
than no review. Write so each section can be understood on its own, then cut.

**Write for a reader whose English is their second language**

Most reviewers on these documents are not native English speakers. A sentence someone has to read
twice is a sentence that does not get reviewed. Borrow the `eli5` skill's rule — assume the reader
knows nothing about this topic and use few words — and apply it to the prose, not the content.

- **One idea per sentence.** If two clauses are joined by "which", "whereby" or "thereby", split
  them into two sentences.
- **Take the common word every time.** use not utilise · start not commence · about not regarding ·
  needs not necessitates · before not prior to · so not thus · enough not sufficient · let not
  facilitate · and not in addition to.
- **No idioms, metaphors, or phrasal verbs that hide the meaning.** "falls over" → "crashes" ·
  "down the line" → "later" · "spin up" → "start" · "reach out to" → "call". A non-native reader
  translates these literally and gets the wrong picture.
- **Expand every acronym on first use**, including the ones everyone supposedly knows. `MDS`,
  `CMA`, `SNS`, `TTL` each cost one parenthesis and save a reader a search.
- **One name per concept, used every time.** Switching between "environment", "env", "tenant" and
  "customer" for the same thing reads as four different things to someone parsing word by word.

This is about vocabulary, not rigour. Technical precision stays: `env id`, idempotent, cursor,
at-least-once are the right words and no simpler word means the same thing. What goes is decorative
vocabulary — the word chosen because it sounds more senior than the plain one.

**Say it once, plainly**

- Lead every section with its conclusion. The reader may stop after one sentence; make that
  sentence the one that matters.
- State each fact exactly once, in the section that owns it. Repeating a decision in Background,
  Approach and Life cycle triples the maintenance cost and is how documents start contradicting
  themselves.
- One paragraph instead of two, one sentence instead of two, whenever nothing is lost.
- Plain, specific words. Use the simplest term that compresses the idea, never an overloaded one.
- Give real units — "3 endpoints", "2 days", "10 min" — never "some work", "a bit", "several".
- Cap any list at 5 items, ranked by importance. More than 5 means the section needs splitting or
  the items are not all worth stating.
- Match depth to the size of the change. A one-service integration does not need the same document
  as a platform redesign.

**Keep certainty exact, and name the actor**

- Mark every capacity, latency, or guarantee claim as measured or estimated. "Handles 10k req/s
  (load test, 2026-09)" or "expected to handle 10k req/s". Never state an estimate as a fact.
- Do not upgrade a hedge from a source. If a benchmark, ticket, or reviewer said "may", the
  document says "may".
- Use active voice and name the system that acts. "`auth-svc` refreshes the token" tells the reader
  who owns the step. "The token is refreshed" hides it, and that hidden owner is often the bug.

**Do not**

- Do not open a section with preamble or close it with a recap of itself.
- Do not use analogies. Describe the actual system.
- Do not use decorative headings, emoji, or motivational phrasing.
- Do not chain em dashes, and avoid semicolons and sentence fragments.
- Do not write filler: "it's important to note that", "worth stating plainly", "the real tension",
  "load-bearing", "here's the honest truth".
- Do not pad a weak section to look complete. Delete it, or write the one `Q:` line that says what
  is missing.

**Structure**

- H2 for the template's top-level sections, H3 for subsections. Do not rename them, and do not
  reorder them except for the sanctioned Design Alternatives move.
- Bullet lists for requirements and steps; tables for alternatives, approvals, effort, and metrics.
  A table beats three paragraphs whenever the content has repeating fields.
- `code` formatting for system names, config keys, endpoints, file paths, and identifiers.
- Reference codes make the document citable: `R<n>` requirements, `Q:` open questions, `D<n>`
  decisions. Use them once a section has three or more items. Never renumber an `R<n>` after
  review — append instead, because downstream tasks and tests cite them.

If `<skill-dir>/local.md` exists, read it first (and any file it points to under
`<skill-dir>/local/`). It holds this install's site-specific setup, and its rules override the
defaults below.

**Before rendering, reread twice — once to cut, once for vocabulary.** Every paragraph that does not
change a reader's decision comes out, and every word a second-language reader would stop on gets
swapped for the plain one. If a section survived only because the template lists it, delete it and say in one line why it
does not apply.
