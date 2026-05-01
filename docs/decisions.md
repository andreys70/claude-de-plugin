# Architecture decisions

Lightweight log of non-obvious design choices for the `data-forge` plugin and the `intuit-de` marketplace. Each entry records what we picked, what we considered instead, and why. Newest at the top.

The format intentionally borrows from ADRs (architecture decision records) but stays single-file so it's grep-able. When this file gets long enough that scrolling hurts, split into `docs/adr/NNNN-<slug>.md`.

---

## 2026-04-30 — Workflow commands ARE the orchestrators (no orchestrator agents)

**Context.** The original architecture had three orchestrator *agents* (`data-issue-fixer`, `data-enhancement-driver`, `data-creator-driver`), each invoked by a thin slash command. At runtime this broke: the orchestrator agent reported "the Agent tool isn't available," and intake sub-agents printed their tool calls as text instead of invoking them. Confirmed by the docs (`code.claude.com/docs/en/sub-agents`): **subagents cannot spawn other subagents.** Slash commands run in the main session and CAN spawn subagents; agents invoked via the `Agent` tool are themselves subagents and cannot. The orchestrator-agent pattern fundamentally doesn't work in Claude Code.

**Options considered.**

- **A. Inline orchestration into the slash commands.** ← chosen
- **B. Move orchestrators to the main thread via `claude --agent`.** Different invocation UX (`claude --agent X` instead of `/X`), and we'd lose the slash-command surface entirely.
- **C. Flatten each orchestrator into a single end-to-end agent that does ALL work itself (no delegation).** Loses isolation benefits (intake/coder/validator each running in fresh contexts), balloons each orchestrator to thousands of lines, and makes failures harder to attribute.
- **D. Switch to [agent teams](https://code.claude.com/docs/en/agent-teams).** Bigger architectural shift; agent teams coordinate across separate sessions and are designed for parallel work, not the sequential phase flow we have.

**Choice.** A. Each workflow's slash command (`commands/data-issue-fix.md`, `commands/data-enhancement.md`, `commands/data-creator.md`) now contains the full orchestration logic — Phase 0 MCP check, the nine phases, the checkpoints, the delegation table. The three orchestrator agent files were deleted. Sub-agents (intake, coder, validator, etc.) stay exactly as they were — they're invoked via `Agent` from the main-session slash command, which works.

The `/data-forge:dispatch` command still routes by intent, but instead of invoking an orchestrator agent it now prints the matching slash command for the engineer to run as a second keystroke. We considered having the dispatcher embed the matching command's content directly (auto-run), but that would have meant duplicating each command's body — too much copy-paste drift.

**Rationale.** The right mental model in Claude Code: **commands are the only "main-session-with-tools-and-Agent" surface available to plugins**. Anything that needs to spawn sub-agents must be a command, not an agent. We treated commands as thin dispatchers and agents as the workhorses, but the architecture inverted: commands ARE the workhorses for orchestration; agents are scoped specialists they spawn.

The downsides we accepted:
- The dispatcher is two-step (route, then engineer types the command). One extra keystroke for the convenience of not duplicating ~250 lines per workflow.
- Documentation churn: README, SKILL.md, every "orchestrator" mention had to be reframed as "workflow command."

What we kept from the previous architecture:
- The three-workflow shape (fix / enhancement / create) — completely preserved.
- The nine-phase flow per workflow — completely preserved.
- The shared sub-agent roster — completely preserved.
- The mode parameter on coder and validator — completely preserved.
- The `data-work-patterns` skill — completely preserved.

So this was a **structural relocation**, not a redesign. The choice of where to put the orchestration changed; what the orchestration does didn't.

**How to apply for new workflows.** When adding a fourth workflow, create a slash command in `commands/<name>.md` containing the orchestration. Do NOT create an orchestrator agent — they don't work.

---

## 2026-04-24 — Three workflows, three orchestrators, one shared roster

**Context.** The plugin originally shipped one orchestrator (`data-issue-fixer`) framed entirely around bug resolution. Engineers also do enhancement work (changes to existing pipelines) and net-new pipeline work (config/code from scratch). Both were getting awkwardly bolted onto the bug orchestrator — the diagnose phase was either misframed or skipped, the validator was checking "did the anomaly go away" against changes that had no anomaly.

**Options considered.**

- **A. Three commands inside `data-forge`, three orchestrators, shared sub-agent roster.** ← chosen
- **B. Three separate plugins under `intuit-de`.** Cleaner versioning per workflow, but ~70% of agents would be duplicated across plugins. Engineers would also have to install three things instead of one.
- **C. One orchestrator with a mode parameter.** Tempting because of less code, but Phase 2 (diagnose vs change-plan vs scaffold-plan) is genuinely different across workflows, and bundling the branches into one prompt would have made it the longest agent file in the plugin.

**Choice.** A — three orchestrators (`data-issue-fixer`, `data-enhancement-driver`, `data-creator-driver`) sharing a common roster (`data-work-intake`, `data-pipeline-coder`, `data-validator`, `bpp-pipeline-runner`, `git-release-agent`, `jira-commenter`, plus `data-issue-diagnoser` and `incident-scribe` used only by fix flow).

**Rationale.** Each orchestrator stays ≤ ~300 lines and is readable end-to-end. Sub-agents that genuinely have to differ (the coder editing existing files vs creating new ones; the validator checking anomaly resolution vs acceptance criteria vs first-run health) take a `mode` parameter rather than forking into separate agents. Adding a fourth workflow later is one new orchestrator + one new command + one Phase 2 template + one SQL section, not a fork of the whole roster.

---

## 2026-04-24 — `mode` parameter on `data-pipeline-coder` and `data-validator`

**Context.** The shared sub-agents do *almost* the same job across workflows but with non-trivial behavioral differences. Coder for `fix` and `enhancement` is minimal-diff against existing files; coder for `create` mirrors a sibling pipeline and creates files from scratch. Validator for `fix` checks anomaly resolution vs baseline; for `enhancement` checks each acceptance criterion plus a regression spot-check; for `create` checks schema/non-zero-rows/required-columns/dups.

**Options considered.**

- **A. `mode` parameter on the existing agents.** ← chosen
- **B. Sibling agents per workflow** (`data-pipeline-scaffolder`, `acceptance-criteria-validator`, `first-run-validator`). More files, more place to drift, more places to update when sub-agent conventions change.
- **C. Inline branching in the orchestrator** that effectively reimplements the sub-agent's logic for the alternate workflows. Defeats the point of having sub-agents.

**Choice.** A. Coder takes `mode: fix | enhancement | scaffold`. Validator takes `mode: anomaly-resolved | acceptance-criteria | first-run-healthy`. Each agent's prompt has a small "modes" section near the top that branches on the value; behavioral rules common to all modes live above that branch.

**Rationale.** Two reasons. (1) The agents share substantially more than they diverge — guardrails, output formatting, refresh-gate logic, "no commits / no pushes" rules are all identical across modes. (2) Mode strings give us a vocabulary the orchestrator can use unambiguously when invoking the sub-agent. If we add a fourth workflow we add one mode value to two agents, not a new agent file plus all its boilerplate.

---

## 2026-04-24 — Phase 2 plan reviewed inline, not as a separate checkpoint

**Context.** Fix flow has Checkpoint 1 (post-diagnosis) as an explicit gate ceremony before code starts. Enhancement and create flows also have a Phase 2 (change plan / scaffold plan) that the engineer needs to approve before the coder runs. We had to decide whether to make that a third checkpoint (matching fix flow) or fold it into Phase 2 itself.

**Options considered.**

- **A. Inline review during Phase 2** with the same approve/refine/stop options as a checkpoint. ← chosen
- **B. Explicit Checkpoint 1 (post-plan) as a separate phase boundary,** parallel to fix flow's CP1.
- **C. No review at all** — orchestrator drafts the plan, hands it straight to the coder. Implicit "if the engineer dislikes the diff, they'll catch it at CP1 (pre-commit)."

**Choice.** A. Engineer is asked `(approve / refine / stop)` immediately after the plan is presented, but it's framed as part of Phase 2 rather than a checkpoint ceremony.

**Rationale.** Phase 2 is the *only* thing happening in Phase 2 — there's no other work being done that the gate is interrupting. Making it a separate checkpoint adds bureaucratic feel without adding actual safety. The same approve/refine/stop semantics apply; the orchestrator just doesn't bold "⚠️ CHECKPOINT N" around it. Net result: enhancement and create have two checkpoints (pre-commit, post-PRF) instead of three, which feels right given they have one fewer truly-separate phase than fix flow.

C was rejected because the plan is the cheap correction point. Catching a misunderstanding here (one page of bullets) is much cheaper than catching it at CP1 (a coded-and-locally-validated diff).

---

## 2026-04-24 — Engineer-prompt convention

**Context.** Every orchestrator has multiple engineer-choice prompts (review checkpoints, action prompts, post-PRF gates). Without a convention they drift — some use "yes" as the affirmative, some use "approve"; some list branches in different orders; some have explicit handler bullets and some leave the LLM to infer.

**Options considered.**

- **A. Strict convention enforced across all orchestrators.** ← chosen
- **B. Let each orchestrator's author choose** as long as the prompt is unambiguous.

**Choice.** A. Three prompt categories with fixed wording:

| Category | Wording | Examples |
|---|---|---|
| Review of an artifact (plan, diff, scaffold) | `(approve / refine / stop)` | post-diagnosis, pre-commit, scaffold review |
| Post-PRF gate (proceed to PRD?) | `(yes / adjust / stop)` for fix/enhancement; `(yes / iterate / stop)` for create | CP3 in fix, CP2 in enhancement and create |
| Action prompt | `(yes / skip / not yet)` or `(yes / skip)` | run BPP pipeline, close ticket |

Branch order is always **affirmative → loop-back → stop**. Every prompt has explicit `**On "X":**` handler bullets immediately after.

**Rationale.** The orchestrators run in fresh contexts, so consistent vocabulary helps the model recognize the prompt shape and respond correctly. It also helps engineers who run multiple workflows over a week — they don't have to remember which command uses which verb. The "iterate" vs "adjust" verb on the create flow is intentional: net-new pipelines almost always need a few PRF dry-runs, so "iterate" frames the loop as expected rather than exceptional.

---

## 2026-04-24 — Marketplace `source` is `"./data-forge"`, not a `git-subdir` URL

**Context.** When the plugin was first wired up, the marketplace manifest used `"source": { "source": "url", "url": "git@github.intuit.com:..." }` plus a top-level `"path": "data-forge"`. That was wrong on two counts — `path` isn't a plugin-level field in the marketplace schema (it's only valid inside a `git-subdir` source object), so Claude Code was cloning the whole repo as the plugin and not finding `plugin.json`. Installation just failed.

