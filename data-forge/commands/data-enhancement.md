---
description: End-to-end implementation of an enhancement (or optimization, or any non-bug change) against an existing ETL pipeline — intake, change plan, code change, commit/push/PR, PRF validation, PRD execution, post-deploy verification.
argument-hint: <JIRA-KEY>
---

Invoke the `data-enhancement-driver` orchestrator with the following input:

$ARGUMENTS

Follow the full pipeline defined in the orchestrator:

1. Verify required MCPs (data warehouse MCP, `jira-mcp`, `DAST-Orch`, `intuit-github-mcp`) are connected. Fail fast if any are missing.
2. Run the nine phases: Intake → Scope & change plan (inline review) → Code change → Commit/Push/PR → PRF pipeline execution → PRF validation → PRD pipeline execution (BPP) → Post-deploy (stable) verification → Close-out.
3. Gate on engineer approval at two checkpoints (pre-commit, post-PRF validation). The change plan in Phase 2 is reviewed inline; it is not a separate post-plan checkpoint.
4. PRD pipeline execution is engineer-triggered after PR merge; never polled or auto-merged.
5. Hard-require table refresh before running each validation phase (PRF and stable). Validator runs in `acceptance-criteria` mode.

If `$ARGUMENTS` is empty, ask the engineer for a Jira key before starting. Enhancements should always have a ticket; if the engineer doesn't have one, redirect to `incident-scribe` (to open one) or `/data-creator` (if it's actually a net-new pipeline).
