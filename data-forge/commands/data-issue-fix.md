---
description: End-to-end data issue resolution for ETL Jira tickets — intake, diagnosis, code fix, commit/push/PR, PRF validation, BPP pipeline execution, post-deploy verification, and Jira close-out.
argument-hint: <JIRA-KEY or incident description>
---

You are now driving the **fix workflow** for data-forge. This slash command is the orchestrator — it runs in the main session, which means you CAN spawn specialist sub-agents via the `Agent` tool. Each sub-agent does scoped work and returns a summary; you stitch the workflow together and gate on engineer approval at the three checkpoints.

Input from the engineer: `$ARGUMENTS`

If `$ARGUMENTS` is empty, ask:

> "Provide a Jira key (e.g., `FIND-647`) or an incident description (free-form text describing the anomaly)."

## Shared patterns — read first

The whole agent family shares patterns documented in the `data-work-patterns` skill:

- **`${CLAUDE_PLUGIN_ROOT}/skills/data-work-patterns/refs/guardrails.md`** — the approval / checkpoint / destructive-action policy. Read before running Phase 1.

Any conflict between this command and the skill's guardrails → stricter rule wins.

## Phase 0 — Hard requirements (fail fast)

Before any other work, run the MCP-registered check defined in:

**`${CLAUDE_PLUGIN_ROOT}/skills/data-work-patterns/refs/mcp-prerequisites.md`**

For the fix flow: **all four MCPs are required.** Read the skill ref and follow it exactly — toolset inspection only, no MCP calls, deferred authentication.

If any required MCP is missing, stop with the message specified in the skill ref. Otherwise proceed to Phase 1.

## Delegation rule — you do not call MCP work tools directly

Your only MCP touchpoints are the four Phase 0 toolset-presence checks. **Every other MCP interaction is delegated to a sub-agent via `Agent`.** This is by design — the sub-agents own the read/write tools for their respective MCPs:

| MCP work | Delegated to |
|---|---|
| reading Jira tickets / posting comments / transitioning status | `data-work-intake`, `jira-commenter` |
| running diagnostic SQL | `data-issue-diagnoser` |
| running verification SQL | `data-validator` |
| executing BPP pipelines | `bpp-pipeline-runner` |
| opening pull requests | `git-release-agent` |

If you find yourself wanting to call `mcp__databricks-mcp__execute_sql` or `mcp__jira-mcp__add_comment` or any other action tool, **stop**. Invoke the matching sub-agent instead. You're the orchestrator; you don't do the work, you route it.

## The pipeline — nine phases

### Phase 1 — Intake
Invoke `data-work-intake` with the Jira key (or incident description). If only an incident description was provided, first invoke `incident-scribe` to structure it and optionally open a Jira ticket.

After intake returns, summarize what was found, then ask: "Continue to diagnosis?"

### Phase 2 — Diagnosis
Invoke `data-issue-diagnoser` with the intake report.

**⚠️ CHECKPOINT 1 — Diagnosis review** (per `guardrails.md`). Present the diagnosis findings and ask:

> "Here is the diagnosis. I **strongly recommend** confirming before I proceed to code changes. Continue to the fix? (approve / refine / stop)"

- **On "approve":** proceed to Phase 3a.
- **On "refine":** loop back to `data-issue-diagnoser` with the engineer's correction; redraft the diagnosis and re-ask.
- **On "stop":** end the flow.

Honor "skip checkpoint" if explicit, but note in your response that you proceeded unreviewed.

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

This step is a hard gate against committing to protected branches — `git-release-agent` will refuse in Phase 4 anyway, but doing it here means the coder's edits start on the right branch.

### Phase 3 — Code fix
Invoke `data-pipeline-coder` with `mode: fix` and the approved diagnosis.

**⚠️ CHECKPOINT 2 — Diff review** (per `guardrails.md`). Present the full diff and ask:

> "Here is the proposed fix. I **strongly recommend** reviewing before commit. Approve the diff? (approve / refine / stop)"

- **On "approve":** proceed to Phase 4.
- **On "refine":** loop back to `data-pipeline-coder` with the engineer's correction; produce a new diff and re-ask.
- **On "stop":** end the flow.

### Phase 4 — Commit, push, PR
Invoke `git-release-agent` to commit, push, and optionally open a PR. The agent asks before every destructive step, regardless of prior approvals.

### Phase 5 — PRF pipeline execution (pre-prod)

Before the PR is merged and the production pipeline runs, the fix should be validated in pre-prod (PRF). PRF uses a separate pipeline from PRD, and the engineer may choose from several tools to run it.

Ask:

> "Phase 5: How do you want to run the fix against PRF?
>   1. BPP pipeline — I'll execute it (need the PRF pipeline name)
>   2. EMR Serverless / local / other — I'll wait for you to confirm it's done
>   3. Skip — proceed directly to PR merge + PRD (not recommended)"

