---
description: Generate per-line code annotation spreadsheets for DM/DQ conf files in the standard SOX code review template. Always takes a JIRA key — reads all pipeline details from the ticket, annotates every listed conf, uploads the finished xlsx to JIRA, and closes the ticket after customer approval. Domain-agnostic.
argument-hint: <JIRA-KEY>
---

You are running the **code annotation** workflow. JIRA key: **$ARGUMENTS**

---

## Input

The only argument is a JIRA key (e.g. `FIND-430`, `STCRF-337`). **All other information comes from the ticket** — pipeline list, git repo path, local repo root, output xlsx path, developer name. There are no additional flags.

If `$ARGUMENTS` does not match `[A-Z]+-[0-9]+`, print an error and stop:
```
❌ Expected a JIRA key (e.g. FIND-430). Usage: /auditpath:annotate <JIRA-KEY>
```

> **Note for the onboarding flow (Phase 14):** When this command is invoked programmatically from within `/auditpath:onboard`, the orchestrator passes conf details directly to the `code-annotator` sub-agent — it does not go through this command. This command is the standalone entry point only.

---

## Step 0 — Resolve plugin paths (do this FIRST, before anything else)

This plugin bundles its runtime script — you do NOT need to write, generate, or rebuild any helper code. The script and the `code-annotator` agent are part of the installed plugin.

**Resolve the plugin root once, store it as a variable, and reuse for the rest of the run:**

```bash
# CLAUDE_PLUGIN_ROOT is set automatically when this command runs from an
# installed plugin. Try it first.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"

# Fallback chain (in order) — these are the standard installed locations:
if [ -z "$PLUGIN_ROOT" ] || [ ! -f "$PLUGIN_ROOT/scripts/generate_annotation.py" ]; then
  for candidate in \
    "$HOME/.claude/auditpath-marketplace/auditpath" \
    "$HOME/.claude/plugins/cache/intuit-de-plugins/auditpath/0.1.0" \
    "$HOME/.claude/plugins/installed/auditpath" \
    "$(find "$HOME/.claude/plugins" -name generate_annotation.py 2>/dev/null | head -1 | xargs dirname 2>/dev/null | xargs dirname 2>/dev/null)" \
  ; do
    if [ -f "$candidate/scripts/generate_annotation.py" ]; then
      PLUGIN_ROOT="$candidate"
      break
    fi
  done
fi

if [ -z "$PLUGIN_ROOT" ] || [ ! -f "$PLUGIN_ROOT/scripts/generate_annotation.py" ]; then
  echo "❌ Cannot locate auditpath plugin. Run 'claude plugin list' to verify installation."
  exit 1
fi

SCRIPT="$PLUGIN_ROOT/scripts/generate_annotation.py"
echo "✅ Using plugin at: $PLUGIN_ROOT"
echo "✅ Script: $SCRIPT"
```

After this block, **always use `$SCRIPT`** (or the literal `"$PLUGIN_ROOT/scripts/generate_annotation.py"`) in Phase 1 and Phase 2 calls. **Never** try to discover the script ad-hoc later, and **never** rebuild any logic that the script already provides — the script is the single source of truth for skeleton generation, context extraction, and annotation merging.

If `openpyxl` is missing on the system, install it once before proceeding:
```bash
python3 -c "import openpyxl" 2>/dev/null || pip3 install openpyxl --break-system-packages --quiet
```

---

## Step 1 — Fetch JIRA ticket

Use `mcp__bc13de2d__getJiraIssue` with the JIRA key. Extract the following fields (all sourced from the ticket — never prompt the engineer for these):

| Field | Where to find it | Default if absent |
|-------|-----------------|-------------------|
| `jira_id` | The key itself | — |
| `summary` | Ticket title | — |
| `reporter` | `reporter.displayName` | — |
| `pipeline_list` | Bullet list of `.conf` paths in description, comments, or acceptance criteria | — (see below) |
| `git_folder_url` | GitHub directory URL in description (e.g. `https://github.intuit.com/.../configs/finance_mm_dm/loss_reserve`) | — (see below) |
| `local_repo_root` | Explicit path in description (look for `Local repo root:` or similar) | `/Users/pkurup/Intuit/git/quick-etl-pipeline-configs` |
| `xlsx_path` | Explicit path in description (look for `Output file:` or similar) | `~/Downloads/<jira_id>_Annotation.xlsx` |
| `developer` | Assignee `displayName` field, or `reporter.displayName` | `git config user.name` output |

**Resolving the pipeline list** (try in order):

