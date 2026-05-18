# SOX DQ Pipeline Patterns

The SOX DQ conf always follows a fixed **16-step pattern**. Only the source CTE chain and validated columns vary between pipelines.

---

## Non-Negotiable Settings (always apply these)

```hocon
spark-properties = {
  "spark.sql.autoBroadcastJoinThreshold" = "-1"   # prevents Cartesian OOM on accuracy join
  "spark.sql.session.timeZone"           = "America/Los_Angeles"  # aligns current_date() with DM PST cutoff
}

step-defaults {
  load-intermediate-results              = false
  cache-results                          = true   # REQUIRED — SurrogateKeyGenerator reads dq_completeness temp view
  save-intermediate-results              = false
  calculate-counts                       = false
  propagate-data-frames-between-steps    = false
}
```

---

## 16-Step Pipeline Order

```
1.  dq_metadata
2.  dq_source
3.  dq_target
4.  dq_compare
5.  dq_unmatched
6.  dq_completeness
7.  SurrogateKeyGenerationCompleteness
8.  InsertStepCompleteness
9.  dq_source_sample_ids
10. dq_target_sample_ids
11. dq_source_sample
12. dq_target_sample
13. dq_accuracy
14. SurrogateKeyGenerationAccuracy
15. InsertStepAccuracy
16. audit_update
```

---

## Step Templates

### Step 1 — dq_metadata
```sql
SELECT
  (SELECT RPT_SOX_SETUP_ID     FROM ${soxSchema}.RPT_SOX_SETUP     WHERE TABLE_NAME = '${dmTable}' AND ACTIVE_FLAG = true) AS setup_id,
  (SELECT START_DATE           FROM ${soxSchema}.RPT_SOX_SETUP     WHERE TABLE_NAME = '${dmTable}' AND ACTIVE_FLAG = true) AS start_date,
  (SELECT END_DATE             FROM ${soxSchema}.RPT_SOX_SETUP     WHERE TABLE_NAME = '${dmTable}' AND ACTIVE_FLAG = true) AS end_date,
  (SELECT RPT_SOX_METADATA_ID  FROM ${soxSchema}.RPT_SOX_METADATA  WHERE TABLE_NAME = '${dmTable}' AND ACTIVE_FLAG = true) AS metadata_id
```
> Use scalar subqueries (not CROSS JOIN) to avoid Cartesian product OOM.

### Step 2 — dq_source
```sql
WITH date_window AS (
  SELECT
    date_trunc('month', add_months(current_date(), -1)) AS start_date,
    last_day(date_trunc('month', add_months(current_date(), -1)))  AS end_date
),
-- paste adapted DM CTE chain here --
-- add CROSS JOIN date_window DW to base CTEs that filter on date --
-- add WHERE to_date(<date_col>) BETWEEN DW.start_date AND DW.end_date --
final AS (
  SELECT
    concat('<urn_prefix>', <pk_cols>) AS id,
    map(
      '<col1>', cast(<col1> AS STRING),
      '<col2>', cast(<col2> AS STRING),
      -- 5-7 validated columns --
    ) AS src_record
  FROM <base_cte>
  CROSS JOIN date_window DW
  WHERE to_date(<date_col>) BETWEEN DW.start_date AND DW.end_date
)
SELECT id, src_record FROM final
```
> Date window = last closed calendar month. `current_date()` is PST-aligned via `spark.sql.session.timeZone`.

### Step 3 — dq_target
```sql
SELECT
  <id_expression>         AS id,
  map(
    '<col1>', cast(<col1> AS STRING),
    '<col2>', cast(<col2> AS STRING)
  )                       AS tgt_record
FROM ${dmSchema}.${dmTable} dm
WHERE to_date(dm.<date_col>) BETWEEN
  date_trunc('month', add_months(current_date(), -1))
  AND last_day(date_trunc('month', add_months(current_date(), -1)))
```

### Step 4 — dq_compare
```sql
SELECT
  COALESCE(S.id, T.id)                AS id,
  S.src_record,
  T.tgt_record,
  CASE WHEN S.id IS NULL THEN 'TARGET_ONLY'
       WHEN T.id IS NULL THEN 'SOURCE_ONLY'
       ELSE 'MATCHED' END             AS match_status
FROM dq_source S
FULL OUTER JOIN dq_target T ON S.id = T.id
```

### Step 5 — dq_unmatched
```sql
SELECT id, src_record, tgt_record, match_status
FROM dq_compare
WHERE match_status <> 'MATCHED'
```

### Step 6 — dq_completeness
```sql
SELECT
  (SELECT setup_id   FROM dq_metadata) AS RPT_SOX_SETUP_ID,
  (SELECT metadata_id FROM dq_metadata) AS RPT_SOX_METADATA_ID,
  '${dmTable}'                          AS TGT_TABLE_NAME,
  '${domain}'                           AS DOMAIN,
  (SELECT start_date FROM dq_metadata)  AS START_DATE,
  (SELECT end_date   FROM dq_metadata)  AS END_DATE,
  COUNT(DISTINCT CASE WHEN match_status IN ('MATCHED','SOURCE_ONLY') THEN id END) AS SRC_METRIC_VALUE,
  COUNT(DISTINCT CASE WHEN match_status IN ('MATCHED','TARGET_ONLY') THEN id END) AS TGT_METRIC_VALUE,
  CASE WHEN
    COUNT(DISTINCT CASE WHEN match_status IN ('MATCHED','SOURCE_ONLY') THEN id END) =
    COUNT(DISTINCT CASE WHEN match_status IN ('MATCHED','TARGET_ONLY') THEN id END)
  THEN true ELSE false END              AS MATCHED,
  current_timestamp()                   AS LOAD_TS
FROM dq_compare
```

