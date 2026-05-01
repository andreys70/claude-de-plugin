---
description: End-to-end implementation of an enhancement (or optimization, or any non-bug change) against an existing ETL pipeline — intake, change plan, code change, commit/push/PR, PRF validation, PRD execution, post-deploy verification, and Jira close-out.
argument-hint: <JIRA-KEY>
---

You are now driving the **enhancement workflow** for data-forge. This slash command is the orchestrator — it runs in the main session, which means you CAN spawn specialist sub-agents via the `Agent` tool. Each sub-agent does scoped work and returns a summary; you stitch the workflow together and gate on engineer approval at the two checkpoints.

Input from the engineer: `$ARGUMENTS`

Enhancements should always have a Jira ticket. If `$ARGUMENTS` is empty, ask:

> "Provide a Jira key for the enhancement (e.g., `FIND-742`). Enhancement work always needs a ticket — if you don't have one, run `/data-forge:dispatch` and we'll route to the right workflow (e.g., `/data-forge:data-creator` for net-new pipeline scaffolding)."

This is the enhancement counterpart to `/data-forge:data-issue-fix`. Key differences from the fix workflow:

- There is **no diagnosis phase** — nothing is broken, so there's no anomaly to root-cause. Phase 2 is **scope & change plan** instead.
- The plan is reviewed **inline during Phase 2**, not as a separate post-plan checkpoint.
- There are **two checkpoints** (pre-commit, post-PRF), not three.
- The validator runs in **`acceptance-criteria` mode**, not `anomaly-resolved`.

## Shared patterns — read first

The whole agent family shares patterns documented in the `data-work-patterns` skill:

- **`${CLAUDE_PLUGIN_ROOT}/skills/data-work-patterns/refs/guardrails.md`** — the approval / checkpoint / destructive-action policy. Read before running Phase 1.
- **`${CLAUDE_PLUGIN_ROOT}/skills/data-work-patterns/refs/change-plan-method.md`** — the method behind the Phase 2 plan. Read this before drafting a plan.
- **`${CLAUDE_PLUGIN_ROOT}/skills/data-work-patterns/templates/enhancement-plan.md`** — the plan output format. Phase 2 produces this.

Any conflict between this command and the skill's guardrails → stricter rule wins.

## Phase 0 — Hard requirements (fail fast)

Before any other work, run the MCP-registered check defined in:

**`${CLAUDE_PLUGIN_ROOT}/skills/data-work-patterns/refs/mcp-prerequisites.md`**

For the enhancement flow: **all four MCPs are required.** Read the skill ref and follow it exactly — toolset inspection only, no MCP calls, deferred authentication.

If any required MCP is missing, stop with the message specified in the skill ref. Otherwise proceed to Phase 1.

## Delegation rule — you do not call MCP work tools directly

Your only MCP touchpoints are the four Phase 0 toolset-presence checks. **Every other MCP interaction is delegated to a sub-agent via `Agent`.** This is by design — the sub-agents own the read/write tools for their respective MCPs:

| MCP work | Delegated to |
|---|---|
| reading Jira tickets / posting comments / transitioning status | `data-work-intake`, `jira-commenter` |
| running verification SQL | `data-validator` |
| executing BPP pipelines | `bpp-pipeline-runner` |
| opening pull requests | `git-release-agent` |

If you find yourself wanting to call `mcp__databricks-mcp__execute_sql` or `mcp__jira-mcp__add_comment` or any other action tool, **stop**. Invoke the matching sub-agent instead. You're the orchestrator; you don't do the work, you route it.

## The pipeline — nine phases

### Phase 1 — Intake

Invoke `data-work-intake` with `mode: enhancement`. The intake report surfaces what the ticket asks for, prior design discussion, the data surface area being changed, and any open questions the planning phase needs to resolve.

After intake returns, summarize what was found, then proceed to Phase 2.

### Phase 2 — Scope & change plan

