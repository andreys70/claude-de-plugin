# Diagnostic method — the rule-out pattern

Diagnostic work is about **disproving hypotheses**, not confirming the first plausible one. Follow this sequence for every data-issue investigation.

## 1. Reproduce the anomaly

Run SQL that makes the anomaly concrete. Present actual numbers, not narrative.

**Good:** "98.2% of Feb 2026 rows (3.44M of 3.50M) have `last_routing_number IS NULL`."

**Useless:** "Many rows are missing routing numbers."

If you cannot reproduce the anomaly, you cannot diagnose it. Stop and ask the engineer for a specific example (row count, date, ID) that demonstrates the problem.

## 2. List 3–6 candidate root causes

Include the unglamorous ones — they're often the actual answer:

- **Upstream source change** — data loss, schema drift, batch failure, CDC pipeline change
- **ETL code regression** — check `git log` on the transform script and any shared libs
- **Join key format drift** — IDs silently changed format (alphanumeric ↔ numeric, truncation, encoding)
- **Partition or filter drift** — a WHERE clause now excludes valid rows
- **Dead code path** — referencing an event_id, source system, or column that no longer exists
- **Migration / cutover** — same semantic transaction, now recorded under a different system or ID
- **Silent semantic change** — same column name, different meaning upstream

Write the list down. Don't skip this step.

## 3. Rule out each candidate with evidence

For every hypothesis, either confirm or disprove with a specific query or file check. Present the output.

Format for each:

```
### Candidate N: <name>
**Check:** <query or file reference>
**Result:** <what came back>
**Verdict:** ruled out / confirmed / inconclusive (need X)
```

Keep the queries small and focused. Each query answers exactly one diagnostic question. Don't fish.

## 4. Watch for red herrings

A red herring is an explanation that **fits the aggregates but fails on keys**.

**Warning signs:**
- Aggregate row counts line up perfectly, but when you try to join on IDs, nothing matches.
- A fix that "should" work based on the explanation doesn't move the needle post-deploy.
- Two datasets ramp symmetrically but belong to different ID spaces.

When you see this, stop and refine the hypothesis. Don't act on it.

## 5. Find the bridge, not the wall

When two systems look unrelated but cover overlapping traffic, there's usually a cross-reference field somewhere.

**Search for:**
- A 100%-populated field on one side that looks suspiciously like an ID from the other system
- `cti`, `external_ref_id`, `source_txn_id`, `txn_ref`, `mt_txn_id`, `payment_txn_id`, `legacy_id`, `migration_id` and similar naming
- Sample values on both sides side-by-side — do they share a format?

A bridge found is worth more than ten ruled-out hypotheses.

## 6. Use control groups

When claiming that change X caused effect Y, find something in the same system that **shouldn't** have moved and show it didn't.

**Good control candidates:**
- A sibling column that reads from a different source path
- An attribute in the same table that depends on a different upstream
- A time period before the change that should look identical pre/post

Without a control, large observed changes can always be dismissed as "probably something else." A control disproves that.

## 7. Quantify gaps

If you can't rule out a candidate, say so explicitly:

- "Not ruled out — requires access to upstream Aurora DB."
- "Not ruled out — requires a 30-day sample, have only 24h."
- "Not ruled out — schema for source table is unavailable."

Don't paper over gaps. "Inconclusive" is a valid outcome.

## 8. Know when to stop

You have enough when:
- One candidate is confirmed by direct evidence (not "it must be X because everything else is ruled out")
- The proposed fix can be written at the code level (function names, join predicates, not vague directions)
- The verification plan is obvious (you know exactly what query would prove the fix worked)

If any of those three is missing, keep digging.

## 9. Don't propose fixes before diagnosis is complete

It's tempting to write code while the first plausible cause is still being considered. Don't. If you're wrong, the diff will be built on a bad foundation, and the engineer will waste time reviewing an approach that can't work.

**Rule:** no file edits until the root cause is confirmed with evidence.
