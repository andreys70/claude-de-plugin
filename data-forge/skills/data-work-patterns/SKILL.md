---
name: data-work-patterns
description: Shared reference for the data-forge plugin across all three workflows (fix, enhancement, create) — diagnostic and change-planning methods, Jira comment templates, and reusable SQL skeletons for verification. The three workflow commands (/data-forge:data-issue-fix, /data-forge:data-enhancement, /data-forge:data-creator) and all eight specialist sub-agents (data-issue-diagnoser, data-validator, data-pipeline-coder, data-work-intake, jira-commenter, bpp-pipeline-runner, git-release-agent, incident-scribe) delegate here for shared patterns.
---

# Data Work Patterns — shared reference

This skill is the single source of truth for patterns used across the `data-forge` agent family. It covers three workflows — **fix** (resolve a data anomaly), **enhancement** (implement a change against an existing pipeline), and **create** (build a net-new pipeline). If you are one of the agents below, read the relevant section here rather than duplicating the pattern in your own prompt.

## Layout

```
data-work-patterns/
├── SKILL.md                              ← this file (method index, workflow map)
├── templates/
│   ├── jira-investigation-comment.md     ← for mid-investigation Jira posts
│   ├── jira-verification-comment.md      ← for post-deploy Jira posts
│   ├── jira-cr-format.md                 ← Change Request format (pre-deploy)
│   ├── intake-report.md                  ← output format for data-work-intake
│   ├── diagnosis-report.md               ← output format for data-issue-diagnoser (fix flow)
│   ├── enhancement-plan.md               ← output format for the enhancement scope-and-plan phase
│   ├── scaffold-plan.md                  ← output format for the create scaffold-plan phase
│   └── validation-report.md              ← output format for data-validator (all modes)
├── sql/
│   └── verification-queries.sql          ← parameterized skeletons; three sections:
│                                              (A) anomaly-resolved (fix)
│                                              (B) acceptance-criteria (enhancement)
│                                              (C) first-run-healthy (create)
└── refs/
    ├── mcp-prerequisites.md              ← Phase 0 fail-fast MCP-registered check (all orchestrators)
    ├── partition-guidance.md             ← mandatory partition-pruning routine before any broad SQL query (diagnoser & validator)
    ├── diagnostic-method.md              ← the rule-out pattern for fix flow
    ├── change-plan-method.md             ← the "scope + propose diff before writing" pattern for enhancement and create flows
    ├── worked-examples.md                ← real case studies (bridges, control groups, red herrings)
    └── guardrails.md                     ← approval rules, checkpoint policy, destructive-action list
```

## When agents should consult this skill

- **`data-issue-diagnoser`** (fix flow only) → `refs/partition-guidance.md` (mandatory before broad SQL) + `refs/diagnostic-method.md` + `refs/worked-examples.md` + `templates/diagnosis-report.md`.
- **`data-work-intake`** → `templates/intake-report.md` (output format; works for all three workflows, mode hint controls which facets to foreground).
- **`data-pipeline-coder`** → `refs/guardrails.md` (what you must NOT do). For `mode: enhancement`, read `refs/change-plan-method.md` first. For `mode: scaffold`, read `templates/scaffold-plan.md` for the expected plan shape.
- **`data-validator`** → `refs/partition-guidance.md` (mandatory before broad SQL) + `sql/verification-queries.sql` (pick the section matching the check-set mode) + `templates/validation-report.md`.
- **`jira-commenter`** → `templates/jira-*-comment.md`. Always check the engineer's personal CR memory first (`~/.claude/projects/*/memory/feedback_cr_format.md`) — if present, it supersedes `templates/jira-cr-format.md`.
- **Orchestrators** (`/data-forge:data-issue-fix` command, `/data-forge:data-enhancement` command, `/data-forge:data-creator` command) → `refs/mcp-prerequisites.md` (Phase 0 fail-fast) + `refs/guardrails.md` (checkpoint and approval rules, workflow-specific notes).

## The diagnostic method — quick reference (fix flow)

The full method is in `refs/diagnostic-method.md`. At a glance:

1. **Reproduce the anomaly** with SQL. Actual numbers, not "significant drop."
2. **List 3–6 candidate root causes.** Include the un-sexy ones (ETL regression, filter drift, dead code path).
3. **Rule out each candidate** with a specific query or file inspection. Present the output.
4. **Watch for red herrings** — explanations that fit aggregates but fail on keys.
5. **Find the bridge** — when two systems look unrelated, check both schemas for a cross-reference field. A 100%-populated field is a strong hint.
6. **Use control groups** — when claiming change X caused effect Y, find something in the same system that shouldn't have moved and show it didn't.

## The change-plan method — quick reference (enhancement & create flows)

The full method is in `refs/change-plan-method.md`. At a glance:

1. **Scope the ask.** What exactly changes? What stays the same? What's out of scope?
2. **Read the current state.** For enhancement: the existing code/config being modified. For create: the target catalog + schema + closest sibling pipeline as a pattern.
3. **Propose the diff or scaffold BEFORE writing it.** List files to touch (or create), describe the change in one sentence each, state what will be validated at PRF.
4. **Name the acceptance criteria up front** — for enhancement, lifted from the Jira; for create, derived from the requirements. These become the validator's `acceptance-criteria` or `first-run-healthy` check set.
5. **Flag assumptions.** Anywhere the requirements are ambiguous, state the assumption explicitly so the engineer can correct it before code is written.

## The approval / checkpoint policy — quick reference

Full details in `refs/guardrails.md`. At a glance:

- **Code edits:** allowed without asking
- **Jira comments:** always ask, every time
- **Git commits / pushes / PR creation:** always ask at every step
- **Verification against un-refreshed data:** refuse
- **Orchestrator checkpoints:**
  - **fix flow (`/data-forge:data-issue-fix` command):** post-diagnosis, pre-commit, post-PRF (3, all default-ON)
  - **enhancement flow (`/data-forge:data-enhancement` command):** pre-commit, post-PRF (2, the plan is reviewed inline during Phase 2)
  - **create flow (`/data-forge:data-creator` command):** pre-commit, post-PRF (2, the scaffold plan is reviewed inline during Phase 2)

## How to extend

- New diagnostic pattern learned in a case? Add it to `refs/worked-examples.md`. One case study per section; keep the "Situation / Insight / Lesson" structure.
- New Jira comment style the engineer prefers? Add a new template in `templates/` and update the `jira-commenter` agent's pointer.
- New verification check that should be standard? Add the SQL skeleton to the matching section of `sql/verification-queries.sql` (A/B/C) and update `refs/diagnostic-method.md` or `refs/change-plan-method.md` accordingly.
- New workflow (beyond fix/enhancement/create)? Add a new slash command in `commands/` (the workflow command IS the orchestrator — there is no separate orchestrator agent), a matching template in `templates/`, and a new section in `sql/verification-queries.sql` if it needs its own check set.

Updates here propagate to all agents in the family — no agent file edits needed.
