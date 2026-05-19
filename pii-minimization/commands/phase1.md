---
description: Apply Phase 1 decrypt-on-read to a pipeline schema. Resolves the schema and framework from a Jira story, dispatches to the correct specialist agent (Alex/Quinn/Rio/Quin), and runs end-to-end through PR, PRF validation, PRD deploy, and Jira close-out.
argument-hint: "<JIRA-KEY> [schema=<schema>] [table=<table>]"
---

You are now driving the **Phase 1 (decrypt-on-read) workflow** for the pii-minimization plugin. This command is the orchestrator — it runs in the main session and dispatches to specialist sub-agents via the `Agent` tool.

Input from the engineer: `$ARGUMENTS`

If `$ARGUMENTS` is empty, ask:
> "Provide a Jira story key for Phase 1 (e.g. `FIND-773`). Optionally add `schema=<name>` or `table=<name>` if the story is ambiguous."

---

## Shared references — read first

Before doing anything else, read:
- **`${CLAUDE_PLUGIN_ROOT}/skills/pii-minimization-ref/refs/guardrails.md`** — approval policy, checkpoint rules, and destructive-action gates.
- **`${CLAUDE_PLUGIN_ROOT}/skills/pii-minimization-ref/refs/framework-dispatch.md`** — schema registry lookup, agent dispatch table, and Google Sheet tab references.
- **`${CLAUDE_PLUGIN_ROOT}/registry/schema-job-type.yaml`** — bundled schema registry (pipeline type, GitHub repo, batch per schema).

Any conflict between this command and those refs → stricter rule wins.

---

## Phase 0 — MCP prerequisite check

Before any other work, verify these MCPs are connected:

| MCP | Required for |
|-----|-------------|
| `mcp__jira-mcp` | Fetch story, post comments, transition status |
| `mcp__DAST-Orch` | Execute BPP pipelines (PRF + PRD) |
| `mcp__intuit-github-mcp` (or DAST-Orch GitHub tools) | Commit, push, open PR |

Check for each by calling `ToolSearch` with the MCP name. If any are missing, stop:
> "Missing MCP: `<name>`. Please connect it and retry."

---

## Phase 1 — Resolve schema and pipeline from Jira

Invoke the `pii-minimization:intake` sub-agent:
```
Agent(pii-minimization:intake, "Jira story: <JIRA-KEY>. Mode: phase1. Extract: schema names, pipeline/framework hint, table list, batch label, assignee.")
```

From the intake report:
1. Identify the pipeline framework using the dispatch table in `framework-dispatch.md`.
2. If the story covers multiple schemas — ask the engineer: "This story covers N schemas. Run Phase 1 for all, or a specific one? (all / <schema>)"
3. If `pipeline == spp` — redirect:
   > "SPP is single-phase encrypt-only. Run `/pii-minimization:phase2 $ARGUMENTS` instead."
4. If `pipeline == report_requestor` — note that Rio handles both phases from Phase 1 entry point.

---

## Phase 2 — Dispatch to specialist agent

Based on the resolved pipeline, dispatch to the correct agent. Pass the full intake report and resolved parameters.

| Pipeline | Agent | Invocation |
|----------|-------|-----------|
| `rda_bpp` | `pii-minimization:rda-bpp-engineer` | Phase 1 decrypt-on-read for PySpark/EMR jobs |
| `quicketl` | `pii-minimization:quicketl-engineer` | Phase 1 decrypt-on-read for HOCON .conf jobs |
| `quickbase` | `pii-minimization:quickbase-engineer` | Phase 1 = create new QuickETL encrypt jobs to PRF |
| `report_requestor` | `pii-minimization:report-requestor-engineer` | Phase 1 inject odin_decrypt() in Python report scripts |

Each agent runs its full Phase 1 lifecycle end-to-end and reports per-step status back to you.

---

## Phase 3 — Gate and close-out

After the specialist agent completes:
1. Confirm the agent reported: PR merged, PRD validation passed (0 unexpected rows), Jira transitioned to Done.
2. If any step is BLOCKED — surface the blocker to the engineer immediately.
3. Output final status:

```
Phase 1: <schema>[.<table>]
  Framework  : <pipeline>
  Agent      : <agent_name>
  Jira       : <JIRA-KEY> → Done
  PR         : <url>
  Validation : PASS
Status: COMPLETE
```
