# Interactive Modes

Two modes talk with the user. The grill-the-author mode adapts the round-based interview idea
from the `grilling` skill in https://github.com/mattpocock/skills.

## Grill the author

You ask. The user answers. The goal is a shared understanding of every open decision in the
design, with nothing assumed.

### Build the decision tree

1. Start from the attack review: every finding, every challenge question, and every open `Q:`
   line in the design.
2. Turn each item into one decision the author must make. Example: "Retry a failed webhook, or
   drop it?"
3. Link each decision to the decisions it depends on. A decision depends on another when its
   options change with the other answer.

### Ask in rounds

A round holds the **frontier**: every decision whose prerequisites are already settled. Do not
put two dependent questions in one round. The later question waits for the next round.

For each question:

1. Number it `G<n>`. Keep the numbers stable for the whole session.
2. Give a short title and the body: the context, the evidence, and the options.
3. Give your recommended answer, with a one-line reason.
4. Word the question so that "yes" accepts your recommendation.

Ask the round with the ask tool (`AskUserQuestion` or the harness equivalent):

- Put the recommended option first, with "(Recommended)" at the end of its label.
- One call holds at most 4 questions. Split a larger round into several calls, one after the
  other. They are still one round.
- When the harness has no ask tool, print the round as a numbered list. Put each recommendation
  on its own line that starts with `➡️`. Then end the turn and wait.
- When the user asked for one question at a time, ask one question per call.

### Facts are yours, decisions are the user's

- Find facts yourself. Read the design, the repo, and the docs it cites. Never ask the user a
  question that a file can answer.
- When a fact needs a long search and a subagent tool exists, dispatch a subagent for it. Ask the
  questions that do not depend on that fact now. Only the dependent questions wait.
- Never answer a decision yourself. Put it to the user and wait.

### After each round

1. Record each answer in the report's Grilling log.
2. Give each answer a resolution: `Decision`, `Accepted risk`, `Design change`, or `Follow-up`.
   A `Follow-up` names the person or team outside this session who must answer it.
3. Compute the new frontier. An answer can settle a decision, open a new one, or show that an
   earlier answer was wrong. Reopen that branch in the next round.

### End

The session ends when the frontier is empty. Then ask the user to confirm the shared
understanding. Do not change any file until the user confirms. When the user says "stop" or
"wrap up", end at once and write what you have.

There is no question cap. A large number of questions means the design scope is large. Say so,
and offer to review one component at a time.

## The user grills the design

The user asks. You answer from the design only.

For each question:

1. Search the design text for the answer.
2. Classify the answer:

   | Class | Meaning | What you write |
   |---|---|---|
   | ✅ Answered | The design states it. | The answer, with a quote and its section, `R<n>`, or `D<n>`. |
   | ⚠️ Partial | The design states part of it. | The part it states, and the part that is missing. |
   | ❌ Silent | The design does not state it. | "The design does not say." Add a finding. |
   | 🔀 Contradicted | Two parts of the design disagree. | Both quotes. Add a 🔴 or 🟠 finding. |

3. Never present general knowledge as the design's answer. When you add a suggestion, label it
   "Suggestion, not in the design".
4. Record the question and its class in the report's Grilling log.

Continue until the user says they are done. Then offer one challenge question the user did not
ask, from the attack review.
