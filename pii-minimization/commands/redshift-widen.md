---
description: Run Redshift column widening for a batch — the mandatory gate before Phase 2 encrypt-on-write. Resolves the batch and schemas from a Jira story, dispatches to Rex (redshift-dba agent), and runs audit → DDL generation → staging dry-run → production ALTER → validation.
argument-hint: "<JIRA-KEY> [batch=<A|B|C|D|E|SPP>] [schema=<schema>]"
---

You are now driving the **Redshift column widening workflow** for the pii-minimization plugin. This command dispatches to Rex (redshift-dba agent) — the hard gate before Phase 2 for any batch.

Input from the engineer: `$ARGUMENTS`

If `$ARGUMENTS` is empty, ask:
> "Provide a Jira story key for the Redshift widening story (e.g. `FIND-699`). Optionally add `batch=<A|B|C|D|E|SPP>` or `schema=<name>` if needed."

---

## Shared references — read first

- **`${CLAUDE_PLUGIN_ROOT}/skills/pii-minimization-ref/refs/guardrails.md`** — approval policy and destructive-action gates.

Production ALTER TABLE statements are irreversible — Rex must complete a staging dry-run before any production ALTERs. If the engineer tries to skip the staging step, block and explain why.

---

## Phase 0 — MCP prerequisite check

Verify these MCPs are connected:

| MCP | Required for |
|-----|-------------|
| `mcp__jira-mcp` | Fetch story, post comments, transition status |
| `mcp__DAST-Orch__execute_sql` | Run Redshift audit + ALTER queries |

---

## Phase 1 — Resolve batch and schemas from Jira

Invoke `pii-minimization:intake`:
```
Agent(pii-minimization:intake, "Jira story: <JIRA-KEY>. Mode: redshift-widen. Extract: batch label, schema list, enc window dates, widening deadline.")
```

Batch → Schema → Deadline reference:

| Batch | Schemas | Phase 2 Enc Window | Widening Deadline |
|-------|---------|-------------------|------------------|
| SPP | risk_enrichment_src | May 18–22 2026 | May 11 2026 |
| A | risk_history_stable, risk_mtlmart_dm, risk_zoot_stable | Jun 8–12 2026 | Jun 1 2026 |
| B | risk_analytics_stable | Jun 15–18 2026 | Jun 8 2026 |
| C | risk_iboss_stable | Jun 22–26 2026 | Jun 15 2026 |
| D | risk_lax_stable, risk_apps_stable, risk_reporting_rpt, risk_collections_rpt, risk_wallet_src, risk_posneg_stable, finance_mm_dm | Jun 29–Jul 2 2026 | Jun 22 2026 |
| E | risk_quickbase_src | Jul 6–10 2026 | Jun 29 2026 |

If today is past the widening deadline, warn:
> "WARNING: Widening deadline for Batch <batch> was <date>. Today is <today>. Widening is overdue — proceed immediately or escalate."

---

## Phase 2 — Dispatch to Rex

```
Agent(pii-minimization:redshift-dba, "<full intake report + batch + schema list + jira_story>")
```

Rex runs all steps:
1. Audit current VARCHAR lengths
2. Generate ALTER TABLE DDL (`max(current_length * 2, current_length + 100)`)
3. Staging dry-run (ALTER + COPY validation)
4. Production ALTER in maintenance window
5. Post-ALTER validation (0 under-width columns)
6. Encrypted COPY validation (0 STL_LOAD_ERRORS)
7. Update Jira → Done

---

## Gate output

On completion:
```
Batch <batch> — Redshift Column Widening: COMPLETE
  Jira <JIRA-KEY> → Done
  Phase 2 for Batch <batch> is now UNBLOCKED.
```
