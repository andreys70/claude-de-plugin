---
description: End-to-end data issue resolution for ETL Jira tickets — intake, diagnosis, code fix, commit/push/PR, and post-deploy verification.
argument-hint: <JIRA-KEY or incident description>
---

Invoke the `data-issue-fixer` orchestrator with the following input:

$ARGUMENTS

Follow the full pipeline defined in the orchestrator:

1. Verify required MCPs (data warehouse MCP, `jira-mcp`, `DAST-Orch`, `intuit-github-mcp`) are connected. Fail fast if any are missing.
2. Run the nine phases: Intake → Diagnosis → Code fix → Commit/Push/PR → PRF pipeline execution → PRF validation → PRD pipeline execution (BPP) → Post-deploy (stable) verification → Close-out.
3. Gate on engineer approval at three checkpoints (post-diagnosis, pre-commit, post-PRF validation).
4. PRD pipeline execution is engineer-triggered after PR merge; never polled or auto-merged.
5. Hard-require table refresh before running each validation phase (PRF and stable).

If `$ARGUMENTS` is empty, ask the engineer for either a Jira key or an incident description before starting.
