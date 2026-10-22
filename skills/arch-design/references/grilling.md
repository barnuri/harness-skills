# Grilling: how to ask open questions

Read this before the first `AskUserQuestion` call of an `arch-design` run. `SKILL.md` says *when*
to ask (every `Q:` line the user can decide). This file says *how*.

## Shape of a question

Phrase each question with 2–4 concrete options and a one-line consequence per option; the harness
appends "Other" for free text. Use plain prose only when the answer cannot be shaped as options.
Never guess and never leave a bracket placeholder.

## Rounds

Ask in rounds, not one at a time and not all at once. This adapts the `grilling` skill in
https://github.com/mattpocock/skills.

- **Map the decisions as a tree.** A decision depends on another when its options change with the
  other answer.
- **A round asks the frontier:** every decision whose prerequisites are settled. Never put two
  dependent questions in one round. One ask-tool call holds up to 4 questions, so split a larger
  round into several calls.
- **Recommend an answer for each question.** Put it first, marked "(Recommended)", and word the
  question so that "yes" accepts it.
- **Facts are yours, decisions are the user's.** Read the repo, the docs, and the tickets for
  every fact. Never ask the user what a file can answer. Never answer a decision yourself.
- **After each round, recompute the frontier.** An answer can open new decisions or reopen an
  earlier one. Stop when the frontier is empty.
