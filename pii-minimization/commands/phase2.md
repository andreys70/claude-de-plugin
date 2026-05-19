---
description: Apply Phase 2 encrypt-on-write to a pipeline schema. Resolves the schema and framework from a Jira story, runs pre-flight checks (Phase 1 stable, Redshift widening complete, IAM updated, downstream decrypt live), dispatches to the correct specialist agent, and runs end-to-end through PR, PRF validation, PRD deploy, and Jira close-out.
argument-hint: "<JIRA-KEY> [schema=<schema>] [table=<table>]"
---

You are now driving the **Phase 2 (encrypt-on-write) workflow** for the pii-minimization plugin. This command is the orchestrator — it runs in the main session and dispatches to specialist sub-agents via the `Agent` tool.

Input from the engineer: `$ARGUMENTS`

If `$ARGUMENTS` is empty, ask:
> "Provide a Jira story key for Phase 2 (e.g. `FIND-719`). Optionally add `schema=<name>` or `table=<name>` if the story is ambiguous."

---

## Shared references — read first

Before doing anything else, read:
- **`${CLAUDE_PLUGIN_ROOT}/skills/pii-minimization-ref/refs/guardrails.md`** — approval policy, checkpoint rules, destructive-action gates.
- **`${CLAUDE_PLUGIN_ROOT}/skills/pii-minimization-ref/refs/framework-dispatch.md`** — schema registry lookup, agent dispatch table, and Google Sheet tab references.
- **`${CLAUDE_PLUGIN_ROOT}/registry/schema-job-type.yaml`** — bundled schema registry (pipeline type, GitHub repo, batch per schema).
- **`${CLAUDE_PLUGIN_ROOT}/skills/pii-minimization-ref/refs/phase2-preflight.md`** — the mandatory pre-flight checklist before any Phase 2 deploy.

---

## Phase 0 — MCP prerequisite check

Verify these MCPs are connected before any other work:

| MCP | Required for |
|-----|-------------|
| `mcp__jira-mcp` | Fetch story, post comments, transition status |
| `mcp__DAST-Orch` | Execute BPP pipelines (PRF + PRD) |
| `mcp__intuit-github-mcp` (or DAST-Orch GitHub tools) | Commit, push, open PR |

If any are missing, stop:
> "Missing MCP: `<name>`. Please connect it and retry."

---

## Phase 1 — Resolve schema and pipeline from Jira

Invoke the `pii-minimization:intake` sub-agent:
```
Agent(pii-minimization:intake, "Jira story: <JIRA-KEY>. Mode: phase2. Extract: schema names, pipeline/framework hint, table list, batch label, enc window dates, prerequisite story references.")
```

From the intake report:
1. Identify the pipeline framework using the dispatch table in `framework-dispatch.md`.
2. If the story says "Phase 1" — redirect: "This looks like a Phase 1 story. Run `/pii-minimization:phase1 $ARGUMENTS` instead."
3. If `pipeline == report_requestor` — redirect: "Report Requestor is Phase 1 only. Run `/pii-minimization:phase1 $ARGUMENTS` instead."
4. If multiple schemas — ask: "This story covers N schemas. Run Phase 2 for all, or a specific one? (all / <schema>)"

---

## Phase 2 — Pre-flight checks

Read `${CLAUDE_PLUGIN_ROOT}/skills/pii-minimization-ref/refs/phase2-preflight.md` and verify ALL checks before dispatching.

Pre-flight checks (for rda_bpp, quicketl, quickbase):
1. **Phase 1 stable in prod** — Phase 1 Jira story referenced in description must be `Done`.
2. **Report Requestor decrypt deployed** — RR Jira story must be `Done`.
3. **IAM role has `kms:GenerateDataKey` + `kms:Decrypt`** — confirm from Jira checklist or ask.
4. **Redshift column widening COMPLETE** — widening Jira story must be `Done` AND Rex must have confirmed `COMPLETE — Phase 2 UNBLOCKED`. If not done, run `/pii-minimization:redshift-widen` first.

If any pre-flight check fails:
```
BLOCKER — Phase 2 cannot proceed:
  <check that failed>
  Action required: <what to do>
```
Do NOT dispatch Phase 2 until all checks pass.

---

## Phase 3 — Dispatch to specialist agent

| Pipeline | Agent | Notes |
|----------|-------|-------|
| `rda_bpp` | `pii-minimization:rda-bpp-engineer` | Phase 2 encrypt-on-write for PySpark/EMR |
| `quicketl` | `pii-minimization:quicketl-engineer` | Phase 2 encrypt-on-write for HOCON .conf |
| `quickbase` | `pii-minimization:quickbase-engineer` | Phase 2 = PRD promotion of PRF-validated job |
| `spp` | `pii-minimization:spp-engineer` | SPP single-phase: encrypt + immediate backfill |

---

## Phase 4 — Gate and close-out

After the specialist agent completes:
1. Confirm: PR merged, PRD validation passed (0 plaintext rows), Jira → Done.
2. Surface any BLOCKER immediately.
3. Output final status:

```
Phase 2: <schema>[.<table>]
  Framework  : <pipeline>
  Agent      : <agent_name>
  Jira       : <JIRA-KEY> → Done
  PR         : <url>
  Validation : PASS — 0 plaintext rows confirmed
Status: COMPLETE
```