This is the planning phase. Do **not** delegate to a separate planner agent — keep the planning here in the orchestrator.

Steps (per `refs/change-plan-method.md`):

1. **Scope the ask** from the intake report — what changes, what stays the same, what's out of scope.
2. **Read the current code** that will be modified. Locate the file(s), the CTEs/joins/filters being touched, and any downstream consumers of `SELECT *` that the change might affect.
3. **Draft the plan** in the format of `templates/enhancement-plan.md`: files to touch, one-line description per file, acceptance criteria lifted from the Jira, assumptions for any ambiguity, risks for PRF.
4. **Present the plan inline** to the engineer:

   > "Here is the proposed change plan. Review before I start writing code? (approve / refine / stop)"

   - **On "approve":** proceed to Phase 3a.
   - **On "refine":** take the engineer's correction, redraft, present again. Repeat until approved.
   - **On "stop":** end the flow.

The plan is the cheap correction point. A misunderstood ask caught here saves rewriting a coded-and-PRF'd diff.

### Phase 3a — Working branch (before any file edits)

Before invoking the coder, ensure the engineer is on a working branch — not a protected one — so the upcoming edits don't land on `main` / `master` / `develop`.

Run `git branch --show-current`. Then:

- **If current branch is protected** (`main`, `master`, `develop`) **OR does not contain the Jira key**, ask:

  > "You're on `<current-branch>`. Cut a new working branch before I make edits?
  >
  > Suggested: `feature/<JIRA-KEY>`
  >
  > (yes / stay on `<current-branch>` / custom name)"

  On `yes` or a custom name, run `git checkout -b <name>`. Uncommitted changes (if any) carry forward automatically — no stash needed.

  On `stay`: refuse if the branch is protected and re-prompt. Otherwise proceed, but note the unusual branch choice in the final recap.

- **If current branch already matches** `feature/<JIRA-KEY>` or an obvious variant, proceed silently.

### Phase 3 — Code change

Invoke `data-pipeline-coder` with `mode: enhancement` and the approved change plan from Phase 2.

**⚠️ CHECKPOINT 1 — Diff review** (per `guardrails.md`). Present the full diff and ask:

> "Here is the proposed change. I **strongly recommend** reviewing before commit, especially against the acceptance criteria from the plan. Approve the diff? (approve / refine / stop)"

- **On "approve":** proceed to Phase 4.
- **On "refine":** loop back to `data-pipeline-coder` (still `mode: enhancement`) with the engineer's correction; produce a new diff and re-ask.
- **On "stop":** end the flow.

### Phase 4 — Commit, push, PR

Invoke `git-release-agent` to commit, push, and optionally open a PR. The agent asks before every destructive step, regardless of prior approvals.

### Phase 5 — PRF pipeline execution (pre-prod)

> "Phase 5: How do you want to run the change against PRF?
>   1. BPP pipeline — I'll execute it (need the PRF pipeline name)
>   2. EMR Serverless / local / other — I'll wait for you to confirm it's done
>   3. Skip — proceed directly to PR merge + PRD (not recommended)"

**On (1):** ask for the PRF pipeline name. Then invoke `bpp-pipeline-runner` with that name and `execution_environment=PRD` (BPP's PRD maps to the PRF pipeline's prod-registered entry; environment selection in BPP refers to the BPP environment, not the data env). Poll to completion. On success, proceed to Phase 6.

**On (2):** wait for engineer to say "done." Ask which target table to validate against in Phase 6.

**On (3):** skip both Phase 5 and Phase 6. Note in the final recap that PRF validation was bypassed. Proceed directly to Phase 7.

### Phase 6 — PRF validation

Invoke `data-validator` with **`mode: acceptance-criteria`** against the PRF target table. Pass the acceptance criteria from the approved plan. The validator pre-checks the refresh gate and then runs each criterion as its own check, plus a regression spot-check and row count sanity.

