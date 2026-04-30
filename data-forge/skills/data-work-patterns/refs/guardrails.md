# Guardrails — approval policy, checkpoints, destructive actions

These rules apply across the whole `data-issue-*` agent family. If an agent's local prompt appears to conflict with these rules, the stricter rule wins.

## Approval policy by action type

| Action | Ask first? | Rationale |
| --- | --- | --- |
| Read queries (SELECT, DESCRIBE, SHOW) | No | Read-only, fast to verify |
| File edits on disk (Edit, Write) | No | Reversible via `git restore` |
| Jira comment creation | **Always** | Comments are visible to the team; once posted, hard to retract gracefully |
| Jira ticket creation | **Always** | Creates work-tracking noise for others |
| Jira status transition | **Always** | Affects team dashboards, SLA tracking |
| Git commit | **Always** | Even local commits can confuse the engineer if unexpected |
| Git push | **Always** | Makes changes visible on the remote; triggers CI |
| Git force-push | **Always, with extra caution** | Overwrites history, can destroy others' work |
| Pull request creation | **Always** | Triggers review notifications, CI pipelines |
| BPP pipeline execution | **Always** | Can cost money, affects shared data, can disrupt downstream consumers; never silently default to PRD |
| Databricks schema change / TRUNCATE / DROP | **Always, high-alert** | Destructive and often hard to reverse |
| Destructive git commands (`reset --hard`, `clean -f`, `checkout .`) | **Always, high-alert, explain alternative first** | Can destroy uncommitted work |

## The three orchestrator checkpoints

When the `/data-forge:data-issue-fix` command orchestrator is driving a full-cycle investigation, it pauses at three points regardless of prior approvals:

### Checkpoint 1 — Post-diagnosis
Before code changes begin. The orchestrator presents the diagnosis (root cause, evidence, proposed fix approach, risks) and asks:

> "Here is the diagnosis. I **strongly recommend** confirming before I proceed to code changes. Continue to the fix? (yes / refine / stop)"

### Checkpoint 2 — Pre-commit
Before any git action. The orchestrator presents the full diff (from `data-pipeline-coder`) and asks:

> "Here is the proposed fix. I **strongly recommend** reviewing before commit. Approve the diff? (yes / refine / stop)"

### Checkpoint 3 — Post-PRF validation
Before promoting the fix to production. After PRF validation completes, the orchestrator presents the PRF validation report and asks:

> "PRF validation shows: <summary>. Proceed to PRD? (yes / stop / adjust)"

On "adjust," loops back to Phase 3 (code fix) with the specific PRF validation concerns. On "stop," ends the flow — the fix needs more work.

### Skip behavior

The engineer may say "skip checkpoint" or equivalent. The orchestrator honors this but notes in its response:

> "Proceeded without review per your instruction."

This keeps the audit trail intact even when the engineer is moving fast.

## BPP pipeline execution rules

- **Never execute without explicit engineer approval.** The `bpp-pipeline-runner` asks before calling `execute_pipeline`.
- **Never silently default to PRD.** PRD is the sensible default when code was just merged, but the agent always names the environment in the approval prompt ("Execute in PRD? yes / E2E / cancel").
- **Never poll GitHub to auto-detect merge and auto-trigger the pipeline.** Merging is the engineer's action. The orchestrator asks for merge confirmation and only then offers the pipeline step.
- **Never retry automatically on failure.** If `execute_pipeline` or polling returns an error, surface it to the engineer and ask how to proceed.
- **Never execute an archived or suspended pipeline.** `bpp-pipeline-runner` verifies the pipeline is live before execution.
- **Pipeline success ≠ table refreshed.** After a successful pipeline run, the orchestrator still gates the validator on the refresh check.

## Verification refresh gate

`data-validator` refuses to run verification queries against a target table that hasn't been refreshed since the fix commit. This is non-negotiable: a stale table with pre-fix NULL% would be misread as "fix failed" — actively harmful.

The check:

```sql
SELECT MAX(last_modified_date) AS max_ts FROM <target_table>;
```

Compared against the commit time of the fix SHA. If `max_ts < commit_time`, the validator stops and tells the engineer to rerun after the next refresh.

## Scope creep policy

If a diagnosis uncovers a second, unrelated bug:

1. **Note it** in the diagnosis output, clearly marked as "not in scope of this ticket."
2. **Stay on the primary ticket.** Do not expand the fix to cover both.
3. **After primary fix is done**, ask the engineer: "Also found <X>. Open a separate Jira ticket? (yes / no / later)"

This preserves reviewability of the primary fix and honors the engineer's ability to triage.

## Honesty rules

- **Partial progress:** if any phase fails (SQL access denied, MCP disconnect, test failure, hook failure), stop and report. Do not paper over to keep the pipeline moving.
- **Uncertainty:** if a candidate can't be ruled out due to missing access or data, say "inconclusive — requires X." Don't promote "not disproven" to "confirmed."
- **Validation outcomes:** if verification shows the fix didn't fully work, say so. Don't soften "fix did not take effect" to "fix has mixed results."
- **Proceeded-without-review:** always surface this in final output so the engineer has a clean audit trail.

## Non-negotiables

- Never modify `git config`
- Never commit with `--no-verify` or `--no-gpg-sign` unless explicitly requested
- Never force-push to protected branches (`main`, `master`, `develop`) without explicit high-friction confirmation
- Never delete files, branches, or database objects to "clean up" without explicit authorization
- Never include credentials, tokens, or secrets in Jira comments, PR descriptions, or commit messages
