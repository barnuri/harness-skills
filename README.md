# harness-skills

Skills and subagents for coding-agent harnesses. They are written to be harness-neutral and run in
**Claude Code, GitHub Copilot CLI, opencode, pi, Codex CLI, and Cursor** (`cursor-agent`).
`hooks/agent-env.sh` also recognizes Gemini CLI, Grok Build, and DeepSeek Harness. Harness-only
features (Stop hooks, subagents, the `Workflow` tool) are optional speed-ups: every skill states
its fallback when a harness lacks them.

## Skills

| Skill | What it does |
|---|---|
| `code-gen` | Implements a request with a persistent `plan.md` / `tasks.md`, a completion gate, and optional parallel execution |
| `cr` | Reviews a diff, branch, or PR with parallel agents and confidence-scored findings |
| `arch-design` | Writes a design doc from a template and renders it to self-contained HTML (with review annotations) and Word |
| `arch-verify` | Checks whether the implementation matches its design doc |
| `rca` | Writes a root cause analysis, optionally pulling from an issue tracker or log tool |
| `handoff` | Compacts the session into a resume document for a fresh session |
| `skills-evolvement` | Audits and improves the skills in a skills repo |
| `context-declutter` | Measures always-loaded context files and splits bloated sections into on-demand references |
| `agent-spec` | Lists, resumes, and cleans `agent-spec/` session folders, and prunes stale session pointers |
| `dev-guidelines` | Placeholder that loads your own coding standards from its local configuration. Does nothing until configured |
| `session-slug` | Shared session identity and session-folder format used by the skills above |

Subagents in `agents/`: `planner`, `implementer`, `bug-hunter`, `guideline-checker`, `test-runner`,
`root-cause-debugger`, `perf-profiler`.

## Install

