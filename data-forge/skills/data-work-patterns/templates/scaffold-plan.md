# Scaffold plan — <TICKET-KEY or spec name>

> Output of the orchestrator's Phase 2 for the create flow. The engineer
> reviews and approves this **before** the coder creates any files.

## Ask (lifted from the Jira or freeform spec)
<one or two sentences summarizing what's being built>

## Source(s)
| Catalog.schema.table | Refresh | Notes |
|---|---|---|
| <upstream> | <freq> | <e.g., raw extract from system X> |

## Target
- **Catalog.schema.table:** `<target>`
- **Refresh frequency:** <daily 6 AM PT / hourly / etc.>
- **Partitioning:** <column + grain, or "none">
- **Primary key:** <col(s)>

## Sibling pipeline to mirror
- **Path:** `<path of an existing pipeline that resembles this one>`
- **Why this sibling:** <one sentence — same source pattern, same sink shape, same refresh model>

## Files to create
| Path | Purpose |
|---|---|
| <config path> | <e.g., pipeline registration / schedule / lineage> |
| <code path>   | <e.g., main transform> |
| <test path?>  | <only if the sibling has tests> |

## Schema (column list lifted from the spec)
| Column | Type | Nullable? | Source-of-truth | Notes |
|---|---|---|---|---|
| <col> | <type> | <yes/no> | <source col or derivation> | <e.g., "must populate per spec"> |
| ... | | | | |

## Out of scope (deferred — separate ticket later)
- <bullet>

## Assumptions
- <e.g., "spec didn't specify partition; defaulting to date column matching sibling"> — engineer should confirm

## Risks / things to watch at PRF dry-run
- <e.g., source row volume, join key uniqueness, refresh dependency chain>

## First-run-healthy criteria (used by the validator post-PRF)
1. Table exists at `<target>`
2. Schema matches the column list above
3. Non-zero rows
4. Required columns populated: <list>
5. No duplicates on `<primary_key>`
6. Row count within an order of magnitude of <expected> (if known)
