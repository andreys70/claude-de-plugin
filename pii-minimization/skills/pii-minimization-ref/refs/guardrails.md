---
name: guardrails
description: Approval policy, checkpoint rules, and destructive-action gates for the pii-minimization plugin.
---

# PII Minimization — Guardrails

## Approval checkpoints

Every Phase 1 and Phase 2 workflow has exactly two mandatory engineer checkpoints:

**Checkpoint 1 — pre-commit (change plan review):**
Before any code is written or any file is modified, the agent presents the full change plan to the engineer:
> "Here is the proposed change plan. Review before I start? (approve / refine / stop)"
- **approve** → proceed to code change
- **refine** → revise and re-present
- **stop** → end the workflow

**Checkpoint 2 — post-PRF validation:**
After the PRF pipeline runs, the agent presents Athena/SQL validation results before PRD deploy:
> "PRF validation results below. Approve PRD deploy? (approve / stop)"
- **approve** → proceed to PRD deploy
- **stop** → end — do not deploy to PRD

Never skip checkpoints. Never proceed to PRD without Checkpoint 2 approval.

## Destructive action gates

The following actions require explicit engineer confirmation before executing — even if the workflow has been running for a while:

- Merging a PR to master
- Executing a PRD pipeline
- Running production Redshift ALTERs
- Transitioning a Jira story to Done

Show the action + consequences, ask "Confirm? (yes/no)", and wait for response.

## Phase rules

| Rule | Detail |
|------|--------|
| Phase 1 ≠ encrypt | Phase 1 = decrypt-on-read only. Data stays plaintext in the output table. |
| Phase 2 separate PR | Always a separate branch and PR from Phase 1. Never combined. |
| Phase 1 before Phase 2 | Phase 1 must be in production before Phase 2 can begin. |
| SPP is single-phase | SPP reads from Kafka, not encrypted Data Lake. Skip Phase 1. |
| Report Requestor is Phase 1 only | RR scripts only decrypt. They never write encrypted data. |
| Redshift widening is a hard gate | Phase 2 is BLOCKED until Rex confirms 0 under-width columns. |
| Jira Done only after 0 plaintext | Phase 2 story is not marked Done until PRD spot-check passes. |
| One PR per table | Never batch multiple tables into one PR. |
| Partition row count > 0 | 0 rows after PRF or PRD deploy is a hard BLOCKER. |
| Surgical edits only | Only SENSITIVE column lines change. Every other line must be byte-for-byte identical. |
