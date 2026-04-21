-- Standard verification queries for data-issue-validator
-- Replace <placeholders> with real values before running.
--
-- Dialect: written in Databricks/Spark SQL. For Redshift/Snowflake/BigQuery,
-- DATE_TRUNC behavior and function names may differ slightly.

-- =============================================================
-- Check 0 — Freshness gate (refuse verification if stale)
-- =============================================================
-- Compare max_ts to the commit time of the fix SHA.
-- If max_ts < commit_time, STOP — table has not picked up the fix.
SELECT
  MAX(<last_modified_column>) AS max_ts,
  COUNT(*)                    AS total_rows,
  MIN(<last_modified_column>) AS min_ts
FROM <catalog>.<schema>.<table>;


-- =============================================================
-- Check 1 — Primary success metric (NULL% trend by month)
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
-- Check 3 — Row count parity (PRF vs stable)
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
-- Check 4 — Spot-check vs source-of-truth
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
-- Check 5 — Cardinality (no duplicates introduced by new join)
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
-- Check 6 — Downstream impact + control group
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
