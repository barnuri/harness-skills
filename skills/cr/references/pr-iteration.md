# PR Iteration (end of every PR review)

Read this file at the end of every review whose target is a PR. Each run on a PR is one
iteration. After you update the tracker and print the review output, decide what to publish.
Compare `ghx api user -q .login` with `ghx pr view <n> --json author -q .author.login`:

- **Current user is the PR author:** do not ask and do not publish. The review output is the
  delivery. Skip steps 1–4 and record `publish: none (author)` in the tracker. An explicit
  `--comment` still publishes **Both**.
- **Current user is not the PR author:** as the last step of the review, ask with the ask tool
  which to publish: **Both** (recommended), **Inline comments**, **Summary comment**, or
  **None**. When the verdict is `✅ REVIEW SATISFIED`, ask in the same call whether to approve
  (step 4). `--comment` in the arguments answers the publish question with **Both**. The
  approval question still runs.
- **The ask tool is unavailable, or the user declines:** publish nothing and say so.

When `arch-verify` also runs on this PR in this session, the skill that runs last asks once for
both and posts one combined review. The skill that runs first records its items and posts
nothing.

Then run the steps the answer selects. **Inline comments** runs steps 1–2, **Summary comment**
runs step 3, **Both** runs steps 1–3, **None** runs none. Step 4 follows the approval answer
whatever the publish choice. When the user selects both, post the inline comments and the
summary as one review.

## Head re-check (before every post and every approval)

The PR head can move while the review runs. Line anchors from the reviewed commit then land on
the wrong lines.

1. Right before you post a review or approve, run `ghx pr view <n> --json headRefOid,state`.
2. Compare `headRefOid` with the full SHA of the reviewed commit. This is the `headRefOid` that
   **Commit anchoring** read at the start of the run.
3. If the head moved or the PR is no longer open, post nothing and never approve. Report that
   new commits arrived after the review. Offer a gap re-run with the ask tool.
4. If the head did not move, post the review with `commit_id` set to the full reviewed SHA.

## Steps

1. **Resolve fixed threads.** List threads with `ghx api graphql` (`reviewThreads { id isResolved
   resolvedBy { login } isOutdated path line comments { author body } }`). A thread counts as
   resolved only when the current user (`ghx api user -q .login`) resolved it or wrote in it.
   Treat a thread someone else resolved without the current user taking part as unresolved:
   re-check it, and if its finding is still open, reply with why and reopen it
   (`unresolveReviewThread`). For every unresolved thread whose finding
   is now `✅ Fixed`, or whose author reply gives a reason you accept, reply in one line with the
   fixing commit or the reason, then resolve it with the `resolveReviewThread` mutation. Never
   resolve a thread that is still open, or one a human reviewer opened and has not been answered.
   Leave declined-but-wrong replies unresolved and answer them with why it still holds.
2. **New inline comments.** Post one review (`ghx api repos/<o>/<r>/pulls/<n>/reviews`,
   `event: COMMENT`, `commit_id` per **Head re-check**) with one inline comment per `🆕 New`
   finding and per still-open finding whose old thread is outdated. Anchor on a RIGHT-side line
   inside the current diff. Never repeat a finding that already has an open, non-outdated thread.
   For a still-open finding that has an open thread, reply in that thread with the fix instead.

   **One-click fixes.** Make each fix easy for the author to apply:
   - **Simple fix** (a few contiguous lines, a rename, a deletion, a one-line assertion): include
     a GitHub ` ```suggestion ` block with the exact replacement text. This applies to new inline
     comments and to replies in open threads.
   - **Suggestion only for a full fix.** Post a suggestion block only when applying it fixes the
     issue completely. Otherwise give a code snippet.
   - **Keep the indentation.** Copy the exact leading whitespace of each replaced line into the
     suggestion. Change the indentation only when the indentation is the fix.
   - **Anchor on the exact range.** Before you post, read the current file lines. Anchor the
     suggestion on the RIGHT-side range it replaces: `line` for one line, `start_line` + `line`
     for several. A wrong anchor deletes real code when the author applies it.
   - **Deletion:** an empty suggestion block deletes the anchored range.
   - **Fix that spans several places or files:** give the suggestion for the anchored part and a
     code snippet for the rest. Say which part is manual.
   - **Fix that is not simple:** give a concrete code snippet, not prose.
3. **Summary comment.** Put the iteration summary in the review's `body`: commit reviewed and
   gap, fixed / still open / new counts by CR id, threads resolved, and an ordered checklist of
   what is left. Post it even when there are no new inline comments. With **Summary comment**
   alone, post a review with this body and no inline comments, and leave out the threads line,
   because step 1 did not run.
4. **Approval gate.** Only when the verdict is `✅ REVIEW SATISFIED` and the user answered yes to
   the approval question, run `ghx pr review <n> --approve` with a one-line body. Run the
   **Head re-check** first. Never approve without that answer, never approve after the head
   moved, and never request changes unless asked.

Record in the tracker the publish choice, which threads were resolved, and the review URL of each
iteration.
