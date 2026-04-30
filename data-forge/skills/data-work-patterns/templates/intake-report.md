# Intake Report — <TICKET-KEY or "no Jira; freeform spec">

## Ticket
- **Summary:** <one-line summary>
- **Status / Priority:** <status> / <priority>
- **Assignee / Reporter:** <name> / <name>
- **Labels:** <labels>
- **Dates:** created <date>, updated <date>, due <date or N/A>

## Problem statement
<2–4 sentences reproducing the problem in your words, grounded in the description or spec>

## Affected surface area
- **Table(s):** <list>
- **Column(s):** <list>
- **Date range / partitions:** <range>
- **Upstream named:** <sources>
- **Downstream named:** <consumers>

## Prior investigation timeline

For each engineer comment in chronological order:

### <Author> — <date>
- **Claim:** <one line>
- **Evidence:** <one line, e.g. "NULL% table: Feb 96.59%, Mar 97.11%">
- **Ruled out:** <one line or N/A>
- **Conclusion:** <one line>
- **Superseded by later comment?** yes / no — <which one>

For freeform-spec inputs (no Jira), populate this section with `(no Jira; freeform spec)` rather than omitting it.

## Current state
<One sentence; phrasing depends on workflow:
  fix:         newly reported / under investigation / root cause identified / fix in progress / fix deployed / awaiting verification / disputed
  enhancement: newly requested / under design / design approved / in development / in PRF / deployed / awaiting verification
  create:      newly requested / requirements gathered / scaffold proposed / scaffold approved / in development / in PRF / deployed / awaiting verification>

## Open questions / next step
- <unresolved items, what needs probing>
- <suggested starting point for the next phase>

## Red flags
<Anything inconsistent, contradictory, or that warrants caution — e.g., "Comment 2 concluded upstream data loss, but Comment 3 retracted and identified Payments 2.0 migration. Do not act on Comment 2's conclusions." Empty if none.>