**Options considered.**

- **A. Relative-path source `"./data-forge"`.** ← chosen
- **B. `git-subdir` source with `url` + `path`.** Works for GHE installs but fragile for local-dev installs where the engineer adds the local checkout path as the marketplace.

**Choice.** A. The plugin entry is `{"name": "data-forge", "source": "./data-forge", "description": "..."}` — the relative path resolves against the marketplace root.

**Rationale.** Per the Claude Code docs, relative paths "only work when users add your marketplace via Git (GitHub, GitLab, or git URL)." Both our install paths are git-based: GHE clones via `git@github.intuit.com:...`, and local-dev does `/plugin marketplace add ~/Documents/GitHub/claude-de-plugins` which Claude Code treats as a local git repo. So the relative form works in both contexts and avoids duplicating the GHE URL inside the manifest (which would otherwise need an update if the repo ever moved).

---

## 2026-04-24 — Plugin nested under `data-forge/`, not at repo root

**Context.** The repo contains exactly one plugin today. Two layouts work: plugin files at repo root (with `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` both at root), or plugin nested in `data-forge/` (with marketplace at root and plugin at `data-forge/`).

**Options considered.**

- **A. Plugin nested under `data-forge/`, marketplace manifest at root.** ← chosen
- **B. Single-plugin layout with everything at root.**

