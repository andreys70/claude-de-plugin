---
description: End-to-end creation of a net-new ETL pipeline (config, code, or both) — intake (Jira or freeform spec), scaffold plan, scaffold code, commit/push/PR, PRF dry-run, PRD execution, post-deploy verification.
argument-hint: <JIRA-KEY or freeform spec>
---

Invoke the `data-creator-driver` orchestrator with the following input:

$ARGUMENTS

Follow the full pipeline defined in the orchestrator:

1. Verify required MCPs (data warehouse MCP, `DAST-Orch`, `intuit-github-mcp`; plus `jira-mcp` only if a Jira key was provided) are connected. Fail fast if any required one is missing.
2. Run the nine phases: Intake (Jira or freeform spec) → Scope & scaffold plan (inline review, includes finding the sibling pipeline) → Scaffold → Commit/Push/PR → PRF pipeline execution (dry-run, may iterate) → PRF validation → PRD pipeline execution (BPP) → Post-deploy (stable) verification → Close-out (skipped if no Jira).
3. Gate on engineer approval at two checkpoints (pre-commit, post-PRF validation). The scaffold plan in Phase 2 is reviewed inline.
4. PRF iteration is allowed and expected for net-new pipelines — no hard limit; engineer says stop when they want to stop.
5. Hard-require table refresh before running each validation phase. Validator runs in `first-run-healthy` mode (table exists, schema matches spec, non-zero rows, required columns populated, no duplicates, row-count order of magnitude).

If `$ARGUMENTS` is empty, ask: "Do you have a Jira ticket for this, or should I work from a spec you'll paste? (Jira preferred — has more context — but a paste works for early-stage requests.)"
