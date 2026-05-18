# DM Pipeline Patterns

Reference for generating QuickETL DM conf files. Agents read this to understand write modes, class names, and HOCON conventions.

---

## Write Mode Selection

| Signal | Write Mode | Class |
|--------|-----------|-------|
| No CDC columns; ticket says full-refresh; `audit_upd_ts` same for all rows after run | `full_refresh` | `HighAvailabilityTableUpdate` |
| Table has `lastUpdated`, `modified_date`, or `audit_upd_ts` partition column | `incremental` | `OptimizedMergeOperator` |

**When in doubt:** check the existing DM conf in the repo. If it uses `HighAvailabilityTableUpdate`, it is full-refresh.

---

## Full-Refresh HOCON Skeleton (`HighAvailabilityTableUpdate`)

```hocon
include required(file("${CONF_HOME}//<domain>_dm_${env}.conf"))
include required(file("${CONF_HOME}//<domain>_dm_base.conf"))

pipeline-defaults {
  generateVerticesAndEdges = false
}

variables {
  targetTable   = "<table_name>"
  targetSchema  = "${dmSchema}"
  s3Location    = "${dmS3Bucket}/<domain>/<table_name>"
}

pipeline {
  name           = "<table_name>"
  primary_owner  = "<engineer>"
  secondary_owner = "<secondary>"
  slack_team     = "#rda-support"
  steps = [
    create_view,
    write_table
  ]
}

create_view {
  class = "com.intuit.superglue.quicketl.transformations.SparkSqlTransformation"
  inputs = []
  output-table = "<table_name>_view"
  load-intermediate-results = false
  sql = """
    -- CTE chain here
    SELECT
      ...,
      current_timestamp() AS audit_ins_ts,
      current_timestamp() AS audit_upd_ts
    FROM ...
  """
}

write_table {
  class = "com.intuit.superglue.quicketl.outputs.HighAvailabilityTableUpdate"
  inputs = ["<table_name>_view"]
  output-table = "${targetSchema}.${targetTable}"
  output-location = "${s3Location}"
  retentionSize = 5
  fileFormat = "PARQUET"
}
```

---

## Incremental HOCON Skeleton (`OptimizedMergeOperator`)

```hocon
include required(file("${CONF_HOME}//<domain>_dm_${env}.conf"))
include required(file("${CONF_HOME}//<domain>_dm_base.conf"))

variables {
  targetTable   = "<table_name>"
  targetSchema  = "${dmSchema}"
  s3Location    = "${dmS3Bucket}/<domain>/<table_name>"
  mergeKey      = "<primary_key_column>"
}

pipeline {
  name  = "<table_name>"
  steps = [create_view, merge_table]
}

create_view {
  class = "com.intuit.superglue.quicketl.transformations.SparkSqlTransformation"
  inputs = []
  output-table = "<table_name>_view"
  sql = """
    SELECT
      ...,
      current_timestamp() AS audit_ins_ts,
      current_timestamp() AS audit_upd_ts
    FROM ...
    WHERE <cdc_filter>
  """
}

merge_table {
  class = "com.intuit.superglue.quicketl.outputs.OptimizedMergeOperator"
  inputs = ["<table_name>_view"]
  output-table = "${targetSchema}.${targetTable}"
  output-location = "${s3Location}"
  merge-key = "${mergeKey}"
  fileFormat = "PARQUET"
}
```

---

## Key Conventions

- Always append `audit_ins_ts = current_timestamp()` and `audit_upd_ts = current_timestamp()` as last two columns
- S3 location pattern: `${dmS3Bucket}/<domain>/<table_name>` (domain is lowercase: qbc, loss_reserve, capital)
- Spark timezone: DM pipelines run in UTC — use `from_utc_timestamp(current_timestamp(), 'America/Los_Angeles')` for PST-based date cutoffs
- Change history header at top of every conf file:
  ```
  // DATE       | JIRA      | AUTHOR        | DESCRIPTION
  // DD/MM/YYYY | FIND-XXX  | <name>        | Initial build
  ```
- Config file naming: `<table_name>.conf` (no prefix for DM, `dq_` prefix for SOX DQ)
- Folder path: `configs/<pipeline_folder>/<domain>/<table_name>.conf`

---

## Domain-Specific Folder Mapping

| Domain | DM Folder | SOX Folder |
|--------|-----------|------------|
| QBC | `configs/finance_mm_dm/qbc/` | `configs/finance_mm_sox/qbc/` |
| Loss Reserve | `configs/finance_mm_dm/loss_reserve/` | `configs/finance_mm_sox/loss_reserve/` |
| Capital | `configs/finance_mm_dm/capital/` | `configs/finance_mm_sox/capital/` |

For new domains: infer from the JIRA ticket or ask the engineer at Checkpoint 1.
