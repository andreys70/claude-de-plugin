# Partition guidance — keep SQL queries fast

This file is the single source of truth for how to handle partitioned tables when running SQL against the data warehouse. Both `data-issue-diagnoser` (fix flow) and `data-validator` (all flows) follow this.

## Why this exists

Diagnostic and verification queries against large tables can take many minutes — sometimes hours — when the engine is forced to scan all partitions. Most large analytics tables are partitioned by date or some other coarse-grained column. A query with no filter on the partition column scans everything; a query with a partition predicate scans only the relevant slice.

The cost is asymmetric:
- **With a partition filter:** seconds to a couple of minutes, even on multi-TB tables.
- **Without:** full scan, often 10–60+ minutes, sometimes timeouts that waste both your time and the engineer's.

Always check, always filter.

## When to apply

Apply this routine **before running any "broad" query** — defined as any query that doesn't already have an explicit filter on what's likely the partition column:

- `COUNT(*)` over the table
- `GROUP BY` over months, days, or any time grain
- `SELECT … WHERE <non-partition-column>` (the predicate doesn't help partition pruning)
- Any query whose WHERE clause filters only by columns you haven't yet confirmed are partition columns

You can skip the routine for:
- A query whose WHERE clause already contains a partition predicate the engineer specified
- A `LIMIT 10` spot-check (the engine usually short-circuits these regardless)

## Procedure

### Step 1: Read the table DDL first (no engineer prompt yet)

Run **one** of these to discover partition columns:

```sql
DESCRIBE TABLE EXTENDED <catalog>.<schema>.<table>;
```

Look in the output for a `# Partition Information` block, then column names in the rows that follow. This is the authoritative source.

If `DESCRIBE TABLE EXTENDED` output is hard to parse or doesn't show partition info clearly, fall back to:

```sql
SHOW PARTITIONS <catalog>.<schema>.<table>;
```

A non-empty result lists actual partitions; the column names embedded in those values are the partition columns.

If neither query reveals partitions, the table is likely unpartitioned — proceed with the original query and accept the cost.

### Step 2: Identify the partition columns and types

For each partition column, note its data type:
- **Date / timestamp / datetime** — the common case for time-series tables.
- **Non-date** (e.g., `region`, `country`, `customer_segment`, `event_type`) — categorical partition.

A table can have multiple partition columns; the most-selective one for your query is usually a date column.

### Step 3: Pick a default filter from context — do not ask the engineer if you can avoid it

Try the defaults in order; only ask if none apply:

**For a fix-flow diagnostic query (`data-issue-diagnoser`):**
1. **Date range named in the Jira intake** (e.g., "anomaly observed Feb–Apr 2026") → use that range exactly.
2. **Anomaly window the engineer specified in the prompt** → use it.
3. **Default lookback** → last 90 days from today.

**For a verification query (`data-validator`):**
1. **`anomaly-resolved` mode:** the baseline + post-fix window the engineer already provided.
2. **`acceptance-criteria` mode:** the post-change window since the commit (`commit_time` to today).
3. **`first-run-healthy` mode:** the run window since the first-run trigger time.
4. **Default lookback if nothing else applies** → last 30 days from today.

For non-date partition columns: there's no useful default. Ask the engineer:

> "Table `<name>` is partitioned by `<column>` (non-date). Which value(s) should I filter on? (e.g., `region IN ('us-east', 'us-west')`)"

### Step 4: Inject the partition predicate into the query

For a date partition column:

```sql
-- before
SELECT … FROM <catalog>.<schema>.<table> WHERE <some_other_filter>;

-- after
SELECT … FROM <catalog>.<schema>.<table>
WHERE <date_partition_col> >= '<from>'
  AND <date_partition_col> <  '<to>'
  AND <some_other_filter>;
```

For a non-date partition column:

```sql
SELECT … FROM <catalog>.<schema>.<table>
WHERE <partition_col> IN ('<value_1>', '<value_2>')
  AND <some_other_filter>;
```

Use **half-open intervals** (`>= from AND < to`) so you don't accidentally include or exclude a boundary day.

### Step 5: If the query still runs slow, tighten the range

If a query takes more than ~30 seconds:
- Stop and reconsider the date range. Was it set too wide?
- Ask the engineer for a tighter range:

  > "Query is still slow with `<from>` to `<to>` (>30s). Want to narrow the window? (e.g., one month at a time)"

For verification queries that need a long historical baseline (12+ months for NULL% trend), this is expected — note it in the report and proceed.

## Confirmation prompt — only when you need engineer input

Surface the partition handling concisely:

> "Table `<name>` is partitioned by `<col>` (`<type>`). Filtering to `<from>` → `<to>` based on `<source: Jira | engineer prompt | default 90d>`. OK to proceed? (yes / change range)"

Skip this prompt if:
- The default came from a date range the engineer or Jira already specified explicitly (no decision is being made for them).
- It's a non-date partition where you had to ask anyway (the asking IS the prompt).

## What you do NOT do

- **Don't run the broad query first to "see how slow it is."** That defeats the point.
- **Don't guess the partition column from naming conventions** (e.g., assuming a column called `event_date` is the partition just because the name fits). Use the DDL.
- **Don't apply this routine to short-circuit-able queries** (LIMIT 10 spot-checks, EXISTS / NOT EXISTS, etc.). Adds noise.
- **Don't widen the default lookback to "be thorough."** The defaults exist because they're the right balance for diagnostic / verification work; widening means slower queries with no extra signal.
