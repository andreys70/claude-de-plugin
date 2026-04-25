# Verification — <TICKET-KEY or spec name>

**Mode:** <anomaly-resolved | acceptance-criteria | first-run-healthy>

## Environment
- **Reference time:** <commit SHA + commit_time, or first-run trigger time>
- **Target table refresh:** <max_ts> — ✅ POST-reference / ❌ STALE
- **Total rows:** <count>

> Pick the section below that matches the mode. Use that section as the report body. Delete the other two.

---

## Mode A — anomaly-resolved (fix flow)

### Check A.1 — <primary metric>
<table with month-by-month pre/post, include historical baseline>

**Verdict:** ✅ fix confirmed / ❌ fix did not take effect / ⚠️ partial

### Check A.2 — Refresh
Already verified in Environment section.

### Check A.3 — Row count parity
<table comparing PRF and stable, or pre vs post-fix window>

**Verdict:** <✅/❌>

### Check A.4 — Spot-check vs source
<10-row sample table showing fixed_column vs source_column, with OK/MISMATCH>

**Verdict:** N/10 OK

### Check A.5 — Cardinality
<table: total_rows vs distinct_key, per month>

**Verdict:** <✅/❌ duplicates introduced?>

### Check A.6 — Downstream impact (if applicable)
<table showing pre/post on downstream metric, ideally with a control group>

**Verdict:** <✅/❌>

### Overall
<One sentence: fix confirmed end-to-end / concerns / blockers>

---

## Mode B — acceptance-criteria (enhancement flow)

### Acceptance criteria

| # | Criterion | Query | Result | Verdict |
|---|---|---|---|---|
| 1 | <criterion text from Jira> | <ref to B.1/B.2/custom> | <row count returned, or actual vs expected> | ✅ pass / ❌ fail / ⚠️ unable to test |
| 2 | <criterion text> | ... | ... | ... |
| ... | | | | |

### Regression spot-check (Check B.3)
<table showing pre vs post window for an unrelated column or population>

**Verdict:** ✅ no regression / ❌ unexpected change in <col>

### Row count sanity
<actual count and expected range>

**Verdict:** ✅ within expected / ⚠️ unexpected drop or spike (<details>)

### Refresh
Already verified in Environment section.

### Overall
<One sentence: all acceptance criteria pass, no regression / N criteria pass, M fail / blockers>

---

## Mode C — first-run-healthy (create flow)

### Check C.1 — Table exists + schema matches spec

**Table exists:** ✅ / ❌

**Schema diff vs spec:**

| Column | Spec | Actual | Match |
|---|---|---|---|
| <col> | <type, nullable?> | <type, nullable?> | ✅ / ❌ |
| ... | | | |

**Verdict:** ✅ schema matches / ❌ <N missing, M extra, K type mismatches>

### Check C.2 — Non-zero rows
<total row count>

**Verdict:** ✅ non-empty / ❌ empty (spec did not allow empty first run)

### Check C.3 — Required columns NOT NULL
<table: each required column → null_count, pct_null, verdict>

**Verdict:** ✅ all required columns populated within tolerance / ❌ <col(s)> exceed tolerance

### Check C.4 — No duplicates on primary key
<total_rows, distinct_keys, duplicates>

**Verdict:** ✅ unique / ❌ <N duplicates>

### Check C.5 — Row count order of magnitude (if spec gave an estimate)
<actual / expected / ratio>

**Verdict:** ✅ within order of magnitude / ⚠️ <ratio> — usually means a join is wrong

### Refresh
Already verified in Environment section.

### Overall
<One sentence: first run healthy, schema and data both as specified / N checks pass, M fail / blockers>
