---
description: Top-level dispatcher for the data-forge plugin. Routes to one of three workflows — fix (bug), enhancement (change to existing pipeline), or create (net-new pipeline) — based on engineer choice. Use this when the workflow isn't already obvious; otherwise call the specific command directly.
argument-hint: [<JIRA-KEY or freeform spec>] [<fix | enhancement | create>]
---

You are dispatching to one of three workflows in the `data-forge` plugin. Parse `$ARGUMENTS` as up to two whitespace-separated tokens:

- **First token (optional):** a Jira key (matches `[A-Z]+-\d+`) or a freeform spec / description.
- **Second token (optional):** the workflow mode — exactly one of `fix`, `enhancement`, or `create`. Case-insensitive.

If only one token is given, decide whether it's a Jira key, a description, or a mode:
- Matches `[A-Z]+-\d+` → it's a Jira key. Mode is unspecified.
- Matches `fix | enhancement | create` (case-insensitive) → it's the mode. Input is unspecified.
- Otherwise → treat it as a description / spec, mode unspecified.

If `$ARGUMENTS` is empty, both are unspecified.

## Decide the workflow

If the **mode** was given explicitly, use it. Skip to the dispatch step below.

If the mode was **not** given, ask:

> "Which workflow?
>
> **1. fix** — diagnose and fix a bug or data anomaly in an existing pipeline (`/data-issue-fix`)
> **2. enhancement** — implement a change, optimization, or new behavior on an existing pipeline (`/data-enhancement`)
> **3. create** — scaffold a net-new pipeline (config, code, or both) (`/data-creator`)
>
> (1 / 2 / 3, or `fix` / `enhancement` / `create`)"

Wait for the engineer's response. Map to the workflow:
- `1` or `fix` → fix
- `2` or `enhancement` → enhancement
- `3` or `create` → create

If the response is something else, re-ask.

## Dispatch

Once the workflow is determined, invoke the matching orchestrator agent **with the input** (the first token from `$ARGUMENTS`, if any):

- **fix** → invoke the `data-issue-fixer` orchestrator. If no input was provided, the orchestrator will ask for a Jira key or incident description.
- **enhancement** → invoke the `data-enhancement-driver` orchestrator. If no input was provided, the orchestrator will ask for a Jira key.
- **create** → invoke the `data-creator-driver` orchestrator. If no input was provided, the orchestrator will ask whether the engineer has a Jira ticket or wants to work from a freeform spec.

Hand the input through verbatim — don't paraphrase or restructure it. The orchestrators each read their inputs the way their underlying intake agent expects.

## Examples

- `/data-forge` — asks for input AND workflow.
- `/data-forge FIND-742` — asks for workflow only; passes the Jira key to the chosen orchestrator.
- `/data-forge fix` — asks for input only; routes to fix flow.
- `/data-forge FIND-742 enhancement` — no prompts; routes directly to enhancement flow with `FIND-742`.
- `/data-forge "build a daily settlement pipeline" create` — no prompts; routes to create flow with the spec as the input.

## Note

This dispatcher exists for discoverability — engineers who already know the workflow they want should call `/data-issue-fix`, `/data-enhancement`, or `/data-creator` directly to skip the dispatch prompt.
