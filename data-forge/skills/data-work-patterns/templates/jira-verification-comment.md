## Post-Deploy Verification — Fix Confirmed / Concerns

<Target table> refreshed on <date/time PT> with commit <SHA> on `<branch>`. All checks pass / Concerns noted below.

### 1. <Primary success metric>

| Month | Pre-fix | **Post-fix** |
| --- | --- | --- |
| <baseline month> | <value> | <value> |
| <problem month 1> | <value> | **<value>** |
| <problem month 2> | <value> | **<value>** |

<1–2 sentence interpretation>

### 2. Row count parity vs stable

<Month-by-month comparison, diff column. Note expected differences, e.g., PRF ahead of stable.>

### 3. Spot-check vs source

<1-sentence summary: "N/10 rows matched source-of-truth values."> Example:

| <id> | <bridge_col> | <fixed_col> | <source_col> |
| --- | --- | --- | --- |
| <sample> | <sample> | <value> | <value> |

### 4. Cardinality

`COUNT(*) = COUNT(DISTINCT <key>)` for every month post-fix. No duplicates introduced.

### 5. Downstream impact (optional, if applicable)

<Table showing pre/post downstream metric, with a control group>

### Status

<One-line conclusion. "Fix confirmed end-to-end." or "Concerns — spot-check showed 8/10 match, investigating mismatches.">

### Next steps

1. <e.g., "Let stable table pick up the fix on next refresh">
2. <e.g., "Monitor NULL% for a week to confirm baseline holds">
3. <e.g., "Close ticket after stable validation">
