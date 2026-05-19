---
name: framework-dispatch
description: Schema registry lookup and agent dispatch table for the pii-minimization plugin. Maps schema names to pipeline frameworks and specialist agents.
---

# Framework Dispatch

## Schema registry

The schema registry is bundled with this plugin at:
```
${CLAUDE_PLUGIN_ROOT}/registry/schema-job-type.yaml
```

Read it directly — no external file reference needed. It maps every schema to its pipeline type, GitHub repo, and batch.

## PII Inventory Google Sheet

**Authoritative source for SENSITIVE columns and pipeline metadata:**
```
https://docs.google.com/spreadsheets/d/1tRCokJ8n__Juw4IG3tI1LfmybxN25y1d/edit
```

| Tab | gid | Purpose |
|-----|-----|---------|
| 📋 Execution Overview | `gid=2018349118` | Rollout plan, dates, schema counts — start here for context |
| 📊 Table-Level PII Detail | `gid=1687383891` | **SENSITIVE columns per schema.table — PRIMARY SOURCE for column lookup** |
| redshift-datalake mapping | `gid=0` | DL→Redshift schema/table/column name mapping (used by Rex) |
| BPP Prf jobs | `gid=1716830622` | PRF pipeline names + `pipeline_devportal_url` column |
| BPP Prod pipelines | `gid=769537233` | PRD pipeline names + `pipeline_devportal_url` column |
| 📋 Table Action Summary | — | Per-table action (ENCRYPT/DROP) and developer assignment |
| 🔐 Schema Encryption Tracker | — | Per-schema Phase 1/2 deploy status |
| 🔓 Decryption Tracker | — | Consumer decrypt deploy status |

**All agents MUST look up SENSITIVE columns from `gid=1687383891` — never hardcode or guess column names.**

Direct links agents should use:
- SENSITIVE columns: `https://docs.google.com/spreadsheets/d/1tRCokJ8n__Juw4IG3tI1LfmybxN25y1d/edit?gid=1687383891`
- PRF pipeline devportal URLs: `https://docs.google.com/spreadsheets/d/1tRCokJ8n__Juw4IG3tI1LfmybxN25y1d/edit?gid=1716830622`
- PRD pipeline devportal URLs: `https://docs.google.com/spreadsheets/d/1tRCokJ8n__Juw4IG3tI1LfmybxN25y1d/edit?gid=769537233`

## Pipeline → Agent dispatch table

| Pipeline value | Agent | Phase 1 | Phase 2 |
|---------------|-------|---------|---------|
| `rda_bpp` | `pii-minimization:rda-bpp-engineer` (Alex) | decrypt-on-read in PySpark/EMR job | encrypt-on-write in PySpark/EMR job |
| `quicketl` | `pii-minimization:quicketl-engineer` (Quinn) | decrypt-on-read in HOCON .conf | encrypt-on-write in HOCON .conf |
| `quickbase` | `pii-minimization:quickbase-engineer` (Quin) | CREATE new QuickETL encrypt jobs → PRF | Promote PRF jobs to PRD |
| `spp` | `pii-minimization:spp-engineer` (Sam) | N/A — redirect to Phase 2 | encrypt-on-write + immediate backfill |
| `report_requestor` | `pii-minimization:report-requestor-engineer` (Rio) | inject odin_decrypt() in Python scripts | inject odin_encrypt() in Python scripts |

Redshift widening is handled separately by `pii-minimization:redshift-dba` (Rex) regardless of pipeline type.

## Title → Pipeline hint mapping

| Story title contains | Pipeline |
|---------------------|---------|
| BPP Transform / BPP / EMR | `rda_bpp` |
| QuickETL / Quick ETL | `quicketl` |
| SPP / Kafka / Stream | `spp` |
| Quickbase / QuickBase | `quickbase` |
| Report Requestor / RR Layer | `report_requestor` |

## Encryption patterns by framework

### rda_bpp (ETL-Zoot and similar)
```python
# Phase 1 — decrypt-on-read
v_session = init_spark_decrypt_session()
# In SQL SELECT:
odin_decrypt(cast(<sensitive_col> as string)) as <sensitive_col>

# Phase 2 — encrypt-on-write
v_session = init_spark_encrypt_session()
odin_encrypt(cast(<sensitive_col> as string)) as <sensitive_col>
```

### quicketl (HOCON .conf with inline SQL)
```sql
-- Phase 1 — decrypt-on-read
CAST(odin_decrypt(<col>) AS STRING) AS <col>

-- Phase 2 — encrypt-on-write
CAST(odin_encrypt(<col>) AS STRING) AS <col>
```

### quickbase (new QuickETL jobs — encrypt in Phase 1)
```sql
-- Phase 1 — encrypt-on-write (new job, read from stage S3)
CAST(odin_encrypt(CAST(<col> AS STRING)) AS STRING) AS <col>

-- Read from latest partition:
WITH latest AS (SELECT MAX(dt) AS max_dt FROM parquet.`"""${variables.stage_s3_location}<table>"""`)
SELECT ..., l.max_dt AS dt
FROM parquet.`"""${variables.stage_s3_location}<table>"""` s
JOIN latest l ON s.dt = l.max_dt
```

### report_requestor (Python)
```python
# Phase 1
from odin_client import odin_decrypt
row[col] = odin_decrypt(row[col])  # NULL-safe: check is not None first

# Phase 2
from odin_client import odin_encrypt
row[col] = odin_encrypt(str(row[col]))  # NULL/empty-safe
```

## Validation patterns

### Ciphertext check (Phase 2 expected — ciphertext present)
```sql
SELECT COUNT(*) FROM <schema>.<table>
WHERE dt = date_sub(current_date, 1)
AND <sensitive_col> IS NOT NULL
AND <sensitive_col> NOT LIKE 'AQI%';
-- Expected: 0
```

### Plaintext check (Phase 1 expected — no ciphertext)
```sql
SELECT COUNT(*) FROM <schema>.<table>
WHERE dt = '<yesterday>'
AND <sensitive_col> LIKE 'AQI%';
-- Expected: 0
```

### Partition sanity check (always run — BLOCKER if 0)
```sql
SELECT COUNT(*) FROM <schema>.<table>
WHERE dt = date_sub(current_date, 1);
-- Expected: > 0
```