1. Look for a bullet/numbered list of `.conf` paths in the ticket description
2. Look in ticket comments for a list of `.conf` files
3. If a `git_folder_url` is present (a GitHub directory link), use `mcp__github__get_file_contents` on that path to list all `.conf` files in the folder — treat them all as the pipeline list
4. If none of the above yields a list → post a comment on the ticket and stop (see below)

**If pipeline list cannot be resolved**, post via `mcp__bc13de2d__addCommentToJiraIssue`:
```
Hi @<reporter>,

To proceed with code annotation I need to know which conf files to document. Please update this ticket with one of:

**Option A** — List the conf files directly:
## Pipelines to annotate
- configs/finance_mm_dm/loss_reserve/dim_money_profile.conf
- configs/finance_mm_dm/loss_reserve/fact_loss_reserve_ach_txn.conf

**Option B** — Provide a GitHub directory URL (all .conf files in that folder will be annotated):
GitHub folder: https://github.intuit.com/data-finance/quick-etl-pipeline-configs/tree/master/configs/finance_mm_dm/loss_reserve

**Optional fields** (defaults shown):
- Local repo root: /Users/pkurup/Intuit/git/quick-etl-pipeline-configs
- Output file: ~/Downloads/<jira_id>_Annotation.xlsx

*AuditPath code-annotator is paused waiting for this information.*
```
Then stop. Do not proceed further until the ticket is updated and the command is re-invoked.

---

## Step 2 — Resolve conf file paths

For each entry in `pipeline_list`:
- If the path is relative, prepend `local_repo_root`
- Verify the file exists: `test -f <path> && echo OK || echo MISSING`
- If any file is MISSING, surface the list and ask the engineer in the chat whether to skip those files or stop

---

## Step 3 — Annotate all pipelines

For each conf file (in order):

**3a. Derive sheet name** from conf basename (max 31 chars — Excel limit). Apply these abbreviations in order:
- `fact_loss_reserve_` → `flr_`
- `dim_money_profile_outrigger` → `dmp_outrigger`
- `dim_money_profile` → `dim_money_profile` (already ≤31)
- `_loanpro_` → `_lp_`
- `_transaction` → `_txn`
- `_allocation` → `_alloc`
- `_repayment` → `_repay`
- `_billpay` → `_bp`
- `_collection` → `_coll`
- `_monetary` → `_mon`
- `_conformed` → `_conf`
- `_chargeoff` → `_chgoff`
- `_chargeback` → `_chgbk`
- `_debt_` → `_debt_`

If still >31 chars after all abbreviations, truncate to 31 and note it in the progress output.

**3b. Infer the overview** from the conf file itself — read the first 50 lines looking for:
- The change history comment block (pipeline purpose often described there)
- The `pipeline { name = ... }` block
- Source table names in the first step's SQL

Construct a 2-3 sentence overview: `"<pipeline_name> — builds the <table_name> <DM|SOX DQ> table for <domain>. Sources from <source_tables>. Write mode: <full_refresh|incremental>."` If write mode cannot be determined, omit that sentence.

**3c. Run Phase 1 skeleton** (use `$SCRIPT` from Step 0):
```bash
python3 "$SCRIPT" skeleton \
  --conf "<conf_path>" \
  --xlsx "<xlsx_path>" \
  --sheet "<sheet_name>" \
  --report-name "<conf_basename_no_ext>" \
  --overview "<inferred_overview>" \
  --developer "<developer>" \
  --context-out "/tmp/<sheet_name>_context.json"
```

**3d. Invoke `code-annotator` sub-agent** with the full conf content and context JSON pre-loaded in the prompt. The sub-agent writes `/tmp/<sheet_name>_annotations.json`. (It also uses `$SCRIPT` internally via `${CLAUDE_PLUGIN_ROOT}/scripts/generate_annotation.py` — no need to pass anything extra.)

**3e. Run Phase 2 merge:**
```bash
python3 "$SCRIPT" merge \
  --xlsx "<xlsx_path>" \
  --sheet "<sheet_name>" \
  --annotations "/tmp/<sheet_name>_annotations.json"
```

**3f. Print progress:**
```
✅ [N/total] <sheet_name> — <line_count> lines annotated
```

**Post a JIRA progress comment after every 3 pipelines** (use `mcp__bc13de2d__addCommentToJiraIssue`):
```
🔄 Annotation progress: N/total pipelines complete.
Last completed: <sheet_name> (<line_count> lines)
Currently working on: <next_pipeline_name>
```

---

## Step 4 — Upload xlsx to JIRA

After all pipelines are annotated, upload the xlsx to the ticket.

Try `mcp__bc13de2d__fetch` first with the Jira attachments endpoint:
```
POST https://jira.cloud.intuit.com/rest/api/3/issue/<jira_id>/attachments
Headers: X-Atlassian-Token: no-check, Content-Type: multipart/form-data
Body: file=@<xlsx_path>
```

