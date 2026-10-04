// Tests for code-gen-implement.js.
//
// The Workflow runtime is not importable, so this stubs it: a faithful pipeline() (each item runs
// through every stage independently, no barrier between stages), a recording agent(), and a log()
// that captures the narrator lines. The script body is then executed inside an async function, the
// same context the real runtime provides — which is why a top-level `return` is legal there and
// `node --check` on the bare file is not a valid syntax test.
//
// The properties worth protecting are the ones that are silent when wrong:
//   - batching: consecutive parallel_safe tasks with DISJOINT file sets run together; an overlap
//     or a non-parallel task splits the batch. Get this wrong and two agents edit one file.
//   - a task whose files cannot be enumerated is serial no matter what the caller claimed
//   - a claimed no-op skips review only when a cheap git-evidence agent confirms a clean diff;
//     a dirty diff or an unverifiable claim (no file scope) runs the full review instead
//   - the reviewer's prompt never carries the implementer's summary (priming)
//   - a dead/skipped implement agent surfaces as blocked instead of vanishing from the results
//   - bad args fail loudly rather than fanning out over garbage
//
// Run: node workflows/code-gen-implement.test.mjs

import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const SRC = join(dirname(fileURLToPath(import.meta.url)), 'code-gen-implement.js')
const body = readFileSync(SRC, 'utf8').replace('export const meta', 'const meta')

const calls = []
let live = 0
let peak = 0

function makeHarness(args, agentImpl, budgetOverride) {
    const log = (m) => calls.push({ kind: 'log', m })
    const budget = budgetOverride || { total: null, spent: () => 0, remaining: () => Infinity }
    const pipeline = async (items, ...stages) =>
        Promise.all(
            items.map(async (item, i) => {
                let prev = item
                for (const stage of stages) prev = await stage(prev, item, i)
                return prev
            }),
        )
    const parallel = async (thunks) => Promise.all(thunks.map((t) => t().catch(() => null)))
    const phase = () => {}
    const agent = agentImpl
    return { log, budget, pipeline, parallel, phase, agent, args }
}

async function run(args, agentImpl, budgetOverride) {
    const h = makeHarness(args, agentImpl, budgetOverride)
    const fn = new Function(
        'args', 'agent', 'pipeline', 'parallel', 'log', 'phase', 'budget',
        `return (async () => { ${body} })()`,
    )
    return fn(h.args, h.agent, h.pipeline, h.parallel, h.log, h.phase, h.budget)
}

let tick = 0
const defaultAgent = async (prompt, opts) => {
    live++
    peak = Math.max(peak, live)
    calls.push({ kind: 'agent', label: opts.label, phase: opts.phase, start: tick++ })
    await new Promise((r) => setTimeout(r, 5))
    live--
    calls.push({ kind: 'end', label: opts.label, end: tick++ })
    const id = opts.label.split(':')[1]
    if (opts.phase === 'Implement') {
        return { task_id: id, status: 'ok', summary: 'did it', files_written: ['f'], no_op: false }
    }
    return { task_id: id, verdict: 'satisfied', findings: [] }
}

let failures = 0
const check = (name, cond, extra) => {
    if (cond) { console.log(`  PASS: ${name}`) }
    else { failures++; console.log(`  FAIL: ${name}${extra ? ` — ${extra}` : ''}`) }
}

// --- 1. disjoint [P] tasks batch together; overlapping ones do not ---
calls.length = 0; peak = 0
let res = await run(
    {
        tasks: [
            { id: 'T1', description: 'a', files: ['a.py'], parallel_safe: true },
            { id: 'T2', description: 'b', files: ['b.py'], parallel_safe: true },
            { id: 'T3', description: 'c', files: ['b.py'], parallel_safe: true }, // overlaps T2
            { id: 'T4', description: 'd', files: ['d.py'], parallel_safe: false }, // serial
        ],
    },
    defaultAgent,
)
console.log('--- batching ---')
const batchLog = calls.filter((c) => c.kind === 'log' && /batch\(es\)/.test(c.m)).map((c) => c.m)[0]
check('3 batches for [T1+T2][T3][T4]', /in 3 batch\(es\)/.test(batchLog), batchLog)
check('widest batch is 2', /widest batch 2/.test(batchLog), batchLog)
check('concurrency observed >= 2', peak >= 2, `peak=${peak}`)
check('all 4 tasks returned', res.tasks.length === 4)

