# sox-pipeline-ref

Shared reference hub for the AuditPath plugin. All agents load references from this skill rather than hardcoding domain-specific knowledge.

## Contents

| File | Purpose |
|------|---------|
| `refs/dm-patterns.md` | Write modes, HOCON skeleton, class names, variable patterns |
| `refs/sox-dq-patterns.md` | Full 16-step SOX DQ pattern with all SQL templates and gotchas |
| `refs/guardrails.md` | Approval policy, non-negotiables, gating rules |
| `refs/validation-queries.md` | Parameterized completeness + accuracy + late-arriving SQL |
| `templates/sox-setup-insert.sql` | RPT_SOX_SETUP + RPT_SOX_METADATA INSERT template |
| `templates/jira-comment-format.md` | Structured progress + results comment format |

## Usage

Agents reference files via `${CLAUDE_PLUGIN_ROOT}/skills/sox-pipeline-ref/refs/<file>` and `${CLAUDE_PLUGIN_ROOT}/skills/sox-pipeline-ref/templates/<file>`.
