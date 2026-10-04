export const meta = {
  name: 'code-gen-implement',
  description: 'Implement a code-gen task list: implement then review each task, pipelined',
  whenToUse:
    'Invoked by the code-gen skill for Medium/Large sessions once tasks.md holds a real task list. Not for Small tasks — orchestration overhead exceeds the benefit on a one-file change.',
  phases: [
    { title: 'Implement', detail: 'one agent per task, batched by disjoint file sets' },
    { title: 'Review', detail: 'per-task review, starts as soon as that task lands' },
  ],
}

// WHY THIS SCRIPT EXISTS
//   skills/code-gen/SKILL.md's tasks.md template has emitted `[P]` "parallel-safe" markers and a
//   legend for them since it was written, and no step in the skill ever read them — every task ran
//   serially. This is the executor that makes `[P]` mean something.
//
// WHAT IT IS NOT
//   It is not an orchestrator that owns the session. The PARENT (the code-gen skill) still owns
//   agent-spec/<slug>/plan.md, tasks.md, their timestamp headers, and the native task mirror.
//   Agents spawned here return DATA; they never write durable state. That separation is what keeps
//   hooks/stop-completion-gate.sh — which greps tasks.md for "^- \[ \]" — working unchanged. If an
//   agent here ever starts writing tasks.md, the completion gate silently stops protecting anything.
//
// DYNAMIC, NOT FIXED
//   Fan-out width is args.tasks.length, parsed from tasks.md at runtime. Saving this file under a
//   name does not freeze it — the shape of each run comes from args.
//
// PIPELINE, NOT BARRIER
//   pipeline() runs each task through implement -> review independently. Task 1 is being reviewed
//   while task 2 is still being implemented. A barrier (parallel() between stages) would be wrong
//   here: reviewing task 1 never needs task 2's result.
//
// ORDERING
//   Tasks are NOT all thrown at pipeline() at once — that would run dependent tasks concurrently.
//   Consecutive parallel_safe tasks with provably disjoint file sets form a batch; a batch is
//   pipelined; batches run in order. Anything not provably disjoint runs as a batch of one.

const MAX_BATCH = 4

// Below this many output tokens remaining, stop spawning review agents. Reported via log() rather
// than dropped silently — a truncated run that looks complete is worse than a noisy one.
const REVIEW_BUDGET_FLOOR = 40_000

const IMPL_SCHEMA = {
  type: 'object',
  required: ['task_id', 'status', 'summary', 'files_written', 'no_op'],
  additionalProperties: false,
  properties: {
    task_id: { type: 'string' },
    status: { type: 'string', enum: ['ok', 'blocked', 'error'] },
    summary: { type: 'string', description: 'What changed, one or two sentences' },
    files_written: { type: 'array', items: { type: 'string' } },
    no_op: { type: 'boolean', description: 'True when the edit would not have changed any file' },
    blocker: { type: 'string', description: 'Set only when status is blocked — the decision the user must make' },
    tests_run: { type: 'array', items: { type: 'string' }, description: 'Test commands actually executed' },
  },
}

const REVIEW_SCHEMA = {
  type: 'object',
  required: ['task_id', 'verdict', 'findings'],
  additionalProperties: false,
  properties: {
    task_id: { type: 'string' },
    verdict: { type: 'string', enum: ['satisfied', 'needs_fixes', 'skipped'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'confidence', 'issue', 'fix'],
        additionalProperties: false,
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          confidence: { type: 'integer', description: '0-100; only report at 80 or above' },
          issue: { type: 'string' },
          fix: { type: 'string' },
        },
      },
    },
  },
}

// Return shape of the cheap git-evidence check that gates a review skip on a claimed no-op.
const NOOP_VERIFY_SCHEMA = {
  type: 'object',
  required: ['task_id', 'clean'],
  additionalProperties: false,
  properties: {
    task_id: { type: 'string' },
    clean: { type: 'boolean', description: 'True only when git shows no changes over the scoped paths' },
    evidence: { type: 'string', description: 'The exact git commands run and their (possibly empty) output' },
  },
}

function fail(message) {
  throw new Error(`code-gen-implement: ${message}`)
}