// Interval overlap on the recorded start/end ticks: T1 and T2 are disjoint so they must overlap;
// T3 touches b.py like T2 does, so it must not start until T2 has finished.
const span = (label) => ({
    start: calls.find((c) => c.kind === 'agent' && c.label === label).start,
    end: calls.find((c) => c.kind === 'end' && c.label === label).end,
})
const overlap = (a, b) => a.start < b.end && b.start < a.end
check('T1 and T2 overlap (disjoint files)', overlap(span('impl:T1'), span('impl:T2')))
check('T3 does not overlap T2 (both touch b.py)', !overlap(span('impl:T2'), span('impl:T3')))
check('T4 does not overlap T3 (not parallel_safe)', !overlap(span('impl:T3'), span('impl:T4')))

// --- 2. task with no files is forced serial even if parallel_safe claimed ---
calls.length = 0
res = await run(
    {
        tasks: [
            { id: 'T1', description: 'a', files: [], parallel_safe: true },
            { id: 'T2', description: 'b', files: [], parallel_safe: true },
        ],
    },
    defaultAgent,
)
console.log('--- unenumerable files force serial ---')
const b2 = calls.filter((c) => c.kind === 'log' && /batch\(es\)/.test(c.m)).map((c) => c.m)[0]
check('2 separate batches', /in 2 batch\(es\)/.test(b2), b2)
check('widest batch is 1', /widest batch 1/.test(b2), b2)

// --- 3. no-op skips review ONLY on verified-clean git evidence ---
const makeNoopAgent = (clean) => async (prompt, opts) => {
    calls.push({ kind: 'agent', label: opts.label, phase: opts.phase, prompt, effort: opts.effort })
    const id = opts.label.split(':')[1]
    if (opts.phase === 'Implement') {
        return { task_id: id, status: 'ok', summary: 'nothing to do', files_written: [], no_op: true }
    }
    if (opts.label.startsWith('verify-noop:')) {
        return { task_id: id, clean, evidence: 'git diff --stat HEAD -- a.py\n(empty)' }
    }
    return { task_id: id, verdict: 'satisfied', findings: [] }
}
const isReview = (c) => c.kind === 'agent' && c.label.startsWith('review:')
const isVerify = (c) => c.kind === 'agent' && c.label.startsWith('verify-noop:')

calls.length = 0
res = await run({ tasks: [{ id: 'T1', description: 'a', files: ['a.py'], parallel_safe: false }] }, makeNoopAgent(true))
console.log('--- no-op with clean diff ---')
check('verifier agent spawned', calls.some(isVerify))
check('verifier runs at low effort', calls.find(isVerify).effort === 'low')
check('no full review spawned', !calls.some(isReview))
check('verdict reported as skipped', res.tasks[0].review_verdict === 'skipped')
check('skip is logged with evidence basis', calls.some((c) => c.kind === 'log' && /no-op verified against git/.test(c.m)))

calls.length = 0
res = await run({ tasks: [{ id: 'T1', description: 'a', files: ['a.py'], parallel_safe: false }] }, makeNoopAgent(false))
console.log('--- no-op with dirty diff ---')
check('verifier agent spawned', calls.some(isVerify))
check('full review runs despite no_op claim', calls.some(isReview))
check('contradiction is logged', calls.some((c) => c.kind === 'log' && /git shows changes/.test(c.m)))

calls.length = 0
res = await run({ tasks: [{ id: 'T1', description: 'a', files: [], parallel_safe: false }] }, makeNoopAgent(true))
console.log('--- no-op with no file scope ---')
check('no verifier spawned (nothing objective to check)', !calls.some(isVerify))
check('full review runs (unverifiable claim)', calls.some(isReview))
check('unverifiable path is logged', calls.some((c) => c.kind === 'log' && /no file scope to verify/.test(c.m)))

// --- 4. blocked task short-circuits review and is surfaced ---
calls.length = 0
const blockedAgent = async (prompt, opts) => {
    calls.push({ kind: 'agent', label: opts.label, phase: opts.phase })
    const id = opts.label.split(':')[1]
    if (opts.phase === 'Implement') {
        return { task_id: id, status: 'blocked', summary: 's', files_written: [], no_op: false, blocker: 'which db?' }
    }
    return { task_id: id, verdict: 'satisfied', findings: [] }
}
res = await run({ tasks: [{ id: 'T1', description: 'a', files: ['a.py'], parallel_safe: false }] }, blockedAgent)
console.log('--- blocked task ---')
check('no review agent spawned', !calls.some((c) => c.kind === 'agent' && c.phase === 'Review'))
check('blocked id surfaced to caller', res.blocked_ids.length === 1 && res.blocked_ids[0] === 'T1')
check('blocker text preserved', res.tasks[0].blocker === 'which db?')

