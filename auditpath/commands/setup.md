---
description: One-time setup for AuditPath. Configures ~/.claude/settings.json with required MCP servers and permission rules. Run this once after installing the plugin.
argument-hint: (no arguments needed)
---

Run the AuditPath setup agent to configure this engineer's Claude Code environment for SOX pipeline onboarding.

The setup agent will:
1. Read the engineer's current `~/.claude/settings.json`
2. Add any missing MCP server entries (Databricks, GitHub, Atlassian/JIRA, BPP)
3. Add any missing Bash permission allow-rules needed by AuditPath agents
4. Write the updated settings.json back
5. Report exactly what was added vs. what was already present

The engineer will be prompted to confirm the changes before they are written.
