# Intuit Data Engineering — Claude Code Plugins

A Claude Code marketplace of plugins for Intuit data engineers.

## Plugins

| Plugin | Purpose | Docs |
|---|---|---|
| **data-forge** | End-to-end data-issue resolution for ETL codebases — Jira intake, diagnosis, code fix, PRF validation, BPP run, post-deploy verification. | [data-forge/README.md](data-forge/README.md) |
| **auditpath** | End-to-end SOX pipeline onboarding — JIRA intake, DM + DQ conf generation, BPP registration, validation, and close-out. Domain-agnostic. | [auditpath/README.md](auditpath/README.md) |
| **pii-minimization** | End-to-end IDPS encryption rollout — Phase 1 decrypt-on-read and Phase 2 encrypt-on-write across RDA BPP, QuickETL, SPP, Report Requestor, and Quickbase pipelines. Includes Redshift widening gate. | [pii-minimization/README.md](pii-minimization/README.md) |

## Install

Add this marketplace in Claude Code, then install any plugin from it. See each plugin's README for usage.

```bash
# Quick install (one command per plugin)
bash pii-minimization/install.sh
bash auditpath/install.sh

# Or manually
claude plugin marketplace add ~/Documents/GitHub/claude-de-plugins
claude plugin install pii-minimization@intuit-de
```

## Maintainers

- data-forge — Andrey Suvorov (andrey_suvorov@intuit.com)
- auditpath — Praveen Kurup (praveen_kurup@intuit.com)
- pii-minimization — Rashmi Nalwad (rashmi_nalwad@intuit.com)
