# harness-skills — Authoring Notes

These skills run in several coding-agent harnesses, not only Claude Code: **Claude Code, GitHub
Copilot CLI, opencode, pi, Codex CLI, and Cursor** (`cursor-agent`). `hooks/agent-env.sh` also
recognizes Gemini CLI, Grok Build, and DeepSeek Harness. Write every skill for an agent that may
have none of Claude Code's machinery.

## No internal or personal information

Never commit company or product names, internal hostnames or URLs, ticket keys or project
prefixes, internal MCP server or tool names, internal repo names, or absolute local paths.
Examples use neutral placeholders (`PROJ-123`, `issues.example.com`, `/home/user`).

Site-specific setup goes in a **local overlay**, which is gitignored:

- `skills/<skill>/local.md` is the entry point. Every skill reads it first when it exists.
- `skills/<skill>/local/` holds extra files that `local.md` points to.
- `hooks/local.env` is sourced by hooks (e.g. `CLAUDE_STATUSLINE_CMD` for `usage-snapshot.sh`).
- `dev-guidelines` is a placeholder that works only through its overlay: `local.md` routes file
  types to guideline files under `local/`.

A marketplace plugin install replaces the skill folders on every update, so its overlays live
outside the plugin, in `~/.config/harness-skills/`: `<skill>/local.md`, `<skill>/local/`, and
`hooks/local.env`. The in-repo overlay wins when both exist. When you change how a skill reads
its overlay, keep both locations and that order.

## Missing dev-guidelines configuration

When `dev-guidelines` reports `dev-guidelines: not configured`, ask the user once per session,
through the ask tool, whether to generate a configuration. The options and the content of each
generated file are in `skills/dev-guidelines/SKILL.md` ("Offer to generate a configuration").

- Write generated files only to `~/.config/harness-skills/dev-guidelines/`.
- Never write `local.md` or `local/` inside a skill folder of this repo or of a plugin install.
  An in-repo overlay may be a symlink into another checkout, and a plugin update deletes the
  plugin folder.
- Never commit an overlay.

## Cross-harness rules

| Harness-specific feature | Elsewhere | What to do |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | Unset outside Claude Code | Use `agent_skill_root` from `hooks/agent-env.sh`, or paths relative to the skill directory |
| Frontmatter `hooks:` (Stop, PreToolUse) | Ignored by other harnesses | Never let correctness depend on a hook. The skill body must still tell the agent to finish the work |
| Session id env vars | Differ per harness | Call `agent_session_id` / `agent_harness` from `hooks/agent-env.sh`. Never read one env var directly |
| Subagent tools, `Workflow`, native task list | Absent or different | Detect by capability, not harness name, and state the fallback ("if no subagent tool exists, do X inline") |
| MCP servers | pi has none, opencode uses its own schema | Never make one MCP server the only path to a capability |
| Slash-command syntax | Differs per harness | Don't rely on a specific invocation syntax in a skill body |

- Keep the frontmatter `name:` equal to the directory name.
- Keep assets inside the skill folder and reference them relatively.
- Write harness-neutral prose: "the agent", imperative voice, never "Claude will…".

## Skill and agent conventions

- Every skill description starts with `(BN) `.
- Never set `model:` or `effort:` in frontmatter. Skills and agents inherit the session model.
- Keep `allowed-tools` (skills) and `tools:` (agents) complete. Agents also carry `memory: user`.
- Register every skill folder in `.claude-plugin/marketplace.json` in the same change.
- Keep the plugin name and description in `.cursor-plugin/marketplace.json` and
  `.cursor-plugin/plugin.json` equal to `.claude-plugin/marketplace.json`. Cursor finds the
  skills in `skills/` by convention, so it needs no skill list.
- `scripts/update-harness-skills.sh` holds each harness's update command. Change it when a
  harness changes its plugin CLI, and keep the README **Updates** table equal to it.
- Agents live in `agents/` and workflows in `workflows/` at the repo root, never inside a skill.
- Skills that keep per-session state use `session-slug` and its session-folder format.

## Tests

Run the test scripts next to the code you change: `hooks/*.test.sh`,
`skills/arch-design/scripts/*.test.sh`, and `node workflows/code-gen-implement.test.mjs`.