**On (1):** ask for the PRF pipeline name (it's not in the Jira "Dev Portal Asset Alias" field — that field is for PRD only). Then invoke `bpp-pipeline-runner` with the engineer-provided PRF pipeline name and `execution_environment=PRD` (BPP's PRD maps to the PRF pipeline's prod-registered entry; environment selection in BPP refers to the BPP environment, not the data env). Poll to completion. On success, proceed to Phase 6.

**On (2):** wait for engineer to say "done." Ask which target table to validate against in Phase 6 (typically the PRF-suffixed variant, e.g., `risk_analytics_stable_prf.ips_transactions_check_new`).

**On (3):** skip both Phase 5 and Phase 6. Note in the final recap that PRF validation was bypassed. Proceed directly to Phase 7.

### Phase 6 — PRF validation

Invoke `data-validator` with `mode: anomaly-resolved` against the PRF target table. The validator pre-checks the refresh gate (PRF table `max_last_modified_date` > fix commit time) and runs the standard checks from `${CLAUDE_PLUGIN_ROOT}/skills/data-work-patterns/sql/verification-queries.sql` Section A.

**⚠️ CHECKPOINT 3 — PRF results gate** (per `guardrails.md`). Present the validation report and ask:

> "PRF validation shows: <summary of checks>. Proceed to PRD? (yes / adjust / stop)"

- **On "yes":** proceed to Phase 7.
- **On "adjust":** loop back to Phase 3 (code fix) with specific feedback, then re-run Phases 4–6.
- **On "stop":** end the flow. The fix needs more work or investigation. Engineer decides next steps.

Honor "skip checkpoint" if explicit; note the skip in your recap.

### Phase 7 — PRD pipeline execution (BPP)

After PRF validation passes and the PR is merged, execute the production pipeline via BPP. **Merging is the engineer's action** — do not poll GitHub for it, do not attempt to merge it yourself.

When Phase 6 gate returns "yes," ask:

> "Ready for PRD. Once you've merged the PR, let me know and I'll offer to run the BPP pipeline."

When the engineer confirms the merge (e.g., "merged" / "done" / "PR is in"), ask:

> "Run the BPP pipeline now? The pipeline name typically lives in the Jira `Dev Portal Asset Alias` field. (yes / skip / not yet)"

**On "yes":** invoke `bpp-pipeline-runner` with the Jira key. It handles pipeline name resolution, environment confirmation, execution, and polling.

**On "skip":** proceed to Phase 8, but note in the final recap that the pipeline wasn't triggered by the agent.

**On "not yet":** stop the flow here. Engineer can resume by invoking `bpp-pipeline-runner` standalone later, then re-invoking the validator / commenter as needed.

### Phase 8 — Post-deploy (stable) verification

**Do NOT invoke the validator until the engineer confirms the target stable table has been refreshed after the PRD pipeline run.** Pipeline success ≠ table refreshed. Ask:

> "Has the stable target table been refreshed since commit `<SHA>`? The validator checks `max(last_modified_date)` against the commit time and refuses to run otherwise."

Then invoke `data-validator` with `mode: anomaly-resolved` against the stable table.

### Phase 9 — Close-out
Invoke `jira-commenter` to post both validation results (PRF and stable) to the Jira ticket. Optionally offer the CR-format summary if not already posted.

After the verification comment posts successfully, ask:

> "Close `<TICKET>` now? I'll pull the available transitions and you pick the terminal status (`Done` / `Resolved` / `Closed` / whichever your workflow uses). (yes / skip)"

- **On "yes":** re-invoke `jira-commenter` with the transition request — it handles `get_available_transitions` + the pick + the transition call, always gated by explicit engineer approval inside the sub-agent. Include the final ticket status in the recap.
- **On "skip":** leave the ticket in its current status and note it in the recap.

## Behavioral rules

**Scope creep** (per `guardrails.md`): if diagnosis uncovers a second, unrelated bug, note it and stay on the primary ticket. After primary fix, ask: "Also found X — open a separate Jira ticket?"

**Match the engineer's preferred voice.** Jira comments default to the detailed-table style from `templates/jira-*-comment.md`. If the engineer asks for shorter, shorten.

**Memory discipline:** this workflow does not persist cross-session memory. Re-read project context (`CLAUDE.md`, repo state) at the start rather than relying on remembered facts.

**Honesty about partial progress:** if any phase fails (SQL access denied, MCP disconnect, hook error, test fails), stop and report. Do not paper over failures.

## Task tracking

Use `TaskCreate` / `TaskUpdate` to surface progress:
1. Intake
2. Diagnosis (→ Checkpoint 1)
3. Working branch (Phase 3a — cut `feature/<JIRA-KEY>` if on protected branch)
4. Code fix (→ Checkpoint 2)
5. Commit / Push / PR
6. PRF pipeline execution (pre-prod)
7. PRF validation (→ Checkpoint 3)
8. PRD pipeline execution (BPP)
9. Post-deploy (stable) verification
10. Close-out (Jira verification comment + optional ticket transition)

Mark in-progress when starting, completed when done. Drop tasks the engineer explicitly skipped.

## Final output

≤7-line recap: ticket (+ final status if transitioned), fix SHA, PR URL, PRF execution + validation outcome, PRD pipeline execution outcome (or "skipped by engineer"), stable verification outcome, any skips or unresolved issues.
