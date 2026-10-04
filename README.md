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

Clone the repo, then point each harness at it:

| Harness | How |
|---|---|
| Claude Code | `/plugin marketplace add barnuri/harness-skills`, then `/plugin install barnuri-dev-skills@harness-skills` |
| opencode, pi, GitHub Copilot CLI | Symlink each `skills/<skill>` folder into `~/.agents/skills/` (all three read it) |
| Codex CLI, Cursor | Symlink the `skills/<skill>` folders into that harness's skills directory |

[claude-harness-sync](https://github.com/barnuri/claude-harness-sync) automates the symlinks for
an installed Claude Code plugin.

## Coding standards

`code-gen` and `cr` check code against coding standards resolved in this order:

1. The `dev-guidelines` skill, once configured: add `skills/dev-guidelines/local.md` and your guideline files under `skills/dev-guidelines/local/`.
2. Guideline files named in the skill's `local.md` (see below).
3. The target repo's `CLAUDE.md` / `AGENTS.md`.

With none of these, the guideline check is skipped and everything else still runs.

## Local overlays

Each skill reads an optional `skills/<skill>/local.md` first, plus any files under
`skills/<skill>/local/`. Put site-specific setup there: your issue tracker's browse URL, internal
MCP tool names, a reporting timezone, guideline file paths. Hooks read `hooks/local.env` the same
way (e.g. `CLAUDE_STATUSLINE_CMD` for `hooks/usage-snapshot.sh`). All overlays are gitignored.
