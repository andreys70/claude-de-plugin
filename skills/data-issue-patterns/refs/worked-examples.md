# Worked examples — patterns from real cases

These are real diagnostic patterns from past investigations. Match the current problem to one of these shapes when stuck — the lesson usually transfers.

## Example 1 — The `mt_txn_id` bridge (FIND-599)

### Situation

`risk_analytics_stable.ips_transactions_check_new.last_routing_number` went 97% NULL for Feb/Mar 2026. Legacy `ihub_check_clear` rows had collapsed. Payments 2.0 had rows for the same period but with alphanumeric `payment_txn_id` (e.g., `179z6csukn94`), while the pipeline's `grouped_data_cte.txn_id` was a numeric BIGINT (e.g., `3082661893`). Two different ID spaces — easy to conclude "parallel systems, unrelated traffic."

### Insight

A third column, `grouped_data_cte.mt_txn_id` (sourced from `ihub_txn_event_hdr.cti`), was populated 100% of the time and held the Payments 2.0 `payment_txn_id` alongside the legacy `txn_id`. Join rate via `mt_txn_id`:

| Month | PRF rows | Match rate via `mt_txn_id` | NULL rate |
| --- | --- | --- | --- |
| Feb 2026 | 3,442,808 | 96.24% | 96.59% |
| Mar 2026 | 4,043,410 | 96.75% | 97.11% |

The match rate tracking the NULL rate to the percentage point was the proof.

### Lesson

**Before concluding two systems are unrelated, grep the schemas and sample data for any field that could bridge them.** A 100%-populated field on one side is a strong hint. Look for fields named `cti`, `external_ref_id`, `source_txn_id`, `mt_txn_id`, `legacy_id`, or similar.

---

## Example 2 — Control group (FIND-599 downstream verification)

### Situation

After deploying the fix, `negative_list` row counts for `Buyer Bank Routing` and `Buyer Routing 2Acct` jumped ~5–8×. The question: is this jump attributable to the fix, or to an unrelated pipeline shift?

### Insight

`Payroll_RoutingNo` is also a routing-number attribute in the same table, but it reads from a separate payroll source — not `ips_transactions_check_new.last_routing_number`. Its post-fix count was unchanged (107–108/day, same as pre-fix). That disproves a "shared infrastructure change" explanation and attributes the jump specifically to the fix.

### Lesson

**When claiming a change caused an effect, find something in the same system that *shouldn't* have moved and show it didn't.** Without a control, any observed change can be explained away as coincidence.

---

## Example 3 — The Payments 2.0 red herring (FIND-599 first attempt)

### Situation

Legacy `ihub_check_clear` row counts collapsed from 3.3M/month (Nov 2025) to 117K (Feb 2026). Payments 2.0 `ppfpymt_payment_moneymovement` row counts for the same period rose from 0 to 3.3M. Symmetric ramp — strongly suggests "migration."

### Why the first theory was wrong

A first fix was attempted using a UNION across legacy and Payments 2.0. The NULL% didn't change post-deploy — because the Payments 2.0 rows had `payment_txn_id` that didn't match legacy `txn_id`. The "same transactions, migrated" theory would have required matching IDs. They didn't.

The theory had to be refined: not "migrated" but "tracked under two IDs simultaneously, bridged by `mt_txn_id`."

### Lesson

**A hypothesis that fits aggregate numbers but fails when you try to join on keys is incomplete.** Ruling-out includes trying the fix and checking it actually works. The first NULL% measurement after a deploy is a lie detector — trust it over the explanation.

---

## Example 4 — Dead code path rule-out

### Situation

While investigating why `last_sent_date` was NULL alongside `last_routing_number`, the pipeline code showed a fallback: `NVL(g.first_sent_date, c.transmit_clear_date)`. That `g.first_sent_date` came from a CTE (`sent_date_cte`) filtering on `event_id = 15603`.

### Insight

Audit of the upstream `ihub_txn_event_det` showed `event_id = 15603` **does not exist** in the Aurora source — verified across 16 active event_ids from Nov 2025 onward. `g.first_sent_date` has always been NULL; the NVL fallback to `c.transmit_clear_date` has been load-bearing since the code was written.

### Lesson

**Rule out dead code paths explicitly.** Don't assume a `NVL(A, B)` means `A` is the primary source — check whether `A` is ever populated at all. A pre-existing dead code path can confuse the investigation by looking like a current bug.

---

## Pattern-matching — when stuck, scan these

If your current investigation is stuck, ask:

- **Does the problem look like Example 1?** Check for a cross-reference field. Search the schema for any ID-shaped column that could bridge the two systems you're looking at.
- **Have you verified your fix actually works (Example 3)?** Symmetric-ramp aggregates are a classic trap. The only reliable test is a deployed fix + a post-deploy metric check.
- **Can you find a control group (Example 2)?** If you claim change X caused effect Y, find a Z that shouldn't have moved and show it didn't.
- **Is the "existing fallback" actually a dead path (Example 4)?** Check whether the NVL/COALESCE's first argument has ever been populated in the period you're investigating.

## Adding a new example

When you diagnose a case with a new pattern, add a section here using the structure:

- **Situation** — what was observed, with concrete numbers
- **Insight** — what the key breakthrough was
- **Lesson** — the generalizable takeaway

Keep each example self-contained. Don't rely on context from other examples.