Every harness below installs straight from this GitHub repo. Pick yours, run its commands once, then
turn on updates as its row in [Updates](#updates) shows.

### Claude Code

```bash
claude plugin marketplace add barnuri/harness-skills
claude plugin install barnuri-dev-skills@harness-skills
```

Inside a session, `/plugin marketplace add barnuri/harness-skills` and
`/plugin install barnuri-dev-skills@harness-skills` do the same.

### GitHub Copilot CLI

```bash
copilot plugin marketplace add barnuri/harness-skills
copilot plugin install barnuri-dev-skills@harness-skills
```

Install through the marketplace. `copilot plugin install barnuri/harness-skills` fails because the
repo has no root `plugin.json`.

### Codex CLI

```bash
codex plugin marketplace add barnuri/harness-skills
codex plugin add barnuri-dev-skills@harness-skills
```

### Cursor

```bash
cursor-agent plugin marketplace add https://github.com/barnuri/harness-skills
```

Then open **Customize** in the Cursor sidebar, find `barnuri-dev-skills`, and select **Install**.
The repo's `.cursor-plugin/` manifests follow Cursor's plugin docs. This flow is not yet tested end to end.
Adding a marketplace needs a signed-in Cursor account (`cursor-agent login`). If you already have
the Claude Code plugin, you can skip this: turn on Cursor Settings → Agents → Third-Party Imports
("Include Third-Party Plugins, Skills, and Other Configs") and Cursor loads it.

### pi

```bash
pi install git:github.com/barnuri/harness-skills
```

pi finds the skills in `skills/` by convention. Pass `-l` to install for one project only.

### opencode

opencode plugins are npm modules, so it reads these skills from a clone instead:

```bash
git clone https://github.com/barnuri/harness-skills ~/.local/share/harness-skills
```

Then add the clone to `~/.config/opencode/opencode.json`:

```json
{
  "skills": { "paths": ["~/.local/share/harness-skills/skills"] }
}
```

## Updates

The plugin sets no `version`, so each commit on `master` is a new release.

| Harness | Native auto-update | Manual update |
|---|---|---|
| Claude Code | Yes, after you turn it on (see below) | `claude plugin marketplace update harness-skills`, then `claude plugin update barnuri-dev-skills@harness-skills` |
| GitHub Copilot CLI | No | `copilot plugin update barnuri-dev-skills@harness-skills` (or `--all`) |
| Codex CLI | No | `codex plugin marketplace upgrade harness-skills`, then `codex plugin add barnuri-dev-skills@harness-skills` |
| Cursor | No CLI setting | `cursor-agent plugin marketplace update harness-skills` |
| pi | No | `pi update git:github.com/barnuri/harness-skills` (or `pi update --extensions`) |
| opencode | No | `git -C ~/.local/share/harness-skills pull` |

**Claude Code.** Third-party marketplaces do not auto-update by default. Turn it on in `/plugin` →
Marketplaces → `harness-skills` → Enable auto-update, or declare the marketplace in
`~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "harness-skills": {
      "source": { "source": "github", "repo": "barnuri/harness-skills" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": { "barnuri-dev-skills@harness-skills": true }
}
```

**Every other harness.** `scripts/update-harness-skills.sh` runs the manual update for each
harness it finds on the machine and skips the rest. Schedule it once to get auto-update
everywhere. For example, with cron, daily at 09:00:

```bash
(crontab -l 2>/dev/null; echo '0 9 * * * bash ~/.local/share/harness-skills/scripts/update-harness-skills.sh >/dev/null 2>&1') | crontab -
```

The path assumes the opencode clone. Point it at any clone of this repo.

An update replaces the plugin folder. Keep your own files in `~/.config/harness-skills/`, which no
update touches (see [Local overlays](#local-overlays)).

## Set up dev-guidelines

`code-gen` and `cr` check code against your coding standards. `dev-guidelines` ships no rules. It
loads the rules you give it. Until you configure it, the guideline check is skipped and everything
else still runs.

### Option 1: let the skill generate it

Run `code-gen`, `cr`, or `dev-guidelines` in any repo. When `dev-guidelines` finds no
configuration, it asks once per session:

| Answer | Result |
|---|---|
| Generate from this repo | Drafts rules from the repo's lint and formatter configs, `CLAUDE.md`/`AGENTS.md`, and its source files |
| Write a starter set | Writes a short generic rule set, with one file per language found in the repo |
| Not now | Asks again next session |
| Never ask | Writes `local.md` with `disabled: true` and stops asking |

It shows you the drafted files before it writes them to `~/.config/harness-skills/dev-guidelines/`.

### Option 2: write it yourself

1. Create the folder:

   ```bash
   mkdir -p ~/.config/harness-skills/dev-guidelines/local
   ```

2. Write `~/.config/harness-skills/dev-guidelines/local.md`. It routes file types to rule files.
   Paths are relative to the folder that holds `local.md`:

   ```markdown
   # Coding standards

   - Always load: `local/coding-principles.md`
   - `.py` files: also load `local/python-guidelines.md`
   - `.ts` / `.tsx` files: also load `local/typescript-guidelines.md`
   ```

3. Write each rule file under `local/`. Keep each rule to one sentence a reviewer can mark as
   followed or not:

   | File | What to put in it |
   |---|---|
   | `coding-principles.md` | Rules for every language: naming, function size, error handling, comments, test expectations, and changing only what the task needs |
   | `<language>-guidelines.md` | One per language: formatter and linter with their configs, typing rules, module layout, test framework and test layout |

4. Check it: run the `dev-guidelines` skill. It prints `dev-guidelines: loaded`.

`local/` can be a symlink to a folder in another repo, so a team can share one rule set.

### Other places the standards can come from

`code-gen` and `cr` use the first source that exists:

1. The `dev-guidelines` skill, once configured.
2. Guideline files named in the calling skill's own `local.md` (see below).
3. The target repo's `CLAUDE.md` / `AGENTS.md`.

## Local overlays

Each skill reads an optional `local.md` first, plus any files in the `local/` folder beside it.
Put site-specific setup there: your issue tracker's browse URL, internal MCP tool names, a
reporting timezone, guideline file paths. Hooks read `local.env` the same way (e.g.
`CLAUDE_STATUSLINE_CMD` for `hooks/usage-snapshot.sh`).

| Install | Skill overlay | Hook overlay |
|---|---|---|
| Plugin or package (survives updates) | `~/.config/harness-skills/<skill>/local.md` | `~/.config/harness-skills/hooks/local.env` |
| Clone you edit | `skills/<skill>/local.md` | `hooks/local.env` |

When both exist, the clone location wins. In-repo overlays are gitignored.

## Without a plugin manager

Symlink each `skills/<skill>` folder of a clone into the harness's skills folder.
`~/.agents/skills/` covers opencode, pi, and GitHub Copilot CLI.
[claude-harness-sync](https://github.com/barnuri/claude-harness-sync) automates these symlinks for
an installed Claude Code plugin.
