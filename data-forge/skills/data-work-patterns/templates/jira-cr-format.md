# CR format template — default

**Before using this template**, check whether the engineer has a personal CR format memory at `~/.claude/projects/*/memory/feedback_cr_format.md`. If present, that file supersedes this template.

---

## CR - Change Request

**Ticket:** <JIRA_KEY>
**PD Ticket:** <PD_NUMBER — omit if not provided>
**Branch:** `<BRANCH_NAME>`

---

### What is changing?

<Brief description of the change, 2–3 sentences. Include what tables/columns are affected.>

### Why is it changing?

<Root cause and motivation. Cite the diagnosis findings. Include business impact if known — declined transactions, lost revenue, wrong decisions being made on the data.>

### How is it changing?

- <Bullet point describing a specific code change>
- <Bullet point describing a specific code change>
- <Bullet point describing a specific code change>
- <If relevant, note code that was intentionally NOT changed (dead paths, cleanup deferred to separate ticket)>

### Files Changed

- `<file path 1>`
- `<file path 2>`

### Risk Assessment

- **Risk Level:** <Low / Medium / High>
- **Impact:** <Who/what is affected? Is the change additive or replacing existing logic? Are historical rows affected or only new rows?>
- **Rollback:** <How to revert — e.g., "Revert commit <SHA> on <branch> and rerun the transform. No downstream schema dependency on the new CTE.">

### Testing

<Validation steps / queries. Mix of pre-deploy testing (dev/PRF runs) and planned post-deploy verification.>

- <Test 1>
- <Test 2>
- <Post-deploy check>