**Choice.** A.

**Rationale.** The `intuit-de` marketplace is intended to grow over time — additional data-engineering plugins as siblings of `data-forge/`. A nested layout means the second plugin is a directory addition + a `marketplace.json` `plugins[]` append, not a restructuring. The cost of the nested layout when there's only one plugin is one extra directory level, which is trivial.

---

## 2026-04-24 — No cross-session memory in the agent family

**Context.** Several agents repeatedly read project context (CLAUDE.md files, repo state) and could in principle cache findings across sessions. We had to decide whether the orchestrators should persist anything.

**Options considered.**

- **A. Stateless across sessions — re-read every time.** ← chosen
- **B. Persist a small index per repo** (e.g., known sibling pipelines, last validated tables, frequently referenced file paths).

**Choice.** A. The orchestrators read `CLAUDE.md` (project root, parent dirs, `~/CLAUDE.md`), repo conventions, and Jira state at the start of each run. Nothing carries forward between sessions.

**Rationale.** Data engineering codebases shift fast — pipelines get renamed, tables get migrated, conventions evolve. A cached "this is the sibling for payments" or "this is the table for FIND-X" goes stale silently and an agent that trusts the cache produces confidently wrong work. The cost of re-reading every run is small (cheap MCP calls + a few file reads); the cost of a stale-cache failure can be a wrong fix landed in PRD. Falls under the same principle as the validator's refresh gate: prefer being right over being fast.

This decision is also stated in the orchestrator prompts under "Behavioral rules" → "Memory discipline."
