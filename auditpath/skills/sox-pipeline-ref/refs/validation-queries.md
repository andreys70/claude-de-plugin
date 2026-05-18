# Validation Queries

Parameterized SQL queries used by the `validator` agent. Replace `{table}`, `{domain}`, `{source_table}`, `{date_col}`, `{start}`, `{end}`, `{dm_run_date}` at runtime.

---

## Completeness Check

```sql
SELECT
  TGT_TABLE_NAME,
  DOMAIN,
  START_DATE,
  END_DATE,
  SRC_METRIC_VALUE,
  TGT_METRIC_VALUE,
  SRC_METRIC_VALUE - TGT_METRIC_VALUE AS delta,
  MATCHED,
  LOAD_TS
FROM finance_sandbox.RPT_SOX_COMPLETENESS
WHERE TGT_TABLE_NAME = '{table}'
  AND DOMAIN         = '{domain}'
ORDER BY LOAD_TS DESC
LIMIT 1
```

**Pass:** `MATCHED = true`
**Tolerance:** `MATCHED = false` but delta fully explained by late-arriving data
**Fail:** Any other outcome — trigger auto-fix loop

---

## Accuracy Check

```sql
SELECT
  TGT_TABLE_NAME,
  DOMAIN,
  COUNT(*)        AS total_records,
  SUM(CASE WHEN MATCHED = true THEN 1 ELSE 0 END)  AS matched_count,
  SUM(CASE WHEN MATCHED = false THEN 1 ELSE 0 END) AS mismatched_count,
  ROUND(SUM(CASE WHEN MATCHED = true THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS match_pct,
  MIN(LOAD_TS) AS run_ts
FROM finance_sandbox.RPT_SOX_ACCURACY
WHERE TGT_TABLE_NAME = '{table}'
  AND DOMAIN         = '{domain}'
  AND DATE(LOAD_TS)  = DATE((SELECT MAX(LOAD_TS) FROM finance_sandbox.RPT_SOX_ACCURACY WHERE TGT_TABLE_NAME = '{table}'))
GROUP BY TGT_TABLE_NAME, DOMAIN
```

**Pass:** `mismatched_count = 0` (100% accuracy)
**Fail:** Any mismatches — run column-diff query below

---

## Column-Diff on Mismatched Records

```sql
SELECT
  ID,
  src_record,
  tgt_record
FROM finance_sandbox.RPT_SOX_ACCURACY
WHERE TGT_TABLE_NAME = '{table}'
  AND DOMAIN         = '{domain}'
  AND MATCHED        = false
  AND DATE(LOAD_TS)  = DATE((SELECT MAX(LOAD_TS) FROM finance_sandbox.RPT_SOX_ACCURACY WHERE TGT_TABLE_NAME = '{table}'))
LIMIT 20
```

---

## Late-Arriving Data Analysis

```sql
SELECT
  to_date(ingest_date)          AS ingest_date,
  COUNT(*)                      AS row_count
FROM {source_table}
WHERE to_date({date_col}) BETWEEN '{start}' AND '{end}'
  AND to_date(ingest_date) > '{dm_run_date}'
GROUP BY 1
ORDER BY 1
```

**Interpretation:**
- `SUM(row_count) >= delta` — delta fully explained by late-arriving data — Expected Tolerance (pass with note)
- `SUM(row_count) < delta` — genuine mismatch — trigger auto-fix loop

---

## SOX Setup Validation (pre-run check)

```sql
SELECT RPT_SOX_SETUP_ID, TABLE_NAME, START_DATE, END_DATE, ACTIVE_FLAG
FROM finance_mm_sandbox.RPT_SOX_SETUP
WHERE TABLE_NAME = '{table}' AND ACTIVE_FLAG = true
```

If no rows returned — setup INSERT was not executed — block DQ job and alert engineer.
