# MCP prerequisites — Phase 0 fail-fast

This file is the single source of truth for the MCP-registered check that every data-forge workflow command runs as Phase 0. If you're a workflow command (`/data-forge:data-issue-fix`, `/data-forge:data-enhancement`, or `/data-forge:data-creator`), follow this exactly.

## Required MCPs

The plugin requires four MCPs registered at the user level:

| MCP | Used in | Authentication |
|---|---|---|
| `jira-mcp` | reading tickets, posting comments, transitioning status | deferred — first call from `data-work-intake` or `jira-commenter` triggers auth if needed |
| `databricks-mcp` | running diagnostic and verification SQL | deferred — first call from `data-issue-diagnoser` or `data-validator` triggers auth if needed |
| `DAST-Orch` | executing BPP pipelines (PRF and PRD) | deferred — first call from `bpp-pipeline-runner` triggers auth if needed |
| `intuit-github-mcp` | opening pull requests | deferred — first call from `git-release-agent` triggers auth if needed |

## Workflow-specific carve-outs

- **fix flow** (`/data-forge:data-issue-fix` command): all four required.
- **enhancement flow** (`/data-forge:data-enhancement` command): all four required.
- **create flow** (`/data-forge:data-creator` command): only the *Jira* MCP is conditional — required when a Jira key was provided, skipped when input is a freeform spec. The other three are required regardless.

## Procedure — toolset inspection only, NO MCP calls

The four eagerly-loaded probe tools are:

- `mcp__jira-mcp__get_jira_user_info`
- `mcp__databricks-mcp__get_user_info`
- `mcp__DAST-Orch__get_jira_user_info`
- `mcp__intuit-github-mcp__search_users`

For each applicable MCP (per workflow above), check whether its probe tool is **present in your toolset**. **Do not invoke the probe** — invoking it would trigger authentication, which is exactly what this Phase 0 design avoids. Just check for presence.

If a probe tool is in your toolset, the corresponding MCP server is registered. If not, it's missing.

## On any missing MCP server

Stop immediately with the message:

> "Missing MCP: `<name>`. The data-forge plugin requires `<name>` to be registered for this workflow. Add `<name>` to your MCP config and restart Claude Code."

Do not proceed past Phase 0. Do not degrade gracefully. Do not skip the missing capability — a missing MCP means the workflow will be incomplete and unreliable.

## Authentication is deferred

This Phase 0 check verifies the MCPs are *registered* — it does not call them, and so does not trigger any auth flow. Each MCP is authenticated on first actual use by the matching sub-agent during the workflow. The user may be prompted to authenticate `databricks-mcp` when Phase 2 (or 6/8) starts, `intuit-github-mcp` when Phase 4 starts, etc.

This is intentional: don't ask the user to log into four services up front when the workflow may use only some of them, and never make them re-auth at the start of every run.

## Don't re-check during the run

If all required probes were registered at Phase 0, treat them as available for the rest of the session. Sub-agent calls handle their own auth lazily.
