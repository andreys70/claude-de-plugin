# Verification — <TICKET-KEY>

## Environment
- **Commit verified:** <SHA> (committed at <commit_time>)
- **Target table refresh:** <max_ts> — ✅ POST-commit
- **Total rows:** <count>

## Check 1 — <primary metric>
<table with month-by-month pre/post, include historical baseline>

**Verdict:** ✅ fix confirmed / ❌ fix did not take effect / ⚠️ partial

## Check 2 — Refresh
Already verified in Environment section.

## Check 3 — Row count parity
<table comparing PRF and stable, or between expected and actual>

**Verdict:** <✅/❌>

## Check 4 — Spot-check vs source
<10-row sample table showing fixed_column vs source_column, with OK/MISMATCH>

**Verdict:** N/10 OK

## Check 5 — Cardinality
<table: total_rows vs distinct_key, per month>

**Verdict:** <✅/❌ duplicates introduced?>

## Check 6 — Downstream impact (if applicable)
<table showing pre/post on downstream metric, ideally with a control group>

**Verdict:** <✅/❌>

## Overall
<One sentence: fix confirmed end-to-end / concerns / blockers>
