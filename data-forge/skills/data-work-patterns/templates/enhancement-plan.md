# Enhancement plan — <TICKET-KEY>

> Output of the orchestrator's Phase 2 (scope & change plan). The engineer
> reviews and approves this **before** the coder writes any code.

## Ask (lifted from the Jira)
<one or two sentences summarizing what the ticket asks for>

## In scope
- <bullet — concrete change>
- <bullet>

## Out of scope
- <bullet — things the ticket might imply but you're explicitly NOT doing>
- <bullet>

## Files to touch
| Path | Why |
|---|---|
| <path> | <one-sentence reason> |
| <path> | ... |

## Proposed change (one line per file)
- `<path>` — <verb + concise description: "add column X derived from Y", "modify join from inner to left outer", "extend filter to include Z">

## Acceptance criteria (used by the validator post-PRF)
1. <criterion — single testable statement>
2. <criterion>
3. ...

## Assumptions
- <assumption made because the Jira was silent on something — engineer should confirm>

## Risks / things to watch at PRF
- <e.g. cardinality preserved? downstream consumers of SELECT * affected? row count expected to move?>
