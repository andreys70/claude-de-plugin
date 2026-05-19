---
name: phase2-preflight
description: Mandatory pre-flight checklist that must pass before any Phase 2 encrypt-on-write deploy. All four checks must be green — any failure is a hard BLOCKER.
---

# Phase 2 Pre-flight Checklist

All four checks must pass before dispatching Phase 2. Any failure = BLOCKER. Do not proceed.

## Check 1 — Phase 1 stable in production

- Find the Phase 1 Jira story referenced in the Phase 2 story description.
- Fetch it via Jira MCP and confirm status = `Done`.
- If not Done:
  ```
  BLOCKER: Phase 1 story <key> is not Done (status: <status>).
  Phase 1 must be deployed and stable in production before Phase 2 can begin.
  Run /pii-minimization:phase1 <Phase1-JIRA-KEY> first.
  ```

## Check 2 — Report Requestor decrypt deployed

- Find the Report Requestor Jira story referenced in the description (e.g. FIND-762 or equivalent).
- Fetch it via Jira MCP and confirm status = `Done`.
- If not Done:
  ```
  BLOCKER: Report Requestor decrypt story <key> is not Done.
  All downstream consumers must have decrypt logic deployed before Phase 2 goes live.
  ```

## Check 3 — IAM role has kms:GenerateDataKey + kms:Decrypt

- Check the Jira description checklist for a confirmation of IAM permissions.
- If not confirmed, ask the engineer:
  > "Please confirm the IAM role for this pipeline has both `kms:Decrypt` AND `kms:GenerateDataKey` in the IDPS policy."
- Do not proceed until confirmed.

## Check 4 — Redshift column widening COMPLETE

- Find the Redshift widening Jira story referenced in the description (e.g. FIND-699 or FIND-769).
- Fetch it via Jira MCP and confirm status = `Done`.
- If not Done:
  ```
  BLOCKER: Redshift column widening story <key> is not Done.
  VARCHAR columns must be widened before ciphertext COPY loads — or truncation errors will occur.
  Run /pii-minimization:redshift-widen <widening-JIRA-KEY> first.
  ```

## Pre-flight output

On all checks passing:
```
Pre-flight: PASS ✓
  Phase 1 stable in prod      : ✓  (<key> Done)
  Report Requestor deployed   : ✓  (<key> Done)
  IAM kms:GenerateDataKey     : ✓  (confirmed)
  Redshift widening complete  : ✓  (<key> Done — Phase 2 UNBLOCKED)
Proceeding to Phase 2 dispatch.
```
