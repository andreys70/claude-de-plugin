# The change-plan method

The fix flow uses the rule-out diagnostic method (`diagnostic-method.md`). The enhancement and create flows don't have an "anomaly" to diagnose — there's nothing broken. Instead, they need an explicit **change plan** drafted before any code is written, so the engineer can correct a misunderstanding while it's still cheap.

This document is the method behind that plan. It applies to both:

- **Enhancement** — modifying an existing pipeline. The plan output is `templates/enhancement-plan.md`.
- **Create** — building a net-new pipeline. The plan output is `templates/scaffold-plan.md`.

## Why a plan, not just "go write the code"

The fix flow has a built-in feedback loop: the diagnosis is wrong, the validator catches it, you go back to diagnose. Enhancement and create flows don't have that — there's no anomaly to validate against, only acceptance criteria. Acceptance criteria are derived from the requirements; if you misunderstood the requirements, you'll write code that passes your own criteria but doesn't match what the engineer actually asked for.

The plan is the place to surface that misunderstanding. It's cheap to rewrite a one-page plan; it's expensive to rewrite a coded-and-PRF'd diff.

## Five steps

### 1. Scope the ask

Read the Jira (or freeform spec) end to end. Distill into:

- **What changes?** — concrete, listable.
- **What stays the same?** — name the things people might expect to change but won't.
- **What's out of scope?** — adjacent things the ticket might imply but you're not doing this round. Naming them now prevents scope creep mid-implementation.

### 2. Read the current state

- **Enhancement:** read the existing code/config you'll be modifying. Read enough to know which CTEs, joins, or filters the change touches and what shape they have today.
- **Create:** there is no current code. Instead, find the **closest sibling pipeline** in the repo — one that has the same source pattern, similar sink shape, similar refresh model. The sibling is your structural template. If you can't find a clear sibling, raise that with the engineer before drafting the plan; a wrong sibling will poison the scaffold.

### 3. Propose the diff or scaffold BEFORE writing it

- **Enhancement:** list the files you'll touch and write one sentence per file describing the change. No code yet.
- **Create:** list the files you'll create, mirror them against the sibling's file list, and describe each one's purpose in one sentence.

The orchestrator presents this list to the engineer for approval. Approval here is the cheap checkpoint — much cheaper than reviewing a 200-line diff.

### 4. Name the acceptance criteria up front

The validator's job at PRF is to check the work against the criteria. If you don't write them down here, the validator will guess — and guessing usually means the engineer disagrees with the verdict.

- **Enhancement:** lift criteria directly from the Jira. If the Jira didn't write them out, derive them from the ask and check them with the engineer ("the implicit acceptance criteria are X, Y, Z — agree?").
- **Create:** the first-run-healthy check set is mostly fixed (table exists, schema matches, non-zero rows, required columns populated, no duplicates, row-count order of magnitude). What you add per ticket are: the column list, the "must populate" subset, the primary key, and an expected row-count order of magnitude if the spec gave one.

### 5. Flag assumptions

Anywhere the ticket or spec is ambiguous and you had to pick a default to draft the plan, **state the assumption explicitly** in its own section of the plan output. Examples:

- "Spec didn't say whether `last_settlement_date` should fall back to `last_event_date` if no settlement event exists. Plan assumes NULL when no settlement event."
- "Spec didn't specify partition column. Plan assumes partition by `event_date` matching the sibling pipeline."
- "Jira said 'recent transactions' without a date range. Plan assumes 'last 90 days' based on similar tickets."

The engineer reads these assumptions during plan review and corrects the wrong ones. Each assumption that survives review becomes implicit input to the coder.

## What the plan is NOT

- **Not a design doc.** No background, no rationale, no comparison of alternatives. The Jira and the engineer's prior context already exist.
- **Not pseudocode.** Don't write the code in plain English. "Add column X derived from Y" is enough; the coder will write the SQL.
- **Not a place to negotiate scope.** If the ticket asks for too much, raise it with the engineer separately; don't quietly drop work in the plan and hope no one notices.
- **Not a substitute for reading the existing code.** A plan written without reading the sibling or the current pipeline is a plan written with assumptions. Read first, write the plan second.

## Plan review at the orchestrator's checkpoint

In the enhancement and create flows, **the plan is reviewed inline during Phase 2** (not as a separate post-plan checkpoint, since it's the only thing in Phase 2). The engineer's options at review time:

- **Approve** → coder begins (`mode: enhancement` or `mode: scaffold`).
- **Refine** → orchestrator sends the plan back to the planner with the engineer's correction; another draft.
- **Stop** → workflow ends.

The next checkpoint is **pre-commit** (after the coder has produced a diff, before `git-release-agent` runs). That's where the engineer reviews the actual code against the approved plan.
