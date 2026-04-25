-- Standard verification queries for data-validator
-- Replace <placeholders> with real values before running.
--
-- Dialect: written in Databricks/Spark SQL. For Redshift/Snowflake/BigQuery,
-- DATE_TRUNC behavior and function names may differ slightly.
--
-- Three sections, one per validator mode:
--   Section A — anomaly-resolved (fix flow)
--   Section B — acceptance-criteria (enhancement flow)
--   Section C — first-run-healthy (create flow)
-- Plus a shared Check 0 (freshness gate) used by all modes.

-- =============================================================
-- Check 0 — Freshness gate (refuse verification if stale) — ALL MODES
-- =============================================================
-- Compare max_ts to the commit time of the fix SHA.
-- If max_ts < commit_time, STOP — table has not picked up the fix.
SELECT
  MAX(<last_modified_column>) AS max_ts,
  COUNT(*)                    AS total_rows,
  MIN(<last_modified_column>) AS min_ts
FROM <catalog>.<schema>.<table>;


-- =============================================================
-- ============== SECTION A — anomaly-resolved (fix) ===========
-- =============================================================

-- =============================================================
-- A.1 — Primary success metric (NULL% trend by month)
-- =============================================================
-- Include historical baseline (pre-anomaly) months to show the target.
SELECT
  DATE_TRUNC('MONTH', <partition_date_col>) AS month,
  COUNT(*)                                  AS total_rows,
  SUM(CASE WHEN <metric_col> IS NULL THEN 1 ELSE 0 END) AS null_count,
  ROUND(100.0 * SUM(CASE WHEN <metric_col> IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_null
FROM <catalog>.<schema>.<table>
WHERE <partition_date_col> >= '<baseline_start>'
GROUP BY DATE_TRUNC('MONTH', <partition_date_col>)
ORDER BY month;


-- =============================================================
-- A.3 — Row count parity (PRF vs stable)
-- =============================================================
WITH prf AS (
  SELECT DATE_TRUNC('MONTH', <partition_date_col>) AS month, COUNT(*) AS prf_rows
  FROM <prf_catalog>.<schema>.<table>
  WHERE <partition_date_col> >= '<start_date>'
  GROUP BY DATE_TRUNC('MONTH', <partition_date_col>)
),
stbl AS (
  SELECT DATE_TRUNC('MONTH', <partition_date_col>) AS month, COUNT(*) AS stable_rows
  FROM <stable_catalog>.<schema>.<table>
  WHERE <partition_date_col> >= '<start_date>'
  GROUP BY DATE_TRUNC('MONTH', <partition_date_col>)
)
SELECT
  COALESCE(p.month, s.month) AS month,
  COALESCE(p.prf_rows, 0)    AS prf_rows,
  COALESCE(s.stable_rows, 0) AS stable_rows,
  COALESCE(p.prf_rows, 0) - COALESCE(s.stable_rows, 0) AS diff
FROM prf p
FULL OUTER JOIN stbl s ON p.month = s.month
ORDER BY month;


-- =============================================================
-- A.4 — Spot-check vs source-of-truth
-- =============================================================
-- Pick rows where the fixed column is now populated and verify against source.
-- Adjust the INNER JOIN to the actual source table/key for your case.
SELECT
  t.<row_id>,
  t.<bridge_col>,
  t.<fixed_col>                            AS target_value,
  s.<source_col>                           AS source_value,
  CASE WHEN t.<fixed_col> = s.<source_col>
       THEN 'OK' ELSE 'MISMATCH' END       AS check_result
FROM <catalog>.<schema>.<table> t
INNER JOIN <source_catalog>.<source_schema>.<source_table> s
  ON s.<source_key> = t.<bridge_col>
 AND <any additional source filters>
WHERE t.<partition_date_col> BETWEEN '<sample_start>' AND '<sample_end>'
  AND t.<fixed_col> IS NOT NULL
LIMIT 10;


-- =============================================================
-- A.5 — Cardinality (no duplicates introduced by new join)
-- =============================================================
SELECT
  DATE_TRUNC('MONTH', <partition_date_col>) AS month,
  COUNT(*)                                  AS total_rows,
  COUNT(DISTINCT <primary_key>)             AS distinct_key,
  COUNT(*) - COUNT(DISTINCT <primary_key>)  AS duplicates
FROM <catalog>.<schema>.<table>
WHERE <partition_date_col> >= '<post_fix_start>'
GROUP BY DATE_TRUNC('MONTH', <partition_date_col>)
ORDER BY month;


-- =============================================================
-- A.6 — Downstream impact + control group
-- =============================================================
-- Run on the downstream table. Include a "control" attribute/column
-- that should NOT have moved, to prove the effect is attributable
-- to the fix and not an unrelated pipeline shift.
SELECT
  DATE(<snapshot_col>)      AS snapshot_date,
  <attribute_col>,
  COUNT(*)                  AS row_count
FROM <downstream_catalog>.<downstream_schema>.<downstream_table>
WHERE <snapshot_col> >= '<pre_fix_start>'
  AND <attribute_col> IN (
    '<affected_attribute_1>',   -- should change post-fix
    '<affected_attribute_2>',   -- should change post-fix
    '<control_attribute>'       -- should be UNCHANGED — the control
  )
GROUP BY DATE(<snapshot_col>), <attribute_col>
ORDER BY snapshot_date, <attribute_col>;


-- =============================================================
-- ========= SECTION B — acceptance-criteria (enhancement) =====
-- =============================================================
-- Enhancement validation works per acceptance criterion. Each criterion
-- becomes its own query. The skeletons below are the most common shapes;
-- adapt or compose them per criterion.

-- =============================================================
-- B.1 — Column-is-populated-when-condition criterion
-- =============================================================
-- "Column <col> must be populated for all rows where <condition>."
-- Returns 0 rows on success; any rows returned are violations.
SELECT
  <primary_key>,
  <partition_date_col>,
  <col>,
  <condition_witness_cols>
FROM <catalog>.<schema>.<table>
WHERE <condition>
  AND <col> IS NULL
  AND <partition_date_col> >= '<post_change_start>'
LIMIT 50;


-- =============================================================
-- B.2 — Aggregate-matches-source criterion
-- =============================================================
-- "Daily total of <metric> in target must match source within <tolerance>."
WITH target_daily AS (
  SELECT DATE(<partition_date_col>) AS d, SUM(<metric>) AS target_sum
  FROM <catalog>.<schema>.<table>
  WHERE <partition_date_col> >= '<post_change_start>'
  GROUP BY DATE(<partition_date_col>)
),
source_daily AS (
  SELECT DATE(<source_date_col>) AS d, SUM(<source_metric>) AS source_sum
  FROM <source_catalog>.<source_schema>.<source_table>
  WHERE <source_date_col> >= '<post_change_start>'
  GROUP BY DATE(<source_date_col>)
)
SELECT
  COALESCE(t.d, s.d)                      AS d,
  t.target_sum,
  s.source_sum,
  ABS(t.target_sum - s.source_sum)        AS abs_diff,
  ROUND(100.0 * ABS(t.target_sum - s.source_sum) / NULLIF(s.source_sum, 0), 4) AS pct_diff
FROM target_daily t
FULL OUTER JOIN source_daily s ON t.d = s.d
ORDER BY d;


-- =============================================================
-- B.3 — Behavior-only-changed-where-expected (regression spot-check)
-- =============================================================
-- For an unrelated column or row population that should NOT have moved,
-- compare pre-change and post-change windows. Diffs flag accidental
-- regression.
WITH pre AS (
  SELECT
    DATE_TRUNC('MONTH', <partition_date_col>) AS month,
    SUM(CASE WHEN <unrelated_col> IS NULL THEN 1 ELSE 0 END) AS null_count,
    COUNT(*)                                                AS total
  FROM <catalog>.<schema>.<table>
  WHERE <partition_date_col> BETWEEN '<pre_start>' AND '<pre_end>'
  GROUP BY DATE_TRUNC('MONTH', <partition_date_col>)
),
post AS (
  SELECT
    DATE_TRUNC('MONTH', <partition_date_col>) AS month,
    SUM(CASE WHEN <unrelated_col> IS NULL THEN 1 ELSE 0 END) AS null_count,
    COUNT(*)                                                AS total
  FROM <catalog>.<schema>.<table>
  WHERE <partition_date_col> BETWEEN '<post_start>' AND '<post_end>'
  GROUP BY DATE_TRUNC('MONTH', <partition_date_col>)
)
SELECT 'pre' AS window, * FROM pre
UNION ALL
SELECT 'post' AS window, * FROM post
ORDER BY window, month;


-- =============================================================
-- ========== SECTION C — first-run-healthy (create) ===========
-- =============================================================

-- =============================================================
-- C.1 — Table exists + schema introspection
-- =============================================================
-- Run once. If the DESCRIBE errors, the pipeline didn't create the table.
DESCRIBE TABLE <catalog>.<schema>.<table>;

-- Schema-as-rows for diffing against the spec:
SELECT column_name, data_type, is_nullable
FROM <catalog>.information_schema.columns
WHERE table_schema = '<schema>'
  AND table_name   = '<table>'
ORDER BY ordinal_position;


-- =============================================================
-- C.2 — Non-zero rows
-- =============================================================
SELECT COUNT(*) AS total_rows
FROM <catalog>.<schema>.<table>;
-- Fail if total_rows = 0 (unless the spec explicitly allows empty first run).


-- =============================================================
-- C.3 — Required-column NULL% (for each column the spec marks "must populate")
-- =============================================================
-- Run once per required column. Flag if pct_null > 1% (or whatever the
-- spec specifies as the tolerance for that column).
SELECT
  '<required_col>' AS col,
  COUNT(*)         AS total_rows,
  SUM(CASE WHEN <required_col> IS NULL THEN 1 ELSE 0 END) AS null_count,
  ROUND(100.0 * SUM(CASE WHEN <required_col> IS NULL THEN 1 ELSE 0 END) / COUNT(*), 4) AS pct_null
FROM <catalog>.<schema>.<table>;


-- =============================================================
-- C.4 — No obvious duplicates on the spec's primary key
-- =============================================================
SELECT
  COUNT(*)                          AS total_rows,
  COUNT(DISTINCT <primary_key>)     AS distinct_keys,
  COUNT(*) - COUNT(DISTINCT <primary_key>) AS duplicates
FROM <catalog>.<schema>.<table>;


-- =============================================================
-- C.5 — Row-count order of magnitude (when the spec gives an estimate)
-- =============================================================
-- Compare the actual count to the spec's expected order of magnitude.
-- Specifically flag when actual is < 10% or > 10x of expected — usually
-- means a join key is wrong or a filter is missing.
SELECT
  COUNT(*)                            AS actual_rows,
  <expected_rows>                     AS expected_rows,
  ROUND(1.0 * COUNT(*) / NULLIF(<expected_rows>, 0), 3) AS ratio_actual_to_expected
FROM <catalog>.<schema>.<table>;