// --- 5. bad args fail loudly ---
console.log('--- arg validation ---')
try {
    await run({ tasks: [] }, defaultAgent)
    check('empty task list throws', false)
} catch (e) {
    check('empty task list throws', /non-empty array/.test(e.message), e.message)
}
try {
    await run({ tasks: '[{"id":"T1"}]' }, defaultAgent)
    check('stringified task list throws', false)
} catch (e) {
    check('stringified task list throws', /non-empty array/.test(e.message), e.message)
}

// --- 6. needs_fixes propagates ---
calls.length = 0
const findingAgent = async (prompt, opts) => {
    const id = opts.label.split(':')[1]
    if (opts.phase === 'Implement') {
        return { task_id: id, status: 'ok', summary: 's', files_written: ['a.py'], no_op: false }
    }
    return { task_id: id, verdict: 'needs_fixes', findings: [{ file: 'a.py', confidence: 90, issue: 'x', fix: 'y' }] }
}
res = await run({ tasks: [{ id: 'T1', description: 'a', files: ['a.py'], parallel_safe: false }] }, findingAgent)
console.log('--- review findings ---')
check('needs_fixes id surfaced', res.needs_fixes_ids[0] === 'T1')
check('findings carried through', res.tasks[0].findings.length === 1)

// --- 7. reviewer prompt is lean: no implementer summary, reads the diff itself ---
calls.length = 0
const promptCapture = []
const capturingAgent = async (prompt, opts) => {
    if (opts.label.startsWith('review:')) { promptCapture.push(prompt) }
    const id = opts.label.split(':')[1]
    if (opts.phase === 'Implement') {
        return { task_id: id, status: 'ok', summary: 'SECRET-IMPL-REASONING', files_written: ['a.py'], no_op: false }
    }
    return { task_id: id, verdict: 'satisfied', findings: [] }
}
await run({ tasks: [{ id: 'T1', description: 'a', files: ['a.py'], parallel_safe: false }] }, capturingAgent)
console.log('--- reviewer prompt isolation ---')
check('reviewer prompt has no implementer summary', !promptCapture[0].includes('SECRET-IMPL-REASONING'))
check('reviewer told to read the diff itself', /git diff/.test(promptCapture[0]))

// --- 8. budget floor skips review, loudly ---
calls.length = 0
res = await run(
    { tasks: [{ id: 'T1', description: 'a', files: ['a.py'], parallel_safe: false }] },
    defaultAgent,
    { total: 100_000, spent: () => 70_000, remaining: () => 30_000 },
)
console.log('--- budget floor ---')
check('no review agent under budget floor', !calls.some(isReview))
check('verdict reported as skipped', res.tasks[0].review_verdict === 'skipped')
check('floor skip is logged loudly', calls.some((c) => c.kind === 'log' && /under 40k tokens remaining\. NOT reviewed/.test(c.m)))

// --- 9. dead implement agent surfaces as blocked, never vanishes ---
calls.length = 0
const deadAgent = async (prompt, opts) => {
    calls.push({ kind: 'agent', label: opts.label, phase: opts.phase })
    const id = opts.label.split(':')[1]
    if (opts.phase === 'Implement') {
        return id === 'T1' ? null : { task_id: id, status: 'ok', summary: 's', files_written: ['b.py'], no_op: false }
    }
    return { task_id: id, verdict: 'satisfied', findings: [] }
}
res = await run(
    {
        tasks: [
            { id: 'T1', description: 'a', files: ['a.py'], parallel_safe: false },
            { id: 'T2', description: 'b', files: ['b.py'], parallel_safe: false },
        ],
    },
    deadAgent,
)
console.log('--- dead implement agent ---')
check('both tasks present in results', res.tasks.length === 2)
check('dead task surfaced as blocked', res.blocked_ids.includes('T1'))
check('healthy task unaffected', res.tasks.some((t) => t.id === 'T2' && t.status === 'ok'))
check('death is logged, not silent', calls.some((c) => c.kind === 'log' && /returned no result/.test(c.m)))

console.log(`\n${failures === 0 ? 'ALL PASS' : failures + ' FAILED'}`)
process.exit(failures === 0 ? 0 : 1)
