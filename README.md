# data-forge — Claude Code plugin

End-to-end automation for three data-pipeline workflows in ETL codebases:

- **fix** (`/data-issue-fix`) — resolve a bug or data anomaly. Jira intake → diagnosis → code fix → PRF validation → BPP pipeline → post-deploy verification → Jira close-out. **Three checkpoints** (post-diagnosis, pre-commit, post-PRF).
- **enhancement** (`/data-enhancement`) — implement a non-bug change against an existing pipeline. Jira intake → scope & change plan → code change → PRF validation → BPP pipeline → post-deploy verification → Jira close-out. **Two checkpoints** (pre-commit, post-PRF). The plan is reviewed inline.
- **create** (`/data-creator`) — scaffold a net-new pipeline (config, code, or both). Intake (Jira preferred, freeform spec accepted) → scaffold plan → scaffold code → PRF dry-run → first-run verification → BPP pipeline → close-out. **Two checkpoints** (pre-commit, post-PRF). PRF iteration before PRD is expected.

Each workflow is its own slash command — `/data-forge:data-issue-fix`, `/data-forge:data-enhancement`, `/data-forge:data-creator`. A top-level `/data-forge:dispatch` command routes when the workflow isn't specified. The three workflow commands share a common roster of specialist sub-agents (intake, coder, validator, git-release, BPP runner, jira-commenter) — the validator and coder switch behavior based on a `mode` passed by the workflow command.

The workflow commands themselves contain the orchestration logic (Phase 0 MCP check, the nine phases, the checkpoints). They run in the main session, which means they can spawn sub-agents via the `Agent` tool — sub-agents cannot spawn other sub-agents, so an "orchestrator agent" pattern doesn't work in Claude Code, but a "command-as-orchestrator" pattern does.

Ships from the `intuit-de` marketplace (this repo), which may grow to host additional data-engineering plugins over time. The plugin itself lives at `data-forge/` inside the repo.

## Install

Claude Code installs plugins from **marketplaces**, not directly from plugin repos. This repo ships its own marketplace manifest (`.claude-plugin/marketplace.json`), so installing is two steps: register the `intuit-de` marketplace, then install the `data-forge` plugin from it.

### Prerequisites

Before installing, make sure you can clone this repo from GHE. Claude Code clones the marketplace repo on your behalf when you run `/plugin marketplace add`, so whatever auth `git clone` needs must already be set up.

