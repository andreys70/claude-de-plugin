# Diagnosis — <TICKET-KEY>

## Anomaly reproduced
<SQL + result showing the anomaly, with actual numbers. Brief table if useful.>

## Root cause
<1–2 sentence statement of the root cause, specific enough to inform a code fix.>

## Evidence
<Tables, sample values, or query outputs that prove the root cause.>

## Candidates considered and ruled out

| Candidate | Ruled out by | Evidence |
| --- | --- | --- |
| <hypothesis> | <query/check> | <result> |
| ... | ... | ... |

## Proposed fix approach
<Code-level description of what needs to change — function names, join predicates, file paths. NOT actual code.>

## Risks / edge cases
<What could go wrong with the proposed fix? Cardinality blowup? Pre-period rows affected? Schema drift?>

## Verification plan
<What queries should be run post-deploy to confirm the fix worked.>

## Not in scope of this ticket
<If the investigation uncovered additional bugs / dead code / cleanup candidates, list them here as "separate ticket" candidates. Do not include them in the proposed fix.>
