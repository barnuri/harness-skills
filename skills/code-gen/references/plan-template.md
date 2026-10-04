# Implementation Plan: [FEATURE]

**Branch**: `[branch-name]` | **Date**: [DATE]

## Summary

[Extract from request: primary goal + high-level technical approach]

## Technical Context

**Language/Version**: [e.g., Python 3.11, TypeScript 5.x or N/A]  
**Primary Dependencies**: [key libraries/frameworks involved]  
**Storage**: [if applicable — e.g., PostgreSQL, Redis, files — or N/A]  
**Testing**: [e.g., pytest, jest, unittest or N/A]  
**Target Platform**: [e.g., server, browser, CLI, mobile]  
**Project Type**: [e.g., library / cli / web-service / api / frontend]  
**Scale/Scope**: [e.g., single file, small service, large multi-team feature]  
**Performance Goals**: [domain-specific or N/A]  
**Constraints**: [key constraints, e.g., backwards-compat, API contract, latency]

> Use `[NEEDS CLARIFICATION]` for any field that is unknown. Also add a row to the **Open Questions — Blocking** table at the end of this file for each one — inline markers alone are easy to miss.

## Project Structure

```text
[Relevant directories and files — existing ones to modify + new ones to create]
```

**Structure Decision**: [Explain the layout choice: monorepo, layered, feature-based, etc.]

## Implementation Phases

### Phase 0 — Research & Discovery
- Understand existing patterns and conventions in the repo
- Identify files to modify and new files to create
- Surface unknowns and risks

### Phase 1 — Design
- Define interfaces, types, or contracts
- Confirm data models and storage schema
- Resolve any ambiguities before writing code

### Phase 2 — Implementation
> Detailed step-by-step tasks are tracked in `tasks.md`

## Key Decisions

| Decision | Chosen Approach | Rejected Alternative | Reason |
|----------|----------------|---------------------|--------|
| [e.g., storage] | [chosen] | [alternative] | [why] |

## 🚧 Open Questions — Blocking

> This section stays **last in the file by design** — always append new rows here, never leave a blocking question buried earlier in the plan. A `🔴 Open` row means the task/phase it blocks must pause until the user answers; never guess and proceed past it.

| # | Question | Blocks | Status |
|---|----------|--------|--------|
| Q1 | [question that needs a user decision] | [Task N / Phase] | 🔴 Open |

Resolved rows: flip `Status` to `🟢 Resolved — <decision taken>`. Keep the row for audit history — never delete it.
