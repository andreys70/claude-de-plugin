---
name: data-issue-patterns
description: Shared reference for the data-issue-fixer agent family — diagnostic methods (rule-out, bridge-finding, control groups), Jira comment templates (investigation, verification, CR format), and reusable SQL skeletons for verification. The data-issue-fixer, data-issue-diagnoser, data-issue-validator, and jira-commenter agents all delegate here for shared patterns.
---

# Data Issue Patterns — shared reference

This skill is the single source of truth for patterns used across the `data-issue-*` agent family. If you are one of those agents, read the relevant section here rather than duplicating the pattern in your own prompt.

## Layout

```
data-issue-patterns/
├── SKILL.md                              ← this file (diagnostic method, index)
├── templates/
│   ├── jira-investigation-comment.md     ← for mid-investigation Jira posts
│   ├── jira-verification-comment.md      ← for post-deploy Jira posts
│   ├── jira-cr-format.md                 ← Change Request format (pre-deploy)
│   ├── intake-report.md                  ← output format for data-issue-intake
│   ├── diagnosis-report.md               ← output format for data-issue-diagnoser
│   └── validation-report.md              ← output format for data-issue-validator
├── sql/
│   └── verification-queries.sql          ← parameterized skeletons for the 5 standard checks
└── refs/
    ├── diagnostic-method.md              ← the rule-out pattern, expanded
    ├── worked-examples.md                ← FIND-599 examples (mt_txn_id bridge, control group, red herring)
    └── guardrails.md                     ← approval rules, checkpoint policy, destructive-action list
```

## When agents should consult this skill

- **`data-issue-diagnoser`** → `refs/diagnostic-method.md` (the rule-out pattern) + `refs/worked-examples.md` (when stuck, match the current problem against known patterns) + `templates/diagnosis-report.md` (output format).
- **`data-issue-intake`** → `templates/intake-report.md` (output format).
- **`data-issue-validator`** → `sql/verification-queries.sql` (the 5 standard checks) + `templates/validation-report.md` (output format).
- **`jira-commenter`** → `templates/jira-*-comment.md` (rendering). Always check the engineer's personal CR memory first (`~/.claude/projects/*/memory/feedback_cr_format.md`) — if present, it supersedes `templates/jira-cr-format.md`.
- **`data-issue-fixer` (orchestrator)** → `refs/guardrails.md` (checkpoint and approval rules).

## The diagnostic method — quick reference

The full method is in `refs/diagnostic-method.md`. At a glance:

1. **Reproduce the anomaly** with SQL. Actual numbers, not "significant drop."
2. **List 3–6 candidate root causes.** Include the un-sexy ones (ETL regression, filter drift, dead code path).
3. **Rule out each candidate** with a specific query or file inspection. Present the output.
4. **Watch for red herrings** — explanations that fit aggregates but fail on keys.
5. **Find the bridge** — when two systems look unrelated, check both schemas for a cross-reference field. A 100%-populated field is a strong hint.
6. **Use control groups** — when claiming change X caused effect Y, find something in the same system that shouldn't have moved and show it didn't.

## The approval / checkpoint policy — quick reference

Full details in `refs/guardrails.md`. At a glance:

- **Code edits:** allowed without asking
- **Jira comments:** always ask, every time
- **Git commits / pushes / PR creation:** always ask at every step
- **Verification against un-refreshed data:** refuse
- **Orchestrator checkpoints:** post-diagnosis and pre-commit, both default-ON

## How to extend

- New diagnostic pattern learned in a case? Add it to `refs/worked-examples.md`. One case study per section; keep the "Situation / Insight / Lesson" structure.
- New Jira comment style the engineer prefers? Add a new template in `templates/` and update the `jira-commenter` agent's pointer.
- New verification check that should be standard? Add the SQL skeleton to `sql/verification-queries.sql` and update `refs/diagnostic-method.md`.

Updates here propagate to all agents in the family — no agent file edits needed.