**⚠️ CHECKPOINT 2 — PRF results gate** (per `guardrails.md`). Present the validation report and ask:

> "PRF validation shows: <summary, per criterion + regression spot-check>. Proceed to PRD? (yes / adjust / stop)"

- **On "yes":** proceed to Phase 7.
- **On "adjust":** loop back to Phase 3 (code change) with specific feedback, then re-run Phases 4–6.
- **On "stop":** end the flow. The change needs more work. Engineer decides next steps.

### Phase 7 — PRD pipeline execution (BPP)

After PRF validation passes and the PR is merged, execute the production pipeline via BPP. **Merging is the engineer's action** — do not poll GitHub for it, do not attempt to merge it yourself.

When Phase 6 gate returns "yes," ask:

> "Ready for PRD. Once you've merged the PR, let me know and I'll offer to run the BPP pipeline."

When the engineer confirms the merge:

> "Run the BPP pipeline now? The pipeline name typically lives in the Jira `Dev Portal Asset Alias` field. (yes / skip / not yet)"

**On "yes":** invoke `bpp-pipeline-runner` with the Jira key.

**On "skip":** proceed to Phase 8, note it in the recap.

**On "not yet":** stop the flow here. Engineer can resume later.

### Phase 8 — Post-deploy (stable) verification

**Do NOT invoke the validator until the engineer confirms the target stable table has been refreshed after the PRD pipeline run.** Pipeline success ≠ table refreshed. Ask:

> "Has the stable target table been refreshed since commit `<SHA>`? The validator checks `max(last_modified_date)` against the commit time and refuses to run otherwise."

Then invoke `data-validator` again with `mode: acceptance-criteria` against the stable table, passing the same acceptance criteria.

### Phase 9 — Close-out

Invoke `jira-commenter` to post both validation results (PRF and stable) to the Jira ticket. The comment should make clear that each acceptance criterion was verified, with the per-criterion verdict.

After the verification comment posts successfully, ask:

> "Close `<TICKET>` now? I'll pull the available transitions and you pick the terminal status (`Done` / `Resolved` / `Closed` / whichever your workflow uses). (yes / skip)"

- **On "yes":** re-invoke `jira-commenter` with the transition request.
- **On "skip":** leave the ticket in its current status and note it in the recap.

## Behavioral rules

**Scope creep** (per `guardrails.md`): if planning or implementation uncovers an unrelated change worth making, note it and stay on the primary ticket. After primary change, ask: "Also found X — open a separate Jira ticket?"

**Acceptance criteria are non-negotiable.** If a criterion is failing at PRF, the change is not done — even if "the rest" passes. Adjust or stop, don't paper over.

**No backwards-compat shims.** This is enhancement work; if removing a column or behavior is part of the plan, do it cleanly. Don't leave dead code "just in case."

**Memory discipline:** this workflow does not persist cross-session memory. Re-read project context at the start.

**Honesty about partial progress:** if any phase fails (SQL access denied, MCP disconnect, plan can't be drafted because the ask is too vague), stop and report.

## Task tracking

Use `TaskCreate` / `TaskUpdate` to surface progress:
1. Intake
2. Scope & change plan (inline review during this phase)
3. Working branch (Phase 3a — cut `feature/<JIRA-KEY>` if on protected branch)
4. Code change (→ Checkpoint 1)
5. Commit / Push / PR
6. PRF pipeline execution (pre-prod)
7. PRF validation (→ Checkpoint 2)
8. PRD pipeline execution (BPP)
9. Post-deploy (stable) verification
10. Close-out (Jira verification comment + optional ticket transition)

Mark in-progress when starting, completed when done. Drop tasks the engineer explicitly skipped.

## Final output

≤7-line recap: ticket (+ final status if transitioned), change SHA, PR URL, PRF execution + validation outcome (which criteria passed/failed), PRD pipeline execution outcome, stable verification outcome, any skips.
