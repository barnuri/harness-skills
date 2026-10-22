# Official Code-Review Sources

Each row records the last version that skills-evolvement read. Agent C compares against it.
Phase 5 updates it. The version is the file's latest commit SHA for a repo source, the program
version for a bundled source, and the fetch date for a doc.

Learn ideas from these sources. Never copy their prompt text into a skill: restate the idea.

## Claude Code (Anthropic)

| Source | Where | Last version read | Read on |
|---|---|---|---|
| Built-in `/code-review` skill | Bundled in the Claude Code program (not published) | Claude Code 2.1.308 | 2026-10-22 |
| `/code-review` docs | https://code.claude.com/docs/en/code-review-local | fetched 2026-10-22 | 2026-10-22 |
| Code Review service docs | https://code.claude.com/docs/en/code-review (+ `-customize`, `-pull-requests`) | fetched 2026-10-22 | 2026-10-22 |
| `code-review` plugin | https://github.com/anthropics/claude-code/blob/main/plugins/code-review/commands/code-review.md | `db8834ba1d72e9a26fba30ac85f3bc4316bb0689` | 2026-10-22 |
| `pr-review-toolkit` plugin | https://github.com/anthropics/claude-code/tree/main/plugins/pr-review-toolkit | `f7ab5c799caf2ec8c7cd1b99d2bc2f158459ef5e` | 2026-10-22 |
| `claude-code-action` review command + agents | https://github.com/anthropics/claude-code-action/tree/main/.claude | `11a01b7183ef5cf1c7fbb75eaf39379c6b11bdc8` | 2026-10-22 |
| `claude-code-action` review workflow example | https://github.com/anthropics/claude-code-action/blob/main/examples/pr-review-comprehensive.yml | `ba45bb9506c90614f565e1e1c183ea099426a2a3` | 2026-10-22 |

## Codex CLI (OpenAI)

| Source | Where | Last version read | Read on |
|---|---|---|---|
| Review rubric (review sub-agent prompt) | https://github.com/openai/codex/blob/main/codex-rs/prompts/templates/review/rubric.md | `81de4f251cfdaf32ecb85e2160ebfc11a562d44b` (release `rust-v0.163.0`) | 2026-10-22 |
| Review target selection | https://github.com/openai/codex/blob/main/codex-rs/prompts/src/review_request.rs | `ba2b67f9cda954bcdda43c2a65ac58e807b996bd` | 2026-10-22 |
| Review output schema | https://github.com/openai/codex/blob/main/codex-rs/protocol/src/protocol.rs (`ReviewOutputEvent`) | `07316174c6f62deb20278c53add2dbd9dcf6da70` | 2026-10-22 |
| Bundled `review-agent` sample skill | https://github.com/openai/codex/blob/main/codex-rs/skills/src/assets/samples/review-agent/SKILL.md | `83a418783707f4446aa832b2799d6cacfef75011` | 2026-10-22 |
| Codex repo PR-review label prompts | https://github.com/openai/codex/tree/main/.github/codex/labels | `baa92f37e0fe1cb80e5290d1e02ca9b6d3edd909` | 2026-10-22 |
| GitHub code review docs | https://learn.chatgpt.com/docs/third-party/github | fetched 2026-10-22 | 2026-10-22 |
| `openai/skills` | https://github.com/openai/skills | `49f948faa9258a0c61caceaf225e179651397431` (no review skill) | 2026-10-22 |

## GitHub Copilot

| Source | Where | Last version read | Read on |
|---|---|---|---|
| Copilot CLI `/review` agent | Bundled in Copilot CLI (`definitions/code-review.agent.yaml`) | CLI 1.0.102-1 | 2026-10-22 |
| Copilot CLI `/security-review` and `rubber-duck` agents | Bundled in Copilot CLI (`definitions/`) | CLI 1.0.102-1 | 2026-10-22 |
| Copilot CLI changelog | https://github.com/github/copilot-cli/blob/main/changelog.md | `17631dc79466e1cf4a3e3f19e9ea907a56217d2c` | 2026-10-22 |
| Copilot code review docs | https://github.com/github/docs/tree/main/content/copilot (code-review concept, how-to, customize, excluded files) | `b4ab111f` | 2026-10-22 |
| awesome-copilot `code-review` skill | https://github.com/github/awesome-copilot/blob/main/.github/skills/code-review/SKILL.md | `65913229e04dd2d03a7a5e6c70ef605e03919bad` | 2026-10-22 |
| awesome-copilot review instructions and agents | https://github.com/github/awesome-copilot (`instructions/code-review-generic.instructions.md`, `agents/gem-reviewer.agent.md`, `skills/security-review/`) | `83fe668a7c8a5eeed990af7b8e19bda8d73c120d` | 2026-10-22 |
| gh-aw review skills and workflows | https://github.com/github/gh-aw (`.github/skills/copilot-review/`, `.github/workflows/pr-code-quality-reviewer.md`) | `93f2d333371be1a18e4826b3f487684e6425a54e` | 2026-10-22 |
