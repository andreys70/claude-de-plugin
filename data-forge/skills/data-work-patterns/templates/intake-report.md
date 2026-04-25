# Intake Report — <TICKET-KEY>

## Ticket
- **Summary:** <one-line summary from Jira>
- **Status / Priority:** <status> / <priority>
- **Assignee / Reporter:** <name> / <name>
- **Labels:** <labels>
- **Dates:** created <date>, updated <date>, due <date or N/A>

## Problem statement
<2–4 sentences reproducing the problem in your words, grounded in the description>

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

## Current state
<One sentence: "newly reported" / "root cause identified, awaiting fix" / "fix deployed, awaiting verification" / etc.>

## Open questions / next step
- <bulleted list of what's unresolved, what needs probing>
- <suggested starting point for diagnosis>

## Red flags
<Anything inconsistent, contradictory, or that warrants caution — e.g., "Comment 2 concluded upstream data loss, but Comment 3 retracted and identified Payments 2.0 migration. Do not act on Comment 2's conclusions.">
