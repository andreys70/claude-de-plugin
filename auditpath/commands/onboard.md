---
description: End-to-end SOX pipeline onboarding — JIRA intake, source analysis, DM + DQ conf generation, BPP registration, unit testing, SOX metadata entry, DQ execution, SOX completeness/accuracy validation, and JIRA close-out. Domain-agnostic: works for QBC, Loss Reserve, Capital, or any future domain.
argument-hint: <JIRA-KEY>
---

You are now driving the AuditPath SOX pipeline onboarding workflow for JIRA ticket: **$ARGUMENTS**

**CRITICAL ARCHITECTURE NOTE:** Run this workflow **directly in this conversation** — do NOT invoke the `orchestrator` sub-agent. Sub-agents in Claude Code cannot use ToolSearch to load deferred MCP tools, but you (the parent session) can. Drive the 14-phase workflow yourself, calling sub-agents only for self-contained tasks (file generation, analysis on data you've already fetched).

---

## How to use sub-agents correctly

- **You (parent session)** = MCP gateway. Call `mcp__claude_ai_Atlassian__*` for JIRA, `mcp__databricks__*` for SQL, `mcp__github__*` for GitHub files, BPP MCP tools for pipeline execution/polling/log retrieval. Use `ToolSearch(...)` first if a tool isn't pre-loaded.
- **Sub-agents** = file/analysis workers. They receive pre-fetched data as input. They write conf files, run local Bash, do analysis. They do NOT call MCP tools.
- **BPP MCP tools are ALWAYS called in the parent session** — never delegated to bpp-runner or any sub-agent. This includes: `execute_pipeline`, `get_pipeline_execution_history`, `get_execution_details`, `debug_emr_pipeline_jobs`. The bpp-runner sub-agent is effectively retired; Phases 5 and 10 run inline.

When invoking a sub-agent, pass the data it needs as part of the prompt, not just a JIRA key.

---

## Hard-coded conventions (apply to every onboarding)

- **Target schema is always `finance_mm_sandbox`** — never `finance_mm_dm`, `finance_mm_sox`, or any other schema. New pipelines are always built and validated under `finance_mm_sandbox`. The DM table goes under `finance_mm_sandbox.<table_name>`. Do not infer the target schema from any other source.
- **SOX table schema mapping — memorize this, never guess:**
  - `finance_mm_sandbox.RPT_SOX_SETUP` — pipeline registration (insert here in Phase 7)
  - `finance_mm_sandbox.RPT_SOX_METADATA` — date window configuration (insert here in Phase 7)
  - `finance_sandbox.RPT_SOX_COMPLETENESS` — completeness results written by DQ job (query here in Phase 11)
  - `finance_sandbox.RPT_SOX_ACCURACY` — accuracy results written by DQ job (query here in Phase 11)
- DM conf folder: `configs/finance_mm_dm/<domain>/<table_name>.conf` (folder name keeps `finance_mm_dm` — only the runtime target schema is sandbox)
- DQ conf folder: `configs/finance_mm_sox/<domain>/dq_<table_name>.conf`

- **Write mode default is `incremental`.** Always prefer incremental over full-refresh. Use full-refresh **only** if one of these three exact conditions is met:
  1. The JIRA ticket explicitly says "full refresh" / "full load" / "rebuild from scratch", OR
  2. There is no usable CDC / change-tracking column on **any** source table (no `lastUpdated`, `modified_date`, `audit_upd_ts`, `ingest_date`, `logDate`, or equivalent on any of the contributing source tables), OR
  3. The source is a snapshot table where every row gets re-emitted on every load (no row-level update timestamp exists).
  
  **NOT valid reasons for full-refresh** (these are explicitly forbidden as justifications):
  - ❌ "The source SQL has cumulative window functions / aggregations / running sums"
  - ❌ "Re-classification logic could retroactively change historical rows"
  - ❌ "It would be hard to incrementalize"
  - ❌ "The source SQL has many CTEs"
  - ❌ "The source has no partition filter"
  - ❌ "The output is large"
  - ❌ Any other reasoning beyond the three explicit conditions above
  
  Multi-table CDC handles cumulative/derived logic correctly: when a primary key changes in any source table, the corresponding target row is fully recomputed (cumulative windows included). The full-cumulative scan happens on every run regardless of write mode — what's incremental is which target rows get re-emitted, not how the SQL runs.
  
  Document the chosen `write_mode`, `cdc_sources` (per multi-table CDC rule), and primary `cdc_column` in the source analysis report. If write_mode is `full_refresh`, state which of the three explicit conditions above triggered it — verbatim quote from JIRA, or "no source table has a usable CDC column" with proof (DESCRIBE output for each).

- **Multi-table CDC for incremental loads.** If a target row can change due to updates in any of several upstream tables, the incremental window must scan ALL of those tables — not just the primary one. In Phase 2, identify every source table that contributes to the final output (joined or unioned in the source SQL). For each, determine its CDC column. The incremental "changed primary keys" sub-step must:
  1. UNION the changed primary keys from every contributing source table (each filtered by its own CDC column over the incremental window)
  2. SELECT DISTINCT the resulting primary keys
  3. Use those keys to drive the main transformation — only rows whose key matches a changed-key from any source are recomputed
  
  This guarantees that an update in any upstream table (not just the primary) flows into the target. Document each source table and its CDC column in the analysis report.

- **Branch creation rule.** Build branches always come from the project's parent branch, NOT from `master` or `main`.
  - The project branch is named after the domain: e.g., `qbc` for QBC pipelines, `loss-reserve` for Loss Reserve pipelines, `capital` for Capital pipelines, etc.
  - At the start of Phase 3 (DM Build), find the project branch:
    1. `git fetch origin`
    2. `git branch -r | grep -i "^[[:space:]]*origin/<domain_lowercase>$"` — must match the bare project branch name (e.g., `origin/qbc`), NOT a feature branch with `qbc` in the name
    3. If multiple candidates, prefer an exact match for the lowercased domain
    4. If no project branch exists for the domain, stop and ask the engineer which branch to use as the parent
  - Cut the feature branch from that project branch. The feature branch name is exactly the JIRA key — no `feature/` prefix, no description suffix:
    ```
    git checkout origin/<project_branch>
    git checkout -b <JIRA-KEY>
    ```
  - Example: for FIND-430 (QBC domain), parent is `origin/qbc`, branch is `FIND-430`.
  - **Before checking out a fresh project branch, the working tree must be clean.** If `git status` shows uncommitted changes from a previous session, either commit/push them on their original branch, or `git stash push -m "<context>"` first. Never silently `stash` and forget — surface to the engineer that there are uncommitted changes and ask before stashing.
  - Record `parent_branch` and `branch` in session state. Never push or commit to the parent project branch directly.
  - **Push the branch to remote immediately after the first commit** so the engineer can see and link to it. Use `git push -u origin <JIRA-KEY>`. Do not wait for the engineer to ask.

## Session state — maintain throughout, persist to disk

State schema:
```
{
  jira_id, table_name, domain, target_schema: "finance_mm_sandbox", sox_source_schemas,
  write_mode, grain, pk_expression, partition_needed, recommended_partition,
  validated_cols, branch, parent_branch, dm_conf_path, dq_conf_path, setup_id,
  dq_pipeline_name, accuracy_cols, dm_pipeline_name, dq_bpp_pipeline_name,
  dm_execution_type, dq_execution_type, dm_run_id, dq_run_id,
  unit_test_result, validation_result,
  dm_fix_attempts: 0, dq_fix_attempts: 0, analysis_rounds: 0,
  current_phase: 1,                    // 1-13, last completed phase + 1 = next phase
  status: "in_progress",               // in_progress | paused | completed | failed
  last_updated: "<ISO timestamp>"
}
```

**Persistence — write state file at the end of every phase and every checkpoint:**

State file location: `~/.claude/auditpath/state/<JIRA-KEY>.json`

Write the file using `Bash` with `mkdir -p` and a heredoc:
```bash
mkdir -p ~/.claude/auditpath/state
cat > ~/.claude/auditpath/state/<JIRA-KEY>.json <<EOF
{ ...full state object as JSON... }
EOF
```

**Resume protocol:** When `/auditpath:onboard <JIRA-KEY>` is invoked, the very first step is:

```bash
test -f ~/.claude/auditpath/state/<JIRA-KEY>.json && cat ~/.claude/auditpath/state/<JIRA-KEY>.json
```

- If the file exists, load the state and present a resume prompt to the engineer:
  ```
  📂 Found prior session for <JIRA-KEY>
  
    Last phase completed: <current_phase - 1>
    Status: <status>
    Last updated: <last_updated>
    Branch: <branch>
    DM conf: <dm_conf_path>
    DM pipeline: <dm_pipeline_name>
    DQ pipeline: <dq_bpp_pipeline_name>
    
    [resume]   — Continue from Phase <current_phase>
    [restart]  — Discard saved state and start over from Phase 1
    [view]     — Show full saved state, then ask
  ```
- On `resume`, jump directly to the next phase. Do NOT re-fetch the JIRA ticket, re-run source analysis, or re-do anything from earlier phases unless their data is missing from the saved state.
- On `restart`, delete the state file (`rm ~/.claude/auditpath/state/<JIRA-KEY>.json`) and start Phase 1 normally.
- If no state file exists, start Phase 1 normally.

After every successful phase completion (and after every checkpoint approval), update `current_phase` and `last_updated`, then re-write the state file. This guarantees you can stop at any point — even mid-phase — and resume cleanly.

---

## 14-phase flow

### Phase 1 — JIRA Intake
1. Call `mcp__claude_ai_Atlassian__getAccessibleAtlassianResources` to get the cloudId for `intuit-prod.atlassian.net` (or use `jira.cloud.intuit.com` directly as cloudId).
2. Call `mcp__claude_ai_Atlassian__getJiraIssue` with `cloudId` and `issueIdOrKey=$ARGUMENTS`, `responseContentFormat="markdown"`.
3. Invoke `jira-intake` sub-agent, passing both `jira_id` and the full ticket data in the prompt. The sub-agent updates the ticket body and returns a structured intake report.
4. Update session context from the intake report.

### Phase 2 — Source Analysis

**Databricks query helper — use this for ALL Databricks SQL.** Do NOT use `mcp__databricks__execute_sql` for results-based queries — it returns PENDING and never polls. Instead, use the Databricks REST SQL Statements API directly via Bash, with a running SQL warehouse:

```bash
# One-time setup: pick a running SQL warehouse
databricks warehouses list --profile <profile> | awk '$NF=="RUNNING"{print $1; exit}'
# Then for each query:
databricks api post /api/2.0/sql/statements --profile <profile> --json '{
  "warehouse_id": "<id>",
  "statement": "<sql>",
  "wait_timeout": "50s"
}'
```

For multi-query analysis, write a Python heredoc that wraps this in a `run_sql()` function. The `wait_timeout` must be 5–50s (NOT lower, NOT higher).

---

**Step 1 — SOX schema enforcement (mandatory).**

Only schemas with `sox` in the schema name are valid sources for SOX pipelines. Before querying any source table:

```sql
SHOW SCHEMAS;
```

Filter to schemas containing `sox`. For each candidate source table the JIRA ticket references, verify there is a SOX-equivalent schema. For example, if the ticket lists `ued_loanpro_prd_dwh.loan_tx`, look for `ued_loanpro_sox_*` or `ued_pmt_psdtm_sox_dwh.*` containing the same logical table. Use the SOX schema as the source.

**If a non-SOX schema is referenced and no SOX equivalent exists, flag it for engineer review and ask before proceeding.** Never proceed silently with a non-SOX schema.

---

**Step 2 — Source row counts and monthly distribution (drives partition decision).**

For the primary SOX source table — never the existing Gold/DM table — run:
```sql
SELECT COUNT(*) AS total_rows FROM <sox_schema>.<primary_source_table>;

SELECT date_trunc('month', <date_col>) AS mo, COUNT(*) AS rows
FROM <sox_schema>.<primary_source_table>
GROUP BY 1 ORDER BY 1 DESC LIMIT 24;
```

Apply thresholds:
- `< 10M rows`     → `partition_needed: false`
- `10M – 100M`     → `partition_needed: true`, partition by date column (month)
- `> 100M`         → `partition_needed: true`, partition by date + optional categorical

**Forbidden inputs to the partition decision** (do not even query these):
- ❌ Any existing Gold, Silver, or DM table — including row counts and date distributions from them
- ❌ Any reference conf from a similar pipeline
- ❌ Whether the source SQL has a partitioning clause
- ❌ Output volume estimated from running the source SQL itself (this is forbidden — only raw source table COUNTs are allowed)
- ❌ Engineer preference (unless explicitly stated in the JIRA ticket)

If Databricks is unreachable, **stop Phase 2** — do not proceed to Checkpoint 1 without live source row counts.

---

**Step 3 — Identify all CDC sources and their CDC columns.**

For every source table in the source SQL (joined or unioned), DESCRIBE it and identify its CDC column. Write the result to `cdc_sources: [{table, cdc_column, distinct_days_in_last_year}, ...]`. Verify CDC viability:

```sql
SELECT MIN(<cdc_col>), MAX(<cdc_col>), COUNT(DISTINCT to_date(<cdc_col>)) AS distinct_days
FROM <sox_schema>.<table>
WHERE <cdc_col> >= add_months(current_date(), -12);
```

A table is a viable CDC source if `distinct_days >= 30` over the last 12 months. If ANY table has a viable CDC column, write_mode MUST be `incremental`. Full-refresh is only allowed when no source table has any viable CDC column, OR when JIRA explicitly requires full-refresh.

---

**Step 4 — Grain and PK.**

Determine the grain (lowest unique key) by running a uniqueness check on candidate PK columns. The PK expression for the DM target MUST be a URN concat:
```
pk_expression = "concat('urn:intuit:<domain>:<object>#', <pk_col>)"
```
For example, for QBC loan repayment transactions: `concat('urn:intuit:qbc:loan-repayment-transaction#', transactionId)`. Never use a bare column name as the PK expression.

---

**Step 5 — Fetch source SQL from GitHub** if a URL is in the ticket: use `mcp__github__get_file_contents`.

**Step 6 — Invoke `source-analyzer`** sub-agent with all pre-fetched data in the prompt. It returns the analysis report.

**Step 7 — Increment `analysis_rounds` and present Checkpoint 1.** Show: write_mode + justification, cdc_sources table, partition decision + thresholds, grain, URN-formatted pk_expression, source row counts. On no-go, collect feedback and re-run.

### Phase 3 — DM Build

**Branch creation (do this BEFORE invoking dm-builder):**
1. `git fetch origin`
2. Find the project branch matching the lowercased domain — must be a bare branch like `origin/qbc`, `origin/loss-reserve`, `origin/capital` — NOT a feature branch that happens to contain the domain name.
3. Cut the feature branch: ensure working tree is clean (commit/stash any pending changes — surface to engineer first), then `git checkout origin/<project_branch>` then `git checkout -b <JIRA-KEY>`. Set `parent_branch` and `branch` in session state. After the first commit on the new branch, push it: `git push -u origin <JIRA-KEY>`.
4. If the project branch does not exist, stop and ask the engineer which parent branch to use.

**Then invoke dm-builder:**
Invoke `dm-builder` with source analysis report + reference conf path. The sub-agent reads/writes local conf files on the new feature branch. Update `dm_conf_path`. The DM conf must implement the multi-table CDC pattern from the analysis report (UNION DISTINCT primary keys across all `cdc_sources`).

### Phase 4 — DM BPP Registration (manual pause)
Invoke `bpp-registrar` with DM details. ⏸ Engineer registers in DAST-Orch UI and confirms. Set `dm_pipeline_name`, `dm_execution_type`.

### Phase 5 — DM Job Run
**Run entirely in the parent session — do NOT delegate to bpp-runner sub-agent.** Sub-agents cannot reliably load deferred BPP MCP tools.

1. Use `ToolSearch("execute pipeline bpp")` to load the `execute_pipeline` tool. Call it with `pipeline_name=dm_pipeline_name`, env=sandbox.
2. Capture the returned execution/run ID → save as `dm_run_id` in session state.
3. Poll using `ToolSearch("pipeline execution history bpp")` → `get_pipeline_execution_history` with `pipeline_name=dm_pipeline_name`, `limit=1`. Wake-up schedule: 0–5 min: 90s; 5–30 min: 240s; 30min+: 900s. Terminal states: `SUCCESS`, `SUCCEEDED`, `FAILED`, `ERROR`, `CANCELLED`.
4. **On success:** record duration, proceed to Phase 6.
5. **On failure — pull EMR logs automatically:**
   - `ToolSearch("get execution details emr")` → `get_execution_details` with `execution_id=dm_run_id` + `execution_type=dm_execution_type`. Extract `aws_account_id`, `application_id`, `job_run_id` (EMR_SERVERLESS) or `cluster_id`, `step_id` (EMR_EC2).
   - `ToolSearch("debug emr pipeline jobs")` → `debug_emr_pipeline_jobs` with those IDs + `additional_context="DM pipeline {dm_pipeline_name} failed. JIRA: {jira_id}"`.
   - Surface the full diagnostic (exception, stack trace excerpt, recommendations) to the engineer before attempting any fix.

### Phase 6 — Unit Test
Pre-fetch row counts and column-match SQL results from Databricks. Invoke `unit-tester` with results. Auto-fix loop: if FAIL, invoke `dm-builder` in fix mode, re-run bpp-runner, re-test. Max 2 retries.

**Checkpoint 2:** present DM build + unit test results. go / request changes / stop.

### Phase 7 — SOX Metadata Entry (manual pause)

**Step 1 — Ask for the DQ JIRA ticket number.**
The DQ pipeline has its own JIRA ticket (separate from the DM build ticket). Prompt the engineer:
```
⏸ Phase 7: SOX Metadata Entry

Before I build the DQ conf I need the DQ JIRA ticket number.
The DQ ticket contains the registered BPP pipeline name and mandatory accuracy columns.

What is the DQ JIRA ticket number? (e.g. FIND-431)
```
Fetch that ticket immediately via `mcp__claude_ai_Atlassian__getJiraIssue`. Extract:
- `dq_pipeline_name` — the BPP pipeline name for the DQ job (e.g. `Intuit.data.finance.dqqbclploanrepaytxn`)
- `accuracy_cols` — the mandatory accuracy columns listed in the DQ ticket
- Any special DQ instructions or notes

Save both to session state. Do NOT ask the engineer to type these values manually — always fetch from the DQ JIRA ticket.

**Step 2 — Present metadata INSERT statements.**
Present the `rpt_sox_setup` + `rpt_sox_metadata` INSERT statements (with next available IDs fetched from Databricks) for the engineer to run manually in a notebook. Include a verification query they can run to confirm the entries exist.

**Step 3 — Wait for confirmation.**
Wait for the engineer to reply "metadata entered". Then verify the entries exist via Databricks before proceeding to Phase 8.

### Phase 8 — DQ Build
**Pre-verify metadata** — query Databricks to confirm `rpt_sox_setup` and `rpt_sox_metadata` rows exist for `setup_id`. Do not proceed if they are missing.

Invoke `dq-builder` with:
- `dq_pipeline_name` and `accuracy_cols` from the DQ JIRA ticket (fetched in Phase 7 Step 1)
- `setup_id` confirmed from Databricks
- source analysis report and DM conf path from session state

Update `dq_conf_path`, `setup_id`, `dq_pipeline_name`, `accuracy_cols` in session state.

### Phase 9 — DQ BPP Registration (manual pause)
Invoke `bpp-registrar` for DQ. ⏸ Engineer registers and confirms. Set `dq_bpp_pipeline_name`, `dq_execution_type`.

**Checkpoint 3:** DQ conf review. yes / request changes / stop.

### Phase 10 — DQ Job Run
**Run entirely in the parent session — do NOT delegate to bpp-runner sub-agent.**

1. `ToolSearch("execute pipeline bpp")` → `execute_pipeline` with `pipeline_name=dq_bpp_pipeline_name`, env=sandbox. Capture `dq_run_id`.
2. Poll with `get_pipeline_execution_history` using same wake-up schedule as Phase 5.
3. **On failure:** same 3-step EMR log chain as Phase 5 — `get_execution_details` → `debug_emr_pipeline_jobs` → surface diagnostic. Return to dq-builder fix loop or escalate after 2 retries.

### Phase 11 — SOX Validation
Pre-fetch validation queries from Databricks: completeness from `rpt_sox_completeness`, accuracy from `rpt_sox_accuracy`, late-arriving from source table. Invoke `dq-validator` with all results. Auto-fix loop: if FAIL, dq-builder fix → bpp-runner → re-validate. Max 2 retries.

**Checkpoint 4:** validation results. approve / investigate / stop.

### Phase 12 — PR Creation
Use `mcp__github__create_pull_request` with dm + dq conf changes on the JIRA branch.

### Phase 13 — JIRA Close-out
Invoke `jira-updater` (after pre-fetching transitions via `mcp__claude_ai_Atlassian__getTransitionsForJiraIssue`). Post final results comment via `mcp__claude_ai_Atlassian__addCommentToJiraIssue`. Transition ticket via `mcp__claude_ai_Atlassian__transitionJiraIssue`.

### Phase 14 — Code Annotation (SOX code review spreadsheet)

After JIRA close-out, generate the per-line annotation spreadsheet for SOX code review. The annotation is for the **DM conf** by default — the DM conf contains the business logic that the Product Owner (PO) and SOX reviewer evaluate; the DQ conf is a standardized validation framework and typically doesn't need PO sign-off line-by-line.

**Steps:**

1. **Ask the engineer two questions:**
   ```
   📝 Phase 14 — Code Annotation
   
   1. Which conf(s) should I annotate?
      [a] DM conf only (default, recommended)
      [b] DQ conf only
      [c] Both DM and DQ
   
   2. Target xlsx file?
      [Enter to use default: ~/Downloads/Annotation Sample.xlsx]
      Or provide a different path.
   ```

2. **For each conf the engineer chose**, derive the inputs from session state:
   - `conf_path` = `dm_conf_path` or `dq_conf_path`
   - `xlsx_path` = engineer's choice (default: `~/Downloads/Annotation Sample.xlsx`)
   - `sheet_name` = `table_name` (DM) or `dq_<table_name>` (DQ), abbreviated to fit Excel's 31-char limit using the rules in `code-annotator.md` (e.g., `_loanpro_` → `_lp_`, `_transaction` → `_txn`). Confirm the abbreviated name with the engineer if shortening was applied.
   - `developer` = JIRA assignee, falling back to `git config user.name`
   - `report_name` = conf basename (e.g. `qbc_loanpro_loan_repayment_transaction.conf`)
   - `brief_overview` = 2-4 sentence summary built from session state: write_mode, source schemas, primary key, target table, multi-table CDC details

3. **Invoke the `code-annotator` sub-agent** with all the inputs above. The sub-agent runs the script at `${CLAUDE_PLUGIN_ROOT}/scripts/generate_annotation.py` to produce the annotated sheet.

4. **Verify the output:**
   ```bash
   python3 -c "import openpyxl; wb=openpyxl.load_workbook('<xlsx>'); print('Sheets:', wb.sheetnames)"
   ```

5. **Confirm to the engineer:**
   ```
   ✅ Annotation sheet(s) written to <xlsx_path>
      Sheets added: <sheet_name(s)>
      Open the file in Excel/Numbers to review and fill in the PO Notes column.
   ```

This phase is **not** gated by an engineer checkpoint — it's a deterministic post-step. But the engineer can skip it by answering "skip" to question 1.

---

## Behavioral rules

- **Drive the workflow inline** — never invoke the `orchestrator` sub-agent. It cannot access MCP tools properly.
- Pre-fetch all MCP data in the parent session, then pass to sub-agents as input.
- Manual pauses (Phases 4, 7, 9) are indefinite — wait for engineer.
- Auto-fix loops: max 2 retries each (DM unit test, DQ validation).
- Never execute destructive actions (BPP runs, git push, JIRA transitions, PR creation) without explicit engineer approval.
- Post a brief progress message at the start of each phase.
- Show session context at each of the 4 checkpoints.

---

## Start now

Begin Phase 1. The first action is to fetch the JIRA ticket for **$ARGUMENTS** via the Atlassian MCP, then invoke `jira-intake` with that data.

If `$ARGUMENTS` is empty, ask the engineer for a JIRA key before starting.