### Step 7 — SurrogateKeyGenerationCompleteness
```hocon
{
  class  = "com.intuit.superglue.quicketl.transformations.SurrogateKeyGeneratorTransformation"
  inputs = ["dq_completeness"]
  output-table = "dq_completeness_with_key"
  surrogate-key-column = "RPT_SOX_COMPLETENESS_ID"
  target-table = "${soxSchema}.RPT_SOX_COMPLETENESS"
}
```

### Step 8 — InsertStepCompleteness
```hocon
{
  class  = "com.intuit.superglue.quicketl.outputs.InsertIntoTableStep"
  inputs = ["dq_completeness_with_key"]
  output-table = "${soxSchema}.RPT_SOX_COMPLETENESS"
}
```

### Steps 9-10 — dq_source_sample_ids / dq_target_sample_ids
```sql
-- dq_source_sample_ids: pull IDs directly from source (not dq_source) for the same window
-- Use TABLESAMPLE to avoid full scan on large tables
SELECT DISTINCT id
FROM (
  SELECT concat('<urn_prefix>', <pk_cols>) AS id
  FROM <source_table> TABLESAMPLE(${samplingSize} PERCENT)
  CROSS JOIN date_window DW
  WHERE to_date(<date_col>) BETWEEN DW.start_date AND DW.end_date
)
LIMIT 1000

-- dq_target_sample_ids: pull matching IDs from DM
SELECT id FROM dq_target
WHERE id IN (SELECT id FROM dq_source_sample_ids)
```

### Steps 11-12 — dq_source_sample / dq_target_sample
```sql
SELECT S.id, S.src_record FROM dq_source S
WHERE S.id IN (SELECT id FROM dq_source_sample_ids)

SELECT T.id, T.tgt_record FROM dq_target T
WHERE T.id IN (SELECT id FROM dq_target_sample_ids)
```

### Step 13 — dq_accuracy
```sql
SELECT
  (SELECT setup_id    FROM dq_metadata) AS RPT_SOX_SETUP_ID,
  (SELECT metadata_id FROM dq_metadata) AS RPT_SOX_METADATA_ID,
  '${dmTable}'                           AS TGT_TABLE_NAME,
  '${domain}'                            AS DOMAIN,
  (SELECT start_date  FROM dq_metadata)  AS START_DATE,
  (SELECT end_date    FROM dq_metadata)  AS END_DATE,
  COALESCE(S.id, T.id)                   AS ID,
  S.src_record,
  T.tgt_record,
  CASE WHEN S.src_record = T.tgt_record THEN true ELSE false END AS MATCHED,
  current_timestamp()                    AS LOAD_TS
FROM dq_source_sample S
FULL OUTER JOIN dq_target_sample T ON S.id = T.id
```

### Steps 14-15 — SurrogateKeyGenerationAccuracy / InsertStepAccuracy
```hocon
{
  class  = "com.intuit.superglue.quicketl.transformations.SurrogateKeyGeneratorTransformation"
  inputs = ["dq_accuracy"]
  output-table = "dq_accuracy_with_key"
  surrogate-key-column = "RPT_SOX_ACCURACY_ID"
  target-table = "${soxSchema}.RPT_SOX_ACCURACY"
}
{
  class  = "com.intuit.superglue.quicketl.outputs.InsertIntoTableStep"
  inputs = ["dq_accuracy_with_key"]
  output-table = "${soxSchema}.RPT_SOX_ACCURACY"
}
```

### Step 16 — audit_update
```sql
UPDATE ${soxSchema}.RPT_SOX_SETUP
SET LAST_RUN_TS = current_timestamp()
WHERE TABLE_NAME = '${dmTable}' AND ACTIVE_FLAG = true
```

---

## Common Gotchas

| Gotcha | Fix |
|--------|-----|
| `cache-results = false` causes SurrogateKeyGenerator to fail (temp view gone) | Always set `cache-results = true` in step-defaults |
| `current_date()` is UTC — off by 1 day vs DM PST cutoff | Set `spark.sql.session.timeZone = America/Los_Angeles` |
| Cartesian OOM on accuracy join with CROSS JOIN dq_metadata | Use scalar subqueries for all dq_metadata references |
| `end_date = date_add(current_date(), -2)` spans into current month | Use `last_day(date_trunc('month', add_months(current_date(), -1)))` |
| Large dq_source DISTINCT id scan causes driver OOM for sample IDs | Query source tables directly with TABLESAMPLE, not dq_source |
| Missing `autoBroadcastJoinThreshold = -1` causes Cartesian on accuracy | Always add to spark-properties |