function normalizeTasks(raw) {
  if (!Array.isArray(raw) || raw.length === 0) {
    fail('args.tasks must be a non-empty array. Pass the parsed tasks.md entries, not a JSON string.')
  }
  return raw.map((t, i) => {
    if (!t || typeof t !== 'object') { fail(`task at index ${i} is not an object`) }
    const id = String(t.id || `T${i + 1}`)
    const files = Array.isArray(t.files) ? t.files.filter((f) => typeof f === 'string' && f.length > 0) : []
    return {
      id,
      description: String(t.description || '').trim(),
      files,
      // A task with no enumerated files can never be proven disjoint from anything, so it is
      // serial regardless of what the caller claimed. Default is always serial.
      parallel_safe: Boolean(t.parallel_safe) && files.length > 0,
    }
  })
}

function overlaps(a, b) {
  return a.some((f) => b.includes(f))
}

// Consecutive parallel_safe tasks whose file sets are pairwise disjoint. Order is preserved, so a
// serial task acts as a barrier for everything after it.
function batchTasks(tasks) {
  const batches = []
  let current = []
  let claimed = []

  for (const task of tasks) {
    const canJoin = task.parallel_safe && current.length > 0 && current.length < MAX_BATCH && !overlaps(task.files, claimed)

    if (canJoin) {
      current.push(task)
      claimed = claimed.concat(task.files)
      continue
    }

    if (current.length > 0) { batches.push(current) }

    if (task.parallel_safe) {
      current = [task]
      claimed = task.files.slice()
    } else {
      batches.push([task])
      current = []
      claimed = []
    }
  }

  if (current.length > 0) { batches.push(current) }
  return batches
}

function implementPrompt(task, context) {
  return [
    `Implement exactly one task from an in-progress code-gen session. Do not start any other task.`,
    ``,
    `Task ${task.id}: ${task.description}`,
    task.files.length > 0 ? `Files in scope (do not write outside this set): ${task.files.join(', ')}` : `Files in scope: determine from the task description; keep the change minimal.`,
    context ? `\nSession context:\n${context}` : ``,
    ``,
    `Rules:`,
    `- ${guidelinesRule()} Match the surrounding code's naming, comment density, and idiom.`,
    `- Do NOT write to agent-spec/ — plan.md and tasks.md are owned by the caller, not by you.`,
    `- Do NOT create branches, commit, or push.`,
    `- If the change turns out to be a no-op (the file already has this), set no_op true and write nothing.`,
    `- If you hit a decision only the user can make, set status "blocked" and describe it in "blocker" instead of guessing.`,
    `- If the task is to write tests, actually run them and list the commands in tests_run. A test written but not run is not done.`,
  ]
    .filter(Boolean)
    .join('\n')
}

// A no-op claim is exactly the kind of self-report a reviewer exists to distrust ("verification
// avoidance"): the skip is allowed only on git evidence, never on the implementer's word.
function noopVerifyPrompt(task, scope) {
  return [
    `An implementation agent claims task ${task.id} was a no-op — that it changed no file.`,
    `Verify that claim with git evidence; do not take its word for it.`,
    ``,
    `Run both, scoped to exactly these paths:`,
    `  git diff --stat HEAD -- ${scope.join(' ')}`,
    `  git status --porcelain -- ${scope.join(' ')}`,
    ``,
    `Return clean=true ONLY if both commands show no changes for these paths. Put the commands and`,
    `their raw output in "evidence". Do not modify anything.`,
  ].join('\n')
}

// The reviewer deliberately never sees the implementer's summary or reasoning — access to the
// worker's account primes the verifier to agree with it. It gets the task and the file list, and
// reads the diff itself.
function guidelinesRule() {
  if (guidelines.length === 0) {
    return `No guideline files are configured: follow the repo's CLAUDE.md/AGENTS.md.`
  }
  return `Coding standards: read ${guidelines.join(', ')} before judging or writing code.`
}

function reviewPrompt(task, filesWritten) {
  return [
    `Review the change just made for task ${task.id}: ${task.description}`,
    ``,
    `Files written: ${filesWritten.join(', ') || '(none reported — locate the change via git status)'}`,
    `Read the actual diff yourself (git diff HEAD -- <files>) and judge the change on its own.`,
    `You have intentionally not been given the implementer's summary or reasoning.`,
    ``,
    `Precision over volume. Only report findings you are confident about — confidence 80 or above.`,
    `Do not flag pre-existing issues outside this change, linter-catchable formatting, or subjective`,
    `style not covered by the coding standards. ${guidelinesRule()}`,
    ``,
    `Return verdict "satisfied" when nothing reaches confidence 80, "needs_fixes" otherwise.`,
  ].join('\n')
}

// ---- run ----

const tasks = normalizeTasks(args && args.tasks)
const context = args && typeof args.context === 'string' ? args.context : ''
const guidelines = args && Array.isArray(args.guidelines) ? args.guidelines.filter(g => typeof g === 'string') : []

