#!/usr/bin/env bash
# Updates harness-skills in every harness on this machine that has it installed.
# Harnesses without a native plugin auto-update (Copilot CLI, Codex CLI, Cursor, pi, opencode)
# get their updates from this script. Safe to run from cron or launchd: every step is
# best-effort, and a harness that is not installed is skipped.
#
# Run: bash scripts/update-harness-skills.sh
# Env: HARNESS_SKILLS_CLONE  clone used by opencode (default ~/.local/share/harness-skills)

set -u

have() { command -v "$1" >/dev/null 2>&1; }
step() { printf '== %s\n' "$1"; }

if have claude; then
  step "Claude Code"
  claude plugin marketplace update harness-skills && claude plugin update barnuri-dev-skills@harness-skills
fi

if have copilot; then
  step "GitHub Copilot CLI"
  copilot plugin update barnuri-dev-skills@harness-skills
fi

if have codex; then
  step "Codex CLI"
  codex plugin marketplace upgrade harness-skills && codex plugin add barnuri-dev-skills@harness-skills
fi

if have cursor-agent; then
  step "Cursor"
  cursor-agent plugin marketplace update harness-skills
fi

if have pi; then
  step "pi"
  pi update git:github.com/barnuri/harness-skills
fi

clone="${HARNESS_SKILLS_CLONE:-$HOME/.local/share/harness-skills}"
if [ -d "$clone/.git" ]; then
  step "opencode (clone at $clone)"
  git -C "$clone" pull --ff-only --quiet
fi

exit 0