- **SSH clone** (recommended): your SSH key must be registered at `github.intuit.com`. Test with `ssh -T git@github.intuit.com` — you should see a greeting, not a permission-denied error.
- **`gh` CLI** (optional but handy for the workflow itself): authenticated against `github.intuit.com` — `gh auth status --hostname github.intuit.com`.
- All [required MCPs](#required-mcps) connected — each workflow command fails fast at Phase 0 if any are missing.

### 1. Register the marketplace (once per machine)

Run this inside any Claude Code session:

```
/plugin marketplace add git@github.intuit.com:RiskDataAnalytics/claude-de-plugins.git
```

Claude Code clones the repo, reads `.claude-plugin/marketplace.json`, and registers the `intuit-de` marketplace locally. You only need to do this once per machine — the marketplace stays registered across sessions.

### 2. Install the plugin

```
/plugin install data-forge@intuit-de
```

The `@intuit-de` suffix tells Claude Code which marketplace to resolve `data-forge` from. Commands (`/data-forge:data-issue-fix`) and agents (`data-forge:data-issue-diagnoser`, etc.) become available immediately.

### Verify

```
/plugin marketplace list
/plugin list
```

You should see `intuit-de` in the marketplace list and `data-forge` in the plugin list.

### Update later

When the plugin ships a new version (anyone on the team merges changes to `master`), pull the update:

```
/plugin marketplace update intuit-de
/plugin install data-forge@intuit-de
```

**Restart Claude Code after the update.** Plugin agents and commands are loaded at session start; updates picked up by `/plugin install` only become active in a fresh session.

### Uninstall

```
/plugin uninstall data-forge
/plugin marketplace remove intuit-de
```

### Local development

When iterating on the plugin before pushing, point Claude Code at your local checkout instead of the GHE repo. Use the absolute path to your clone:

```
/plugin marketplace add ~/Documents/GitHub/claude-de-plugins
/plugin install data-forge@intuit-de
```

Changes to agent/skill files in the checkout are picked up on the next Claude Code session (no reinstall needed). If you edit `data-forge/.claude-plugin/plugin.json` or the root `.claude-plugin/marketplace.json`, run `/plugin marketplace update intuit-de` to refresh.

### Troubleshooting install failures

- **`fatal: Could not read from remote repository` / SSH permission denied** — your SSH key isn't set up for `github.intuit.com`. Re-check `ssh -T git@github.intuit.com`.
- **`marketplace.json: schema validation failed`** — you're on an older, broken version of the manifest. Run `/plugin marketplace update intuit-de` to pull the current one, or remove and re-add the marketplace.
- **Plugin installs but commands don't appear** — restart Claude Code; plugins are loaded at session start.

## Use

Pick the command that matches the workflow:

```
/data-forge:data-issue-fix JIRA-XXXX           # bug / data anomaly
/data-forge:data-enhancement JIRA-XXXX         # change to existing pipeline
/data-forge:data-creator JIRA-XXXX             # net-new pipeline (Jira)
/data-forge:data-creator "<freeform spec>"     # net-new pipeline (no ticket yet)
```

If you're not sure which one, the dispatcher asks:

```
/data-forge:dispatch                           # asks for input + workflow
/data-forge:dispatch JIRA-XXXX                 # asks for workflow only
/data-forge:dispatch JIRA-XXXX enhancement     # no prompts
```

Or invoke any specialist sub-agent directly:

```
Agent(data-forge:data-issue-diagnoser, "why is last_routing_number 97% NULL since Dec 2025?")
Agent(data-forge:bpp-pipeline-runner, "run pipeline for JIRA-XXXX")
Agent(data-forge:data-validator, "verify JIRA-XXXX on schema_name.table_name after commit <commit-sha>, mode: anomaly-resolved")
```

### Modes (for `data-pipeline-coder` and `data-validator`)

These two sub-agents take a `mode` parameter so the same agent can serve all three workflows. Orchestrators set this automatically; if you invoke either agent standalone, pass the mode that matches the situation:

| Agent | Mode | When to use |
|---|---|---|
| `data-pipeline-coder` | `fix` | applying a diagnosis to existing code (bug fix) |
| `data-pipeline-coder` | `enhancement` | applying an approved change plan to existing code |
| `data-pipeline-coder` | `scaffold` | creating net-new pipeline files from a scaffold plan |
| `data-validator` | `anomaly-resolved` | did the named anomaly (NULL%, etc.) actually go away? |
| `data-validator` | `acceptance-criteria` | does each acceptance criterion from the Jira pass? |
| `data-validator` | `first-run-healthy` | did the new pipeline produce a healthy first run? (table exists, schema matches, non-zero rows, required cols populated) |

## Required MCPs

The plugin requires four MCPs to be **registered** at the user level before running any command. These are non-negotiable prerequisites:

| MCP | Required for |
|---|---|
| `jira-mcp` | reading tickets, posting comments, transitioning status |
| `databricks-mcp` | running diagnostic and verification SQL |
| `DAST-Orch` | executing BPP pipelines (PRF and PRD) |
| `intuit-github-mcp` | opening pull requests |

Each workflow command's Phase 0 verifies these are *registered* (their tools are present in the toolset) and refuses to proceed if any is missing — you'll get an immediate `Missing MCP: <name>` message. Add the missing one to your MCP config and restart Claude Code.

**Authentication is deferred.** Phase 0 does not call any MCP tool — it only checks that the tools exist. Each MCP is authenticated on first actual use by the matching sub-agent during the workflow:

- `databricks-mcp` → first SQL call from `data-issue-diagnoser` (fix flow Phase 2) or `data-validator` (Phase 6/8)
- `intuit-github-mcp` → first PR-related call from `git-release-agent` (Phase 4)
- `DAST-Orch` → first call from `bpp-pipeline-runner` (Phase 5/7)
- `jira-mcp` → first call from `data-work-intake` (Phase 1) or `jira-commenter` (Phase 9)

This means you won't be asked to authenticate four services at the start of every run; you authenticate each one only when the workflow actually needs it, and only the first time per session.

(The create flow's Phase 1 also accepts a freeform spec when no Jira ticket exists yet — `jira-mcp` is then not required at all for that single run. The other three are still mandatory.)

### Why Databricks queries stay fast

Both `data-issue-diagnoser` and `data-validator` follow the routine in `data-forge/skills/data-work-patterns/refs/partition-guidance.md` before running any broad SQL: read the table DDL, identify partition columns, inject a date predicate from the Jira anomaly window or the post-change window. This is what keeps diagnostic and verification queries in the seconds-to-minutes range instead of multi-hour scans. If a query still takes more than ~30s, the agent will ask you for a tighter date range rather than waiting it out.

## Workflow diagram — fix flow

The fix workflow command (`/data-forge:data-issue-fix`) runs nine phases plus a working-branch pre-flight (Phase 3a). Three checkpoints (post-diagnosis, pre-commit, post-PRF-validation) gate on engineer approval. Destructive actions (Jira posts, git commits, git push, PR creation, BPP execution) always require explicit approval even inside an approved checkpoint.

The enhancement and create flows follow the same shape with two differences: Phase 2 is "scope & plan" (reviewed inline, no separate post-plan checkpoint) instead of diagnosis, and the validator runs in `acceptance-criteria` mode (enhancement) or `first-run-healthy` mode (create) instead of `anomaly-resolved`. The diagram below shows the fix flow as the canonical example.

```mermaid
flowchart TD
    Start([/data-issue-fix JIRA-XXX/])
    Start --> MCPCheck{MCPs connected?<br/>databricks-mcp, jira-mcp,<br/>DAST-Orch, intuit-github-mcp}
    MCPCheck -->|missing| FailFast[/Stop, tell engineer<br/>which MCP to reconnect/]
    MCPCheck -->|all present| P1

    P1[Phase 1: Intake<br/>read Jira + comments]
    P1 --> P2[Phase 2: Diagnosis<br/>rule-out pattern, SQL evidence]
    P2 --> CP1{Checkpoint 1<br/>review diagnosis?}
    CP1 -->|refine| P2
    CP1 -->|stop| End1([stop])
    CP1 -->|yes| P3a

    P3a[Phase 3a: Working branch<br/>cut feature/JIRA-KEY if on protected branch]
    P3a --> BranchGate{on protected branch<br/>or name mismatch?}
    BranchGate -->|yes| AskCheckout[/ask: cut new branch?/]
    AskCheckout --> P3
    BranchGate -->|no| P3

    P3[Phase 3: Code fix<br/>minimal diff, local validation]
    P3 --> CP2{Checkpoint 2<br/>review diff?}
    CP2 -->|refine| P3
    CP2 -->|stop| End2([stop])
    CP2 -->|yes| P4

    P4[Phase 4: Commit / Push / PR<br/>each action asks first]
    P4 --> P5[Phase 5: PRF pipeline execution<br/>BPP / EMR Serverless / local]
    P5 --> PRFGate{PRF table<br/>refreshed?}
    PRFGate -->|no| WaitPRF[/wait + retry/]
    PRFGate -->|yes| P6

    P6[Phase 6: PRF validation<br/>5 standard checks]
    P6 --> CP3{Checkpoint 3<br/>PRF results OK?}
    CP3 -->|adjust| P3
    CP3 -->|stop| End3([stop, needs more work])
    CP3 -->|yes| MergeConfirm

    MergeConfirm{engineer confirms<br/>PR merged?}
    MergeConfirm -->|not yet| End4([pause, resume later])
    MergeConfirm -->|merged| P7

    P7[Phase 7: PRD pipeline execution<br/>resolve name from Jira,<br/>confirm env, execute, poll]
    P7 --> PipeResult{pipeline result?}
    PipeResult -->|failed| ReportFail[/surface error,<br/>stop or retry/]
    PipeResult -->|success| StableGate

    StableGate{stable table<br/>refreshed?}
    StableGate -->|no| WaitStable[/wait + retry/]
    StableGate -->|yes| P8

    P8[Phase 8: Post-deploy verification<br/>stable table, 5 standard checks]
    P8 --> P9[Phase 9: Close-out<br/>post PRF + stable results to Jira]
    P9 --> CloseGate{close ticket?}
    CloseGate -->|yes| Transition[jira-commenter<br/>transition to Done/Resolved/Closed]
    CloseGate -->|skip| Done
    Transition --> Done([recap: ticket status, SHA, PR,<br/>PRF outcome, PRD pipeline,<br/>stable verification])

    style CP1 fill:#fff4cc
    style CP2 fill:#fff4cc
    style CP3 fill:#fff4cc
    style MergeConfirm fill:#fff4cc
    style PipeResult fill:#fff4cc
    style CloseGate fill:#fff4cc
    style PRFGate fill:#ffcccc
    style StableGate fill:#ffcccc
    style MCPCheck fill:#ffcccc
    style BranchGate fill:#fff4cc
```

**Legend:** yellow = engineer-gated decision; red = hard gate / fail-fast check.

## Agent roster map

Three workflow commands (one per workflow) share a common roster of specialist sub-agents. Each command owns its phase flow; sub-agents own their scoped work and are reused across workflows. The shared `data-work-patterns` skill is the single source of truth for templates, methods, and SQL.

**Workflow commands do not call MCP tools directly.** All Jira reads/writes, SQL execution, BPP pipeline runs, and PR creation are delegated to the matching sub-agent via `Agent`. The command's Phase 0 only inspects its own toolset to verify the MCPs are *registered* (no tool calls, no auth triggered). This keeps the command's tool surface minimal and makes failures attributable to the right specialist.

```mermaid
flowchart LR
    User([Engineer])
    User -->|/data-forge:dispatch<br/>or specific command| OrchPick

    OrchPick{workflow?}
    OrchPick -->|fix| FixCmd["/data-forge:data-issue-fix<br/>(slash command)"]
    OrchPick -->|enhancement| EnhCmd["/data-forge:data-enhancement<br/>(slash command)"]
    OrchPick -->|create| CreateCmd["/data-forge:data-creator<br/>(slash command)"]

    FixCmd     -.->|Phase 1| A1[data-work-intake]
    EnhCmd     -.->|Phase 1| A1
    CreateCmd  -.->|Phase 1| A1

    FixCmd     -.->|Phase 1 fallback| A8[incident-scribe]
    FixCmd     -.->|Phase 2 — diagnose| A2[data-issue-diagnoser]
    EnhCmd     -.->|Phase 2 — change plan| InlinePlan{{inline plan<br/>in command}}
    CreateCmd  -.->|Phase 2 — scaffold plan| InlinePlan

    FixCmd     -.->|Phase 3 — mode: fix| A3[data-pipeline-coder]
    EnhCmd     -.->|Phase 3 — mode: enhancement| A3
    CreateCmd  -.->|Phase 3 — mode: scaffold| A3

    FixCmd     -.->|Phases 4| A4[git-release-agent]
    EnhCmd     -.->|Phases 4| A4
    CreateCmd  -.->|Phases 4| A4

    FixCmd     -.->|Phases 5 / 7| A5[bpp-pipeline-runner]
    EnhCmd     -.->|Phases 5 / 7| A5
    CreateCmd  -.->|Phases 5 / 7| A5

    FixCmd     -.->|Phases 6 / 8 — anomaly-resolved| A6[data-validator]
    EnhCmd     -.->|Phases 6 / 8 — acceptance-criteria| A6
    CreateCmd  -.->|Phases 6 / 8 — first-run-healthy| A6

    FixCmd     -.->|Phase 9| A7[jira-commenter]
    EnhCmd     -.->|Phase 9| A7
    CreateCmd  -.->|Phase 9| A7

    Skill[(data-work-patterns skill)]
    A1 -.references.-> Skill
    A2 -.references.-> Skill
    A3 -.references.-> Skill
    A5 -.references.-> Skill
    A6 -.references.-> Skill
    A7 -.references.-> Skill
    FixCmd -.references.-> Skill
    EnhCmd -.references.-> Skill
    CreateCmd -.references.-> Skill

    A4 --- MCP_GH[("intuit-github-mcp")]
    A5 --- MCP_DAST[("DAST-Orch")]
    A6 --- MCP_DB[("databricks-mcp")]
    A2 --- MCP_DB
    A1 --- MCP_JIRA[("jira-mcp")]
    A7 --- MCP_JIRA
    A8 --- MCP_JIRA

    style FixCmd fill:#cce5ff
    style EnhCmd fill:#cce5ff
    style CreateCmd fill:#cce5ff
    style Skill fill:#d4edda
    style InlinePlan fill:#fff4cc
```

Every sub-agent can be invoked standalone (e.g., `Agent(data-issue-diagnoser, ...)`). Read-only sub-agents return findings and suggest the next step. Write sub-agents always gate before any write, regardless of invocation path.

## Repo layout

```
claude-de-plugins/                    ← git repo root (intuit-de marketplace)
├── .claude-plugin/
│   └── marketplace.json              ← marketplace manifest (stays at root)
├── README.md
└── data-forge/                       ← the plugin itself
    ├── .claude-plugin/
    │   └── plugin.json
    ├── agents/
    ├── commands/
    └── skills/
        └── data-work-patterns/
```

The root `marketplace.json` points at `data-forge/` via a relative `source` (`"./data-forge"`), so a single repo can ship multiple plugins as sibling directories in the future — each entry in `plugins[]` just points at its own folder.

## Architecture

Three pieces, working together:

### Slash commands (`data-forge/commands/`)
Workflow orchestrators. Each runs in the main session and spawns specialist sub-agents via `Agent`.

- `/data-forge:data-issue-fix` — fix flow (bug / data anomaly)
- `/data-forge:data-enhancement` — enhancement flow (change to existing pipeline)
- `/data-forge:data-creator` — create flow (net-new pipeline)
- `/data-forge:dispatch` — top-level router that asks for the workflow when not specified

### Specialist sub-agents (`data-forge/agents/`)
Isolated workers. Each runs in a fresh conversation context, owns a scoped piece of the workflow, and is reused across all three commands.

- `data-work-intake` — reads a Jira ticket + comments (or a freeform spec for create flow)
- `data-issue-diagnoser` — root-cause analysis (fix flow only)
- `data-pipeline-coder` — implements approved changes; modes: `fix` | `enhancement` | `scaffold`
- `bpp-pipeline-runner` — executes BPP pipeline (PRF and PRD)
- `data-validator` — verification; modes: `anomaly-resolved` | `acceptance-criteria` | `first-run-healthy`
- `jira-commenter` — posts Jira comments; optionally transitions the ticket to a terminal status
- `git-release-agent` — commit / push / PR
- `incident-scribe` — structures raw incident reports (used by fix flow's Phase 1 fallback)

### Skill (`data-forge/skills/data-work-patterns/`)
Shared reference library that commands and agents delegate to — diagnostic and change-planning methods, comment templates, plan templates, mode-aware SQL skeletons, guardrails. Updates here propagate to every command and agent without editing prompts. Referenced inside command and agent prompts as `${CLAUDE_PLUGIN_ROOT}/skills/data-work-patterns/...` (where `${CLAUDE_PLUGIN_ROOT}` resolves to `data-forge/`).

```
data-work-patterns/
├── SKILL.md
├── refs/
│   ├── mcp-prerequisites.md      ← Phase 0 fail-fast MCP-registered check (all workflow commands)
│   ├── partition-guidance.md     ← mandatory partition-pruning routine before broad SQL (diagnoser & validator)
│   ├── diagnostic-method.md      ← rule-out pattern (fix flow)
│   ├── change-plan-method.md     ← scope-and-plan pattern (enhancement & create)
│   ├── worked-examples.md        ← real case studies (bridges, control groups, red herrings)
│   └── guardrails.md             ← approval policy, checkpoints, non-negotiables
├── templates/
│   ├── intake-report.md
│   ├── diagnosis-report.md       ← fix flow output
│   ├── enhancement-plan.md       ← enhancement flow Phase 2 output
│   ├── scaffold-plan.md          ← create flow Phase 2 output
│   ├── validation-report.md      ← mode-aware: A / B / C sections
│   ├── jira-investigation-comment.md
│   ├── jira-verification-comment.md
│   └── jira-cr-format.md
└── sql/
    └── verification-queries.sql  ← three sections:
                                       A — anomaly-resolved (fix)
                                       B — acceptance-criteria (enhancement)
                                       C — first-run-healthy (create)
```

## Roster summary

Workflow commands (in `data-forge/commands/`) run in the main session and inherit its tool surface; they spawn the agents below via `Agent`. Agents (in `data-forge/agents/`) have explicit `tools:` declarations — the table summarizes capability classes; see each agent's frontmatter for the exact tool list.

| Agent | Filesystem | Shell | MCP | Writes? |
| --- | --- | --- | --- | --- |
| `data-work-intake` | Read | — | jira-mcp | no |
| `data-issue-diagnoser` | Read, Grep, Glob | Bash | databricks-mcp | no |
| `data-pipeline-coder` | Read, Edit, Write, Grep, Glob | Bash | — | edits/creates files, no commit |
| `bpp-pipeline-runner` | Read | ScheduleWakeup | DAST-Orch | BPP only, with approval |
| `data-validator` | Read | Bash | databricks-mcp | no |
| `jira-commenter` | Read | — | jira-mcp | Jira comments + ticket transitions, with approval |
| `git-release-agent` | Read | Bash | intuit-github-mcp | git only, with approval |
| `incident-scribe` | Read, Grep, Glob | — | jira-mcp | Jira only, with approval |

## Guardrails

See `data-forge/skills/data-work-patterns/refs/guardrails.md` for the full policy. Quick reference:

- **Code edits:** allowed without asking
- **Jira comments:** always ask first
- **Git commits / pushes / PRs:** always ask at every step
- **BPP pipeline execution:** always ask; never silently default to PRD; never poll GitHub to auto-trigger on merge
- **Verification:** refuses to run against un-refreshed data (non-negotiable)
- **Scope creep:** second bugs noted, primary fix stays focused

## Checkpoints

Per workflow:

| Workflow | Checkpoints |
| --- | --- |
| **fix** (`/data-forge:data-issue-fix`) | 1. Post-diagnosis<br>2. Pre-commit (diff review)<br>3. Post-PRF (acceptance to proceed to PRD) |
| **enhancement** (`/data-forge:data-enhancement`) | 1. Pre-commit (diff against approved plan)<br>2. Post-PRF (acceptance criteria pass) |
| **create** (`/data-forge:data-creator`) | 1. Pre-commit (scaffold review)<br>2. Post-PRF (first-run-healthy pass) |

In the enhancement and create flows, the Phase 2 plan (change plan / scaffold plan) is **reviewed inline during Phase 2** — not as a separate post-plan checkpoint — so the engineer can refine/approve/stop without an explicit gate ceremony.

All checkpoints default-ON. "Skip checkpoint" is honored when the engineer is explicit but noted in the response for audit.

## Project context

Each workflow command reads `CLAUDE.md` (project root, parent dirs, `~/CLAUDE.md`) for conventions — Jira project key, catalog names, ETL script patterns. **No cross-session memory** — each run re-reads rather than recalling.

## Extending

- **New diagnostic pattern?** Add to `data-forge/skills/data-work-patterns/refs/worked-examples.md`. One case study per section; keep Situation / Insight / Lesson structure.
- **New Jira comment template?** Add to `data-forge/skills/data-work-patterns/templates/` and update `jira-commenter`'s template pointer list.
- **New verification check?** Add to the matching section (A / B / C) of `data-forge/skills/data-work-patterns/sql/verification-queries.sql` and mention it in `refs/diagnostic-method.md` (fix) or `refs/change-plan-method.md` (enhancement / create).
- **New workflow?** Add a new slash command in `commands/` (the workflow command IS the orchestrator — there is no separate orchestrator agent), a Phase 2 plan template in `templates/`, and a new section in `sql/verification-queries.sql` if the workflow needs its own check set. The validator and coder both accept new modes via their `mode` parameter — no code edits needed for the shared sub-agents.
- **New repo?** Ensure it has a `CLAUDE.md` describing its conventions and that its data warehouse MCP is connectable. No agent code changes required.

## Example session — fix flow

The fix flow has the most phases and is shown below as a representative example. The enhancement and create flows look similar, but Phase 2 is "scope & plan" reviewed inline (not a separate checkpoint), and validation runs in `acceptance-criteria` or `first-run-healthy` mode respectively.

```
> /data-issue-fix JIRA-XXXX

[Phase 1] Reading JIRA-XXXX... 4 comments. Last comment retracted
Payments 2.0 UNION approach. Currently awaiting validation of a
parallel-join fix using mt_txn_id.

Continue to diagnosis? (yes / stop)
> yes

[Phase 2] Diagnoser ran 8 queries. Root cause: join key mismatch —
Payments 2.0 payment_txn_id doesn't match legacy numeric txn_id.
Bridge is mt_txn_id (100% populated, same alphanumeric format).
Match rate tracks NULL rate to the percentage point.

CHECKPOINT 1: here's the diagnosis. Review before code changes?
> yes, looks right

[Phase 3] Coder: added _ihub_check_clear_pmt2_cte, parallel join,
COALESCE on 3 columns. Diff: +19 -30 lines, 1 file.

CHECKPOINT 2: here's the diff. Approve?
> yes

[Phase 4] Commit / push / PR?
> yes to all

[committed 6875fe0a, pushed, PR #742 opened]

[Phase 5] How do you want to run the fix against PRF?
  1. BPP pipeline
  2. EMR Serverless / local / other
  3. Skip (not recommended)
> 1, pipeline is ips_transactions_check_new_prf

[triggered PRF execution abc123, polling...
 ... 6m later: SUCCESS]

Has the PRF target table been refreshed? (yes / no)
> yes

[Phase 6] PRF validator: NULL% at 0.35% across Feb–Apr 2026.
Row count parity OK. Spot-check: 10/10. Cardinality preserved.

CHECKPOINT 3: PRF validation looks clean. Proceed to PRD?
> yes

Ready for PRD. Once you've merged the PR, let me know.
> merged

[Phase 7] Run the BPP pipeline now? Name from Jira 'Dev Portal
Asset Alias': `t_ips_transactions_check_new_pipeline`.
Env: PRD. (yes / switch to E2E / cancel)
> yes

[triggered PRD execution def456, polling...
 ... 4m later: SUCCESS]

Has the stable target table been refreshed? (yes / no)
> yes, refreshed this morning

[Phase 8] Stable validator: NULL% collapsed from 97% to 0.35%
across Feb–Apr 2026. Row count parity: diff = 0. Spot-check: 10/10.

[Phase 9] Post PRF + stable verification to Jira?
> yes

[jira-commenter posted comment 15291782]

Close JIRA-XXXX now? Available transitions: `Done`, `Cancelled`. (yes / skip)
> yes, Done

[transitioned JIRA-XXXX → Done]

Recap: JIRA-XXXX fixed (SHA 6875fe0a), status Done. PR #742 merged.
PRF validated, PRD pipeline succeeded. NULL% baseline restored in stable.
```

## Why this layout

- **Workflow command IS the orchestrator** → slash commands run in the main session, so they can spawn specialist sub-agents via `Agent`. An "orchestrator agent" pattern doesn't work in Claude Code — sub-agents cannot spawn other sub-agents.
- **Agents** run in isolated contexts → each specialist's context doesn't balloon.
- **Three commands, one shared roster** → workflows differ only where they actually differ (intake framing, Phase 2 method, validator mode); the rest is shared code.
- **Skill** is the single source of truth for shared patterns → update in one place, all commands and agents benefit. Adding a new workflow means adding one slash command + one Phase 2 template + one SQL section, not duplicating the roster.
- **`mode` parameter on coder and validator** → behavior switches per workflow without forking the agents. Adding a fourth workflow later just means another mode value.
- **Templates** as separate files → easier to version, easier for engineers to tweak without prompt edits.
- **SQL skeletons** in their own file → can be copy-pasted into a Databricks notebook for ad-hoc investigation.
- **Worked examples** as a growing file → the system learns over time as patterns are added.
- **Plugin nested under `data-forge/`** → the `intuit-de` marketplace can ship additional plugins as sibling directories without restructuring.