// Optional agent-type overrides. The code-gen skill passes implementerAgent
// 'barnuri-dev-skills:implementer' (agents/implementer.md); left unset the script still runs
// against the default workflow subagent, which keeps it usable where plugin agents don't resolve.
const implAgent = args && args.implementerAgent ? { agentType: args.implementerAgent } : {}
const reviewAgent = args && args.reviewerAgent ? { agentType: args.reviewerAgent } : {}
const skipReview = Boolean(args && args.skipReview)

const batches = batchTasks(tasks)
log(`${tasks.length} task(s) in ${batches.length} batch(es); widest batch ${Math.max(...batches.map((b) => b.length))}`)

const results = []

for (const batch of batches) {
  if (batch.length > 1) { log(`Batch: ${batch.map((t) => t.id).join(', ')} — disjoint file sets, running together`) }

  const batchResults = await pipeline(
    batch,
    (task) =>
      agent(implementPrompt(task, context), {
        label: `impl:${task.id}`,
        phase: 'Implement',
        schema: IMPL_SCHEMA,
        ...implAgent,
      }),

    async (impl, task) => {
      // A dead or user-skipped implement agent must surface as a blocked task, never vanish —
      // a null dropped here would leave the parent with no signal that the task never ran.
      if (!impl) {
        log(`${task.id}: implementation agent returned no result (skipped or died) — surfaced as blocked`)
        return {
          task,
          impl: {
            task_id: task.id,
            status: 'blocked',
            summary: '',
            files_written: [],
            no_op: false,
            blocker: 'Implementation agent returned no result (skipped or died)',
          },
          review: { task_id: task.id, verdict: 'skipped', findings: [] },
        }
      }

      const skipped = { task, impl, review: { task_id: task.id, verdict: 'skipped', findings: [] } }

      if (impl.status !== 'ok') {
        log(`${task.id}: ${impl.status}${impl.blocker ? ` — ${impl.blocker}` : ''}`)
        return skipped
      }

      if (skipReview) {
        return skipped
      }

      // A claimed no-op may skip review, but only on git evidence — never on the implementer's own
      // word (that would be the "verification avoidance" failure mode). A cheap low-effort agent
      // checks the diff over the task's paths; with no enumerable paths there is nothing objective
      // to check against, so the full review runs.
      if (impl.no_op) {
        const scope = [...new Set([...task.files, ...impl.files_written])]
        if (scope.length === 0) {
          log(`${task.id}: no-op claimed but no file scope to verify against — running full review`)
        } else {
          const verdict = await agent(noopVerifyPrompt(task, scope), {
            label: `verify-noop:${task.id}`,
            phase: 'Review',
            effort: 'low',
            schema: NOOP_VERIFY_SCHEMA,
          })
          if (verdict && verdict.clean) {
            log(`${task.id}: no-op verified against git (clean diff), review skipped`)
            return skipped
          }
          log(`${task.id}: no-op claimed but ${verdict ? 'git shows changes' : 'verification failed'} — running full review`)
        }
      }

      if (budget.total && budget.remaining() < REVIEW_BUDGET_FLOOR) {
        log(`${task.id}: review skipped — under ${REVIEW_BUDGET_FLOOR / 1000}k tokens remaining. NOT reviewed.`)
        return skipped
      }

      const review = await agent(reviewPrompt(task, impl.files_written), {
        label: `review:${task.id}`,
        phase: 'Review',
        schema: REVIEW_SCHEMA,
        ...reviewAgent,
      })
      return { task, impl, review }
    },
  )

  results.push(...batchResults.filter(Boolean))
}

// The caller marks tasks.md and the native task list from this. Nothing here does.
const blocked = results.filter((r) => r.impl.status === 'blocked')
const needsFixes = results.filter((r) => r.review && r.review.verdict === 'needs_fixes')

log(`Done: ${results.length} task(s), ${blocked.length} blocked, ${needsFixes.length} needing fixes`)

return {
  tasks: results.map((r) => ({
    id: r.task.id,
    status: r.impl.status,
    no_op: r.impl.no_op,
    summary: r.impl.summary,
    files_written: r.impl.files_written,
    tests_run: r.impl.tests_run || [],
    blocker: r.impl.blocker || null,
    review_verdict: r.review ? r.review.verdict : 'skipped',
    findings: r.review ? r.review.findings : [],
  })),
  blocked_ids: blocked.map((r) => r.task.id),
  needs_fixes_ids: needsFixes.map((r) => r.task.id),
}