If that fails (MCP does not support binary upload), use curl:
```bash
# Get JIRA token from environment or keychain
JIRA_TOKEN=$(security find-generic-password -a "$USER" -s "jira-api-token" -w 2>/dev/null || echo "")
if [ -n "$JIRA_TOKEN" ]; then
  curl -s -X POST \
    -H "Authorization: Bearer $JIRA_TOKEN" \
    -H "X-Atlassian-Token: no-check" \
    -F "file=@<xlsx_path>" \
    "https://jira.cloud.intuit.com/rest/api/3/issue/<jira_id>/attachments"
else
  echo "NO_TOKEN"
fi
```

If upload fails entirely (no token, network error), note it in the review comment: `⚠️ Automated upload failed — please attach \`<xlsx_filename>\` manually from: \`<xlsx_path>\``

---

## Step 5 — Post review-request comment

Use `mcp__bc13de2d__addCommentToJiraIssue`:

```
## 📋 Code Annotation Complete — Ready for Review

**Pipelines annotated:** <N>  
**Output file:** `<xlsx_filename>` (attached above)  
**Generated:** <today's date>

### Sheets included
| # | Sheet name | Conf file | Lines annotated |
|---|-----------|-----------|-----------------|
| 1 | <sheet_1> | <conf_1.conf> | <lines_1> |
| 2 | <sheet_2> | <conf_2.conf> | <lines_2> |
...

### How to review
1. Open the attached xlsx
2. Each sheet = one pipeline
3. **Column C** = source code line
4. **Column D** = Developer Notes (generated)
5. **Column E** = PO Notes ← fill these in
6. Reply to this comment:
   - **"Approved"** → annotation accepted, ticket will be closed
   - **"Changes requested: \<notes\>"** → feedback incorporated and re-submitted (max 2 rounds)

*Generated by AuditPath code-annotator — [feature/FIND-430-auditpath](https://github.intuit.com/data-finance/quick-etl-pipeline-configs/tree/feature/FIND-430-auditpath)*
```

---

## Step 6 — Wait for approval

Tell the engineer in the chat:
```
⏸  Review comment posted on <jira_id>. Reply here with:
   • "approved" — to close the ticket
   • "changes requested: <which pipelines and what to fix>" — to revise and resubmit
```

When the engineer replies:
- `"approved"` / `"looks good"` / `"LGTM"` / `"done"` → go to Step 7
- `"changes requested: <notes>"` → identify which pipelines need re-annotation, re-run Steps 3–5 for those pipelines only, then return to Step 6. Maximum 2 revision rounds. After 2 rounds, surface to engineer for manual resolution.

---

## Step 7 — Close JIRA ticket

1. `mcp__bc13de2d__getTransitionsForJiraIssue` — list available transitions
2. Find transition with name matching `Done` / `Closed` / `Resolved` (case-insensitive)
3. `mcp__bc13de2d__transitionJiraIssue` with that transition ID
4. Post final comment via `mcp__bc13de2d__addCommentToJiraIssue`:
   ```
   ✅ Annotation review approved and ticket closed.
   
   **Final artifact:** `<xlsx_filename>` (attached)  
   **Pipelines documented:** <N>  
   **Total lines annotated:** <sum>  
   **Completed:** <today's date>
   ```

---

## Shared reference

- **Script:** `${CLAUDE_PLUGIN_ROOT}/scripts/generate_annotation.py` — bundled with the plugin. Resolved by Step 0 above as `$SCRIPT`. **Do not rebuild it.**
- **code-annotator agent:** `${CLAUDE_PLUGIN_ROOT}/agents/code-annotator.md` — invoked via the `Agent` tool with `subagent_type: code-annotator`.
- **JIRA MCP:** `mcp__bc13de2d__*` tools (Atlassian)
- **GitHub MCP:** `mcp__github__get_file_contents` (for listing conf files from a GitHub folder URL)

## Plugin distribution note

This command and its dependencies (`generate_annotation.py`, the `code-annotator` sub-agent, the abbreviation rules, the JIRA comment templates) all live inside the `auditpath` plugin. Engineers who install the plugin via `claude plugin install auditpath@intuit-de-plugins` get the complete annotation toolkit — no separate script downloads, no path-discovery workarounds, no rebuilding logic at runtime.

## Use cases

- Bulk annotation of all pipelines in a domain for a SOX audit cycle
- Documentation requests filed by PO or auditor as a JIRA ticket
- Periodic refresh of annotation sheets when confs change

## Begin now

Fetch the JIRA ticket for **$ARGUMENTS** and start Step 1.
