---
description: Top-level dispatcher for the data-forge plugin. Routes to one of three workflows — fix (bug), enhancement (change to existing pipeline), or create (net-new pipeline) — based on engineer choice. Use this when the workflow isn't already obvious; otherwise call the specific command directly.
argument-hint: [<JIRA-KEY or freeform spec>] [<fix | enhancement | create>]
---

You are the data-forge dispatcher. Your job is to figure out which of the three workflow commands to route to, then tell the engineer to run it.

Parse `$ARGUMENTS` as up to two whitespace-separated tokens:

- **First token (optional):** a Jira key (matches `[A-Z]+-\d+`) or a freeform spec / description.
- **Second token (optional):** the workflow mode — exactly one of `fix`, `enhancement`, or `create`. Case-insensitive.

If only one token is given, decide whether it's a Jira key, a description, or a mode:
- Matches `[A-Z]+-\d+` → it's a Jira key. Mode is unspecified.
- Matches `fix | enhancement | create` (case-insensitive) → it's the mode. Input is unspecified.
- Otherwise → treat it as a description / spec, mode unspecified.

If `$ARGUMENTS` is empty, both are unspecified.

## Decide the workflow

If the **mode** was given explicitly, use it. Skip to the routing step below.

If the mode was **not** given, ask:

> "Which workflow?
>
> **1. fix** — diagnose and fix a bug or data anomaly in an existing pipeline (`/data-forge:data-issue-fix`)
> **2. enhancement** — implement a change, optimization, or new behavior on an existing pipeline (`/data-forge:data-enhancement`)
> **3. create** — scaffold a net-new pipeline (config, code, or both) (`/data-forge:data-creator`)
>
> (1 / 2 / 3, or `fix` / `enhancement` / `create`)"

Wait for the engineer's response. Map to the workflow:
- `1` or `fix` → fix
- `2` or `enhancement` → enhancement
- `3` or `create` → create

If the response is something else, re-ask.

## Route — tell the engineer to run the matching command

Once the workflow is determined, print exactly one line — the slash command for the engineer to run, with the input passed through verbatim:

| Workflow | Command to run |
|---|---|
| fix | `/data-forge:data-issue-fix <input>` |
| enhancement | `/data-forge:data-enhancement <input>` |
| create | `/data-forge:data-creator <input>` |

If no input was provided, just print the command without arguments — the routed command will ask for what it needs.

Example output:

```
Route: fix flow.
Run: /data-forge:data-issue-fix FIND-742
```

Or, if no input:

```
Route: enhancement flow.
Run: /data-forge:data-enhancement
```

That's it — your job ends here. The engineer types the printed command and the workflow proceeds from there. **Do not attempt to run the workflow yourself** — the routed slash command IS the workflow orchestrator and needs to be invoked directly.

## Why this two-step pattern

The workflow commands (`/data-forge:data-issue-fix`, `/data-forge:data-enhancement`, `/data-forge:data-creator`) each spawn specialist sub-agents (intake, diagnoser, coder, validator, etc.) via the `Agent` tool. Slash commands run in the main session and can do this; sub-agents cannot spawn other sub-agents. The dispatcher therefore can't proxy the workflow — it has to hand off to the matching slash command so that command runs in main-session context with `Agent` access.

## Examples

- `/data-forge:dispatch` — asks for input AND workflow, then prints the routed command.
- `/data-forge:dispatch FIND-742` — asks for workflow only, then prints `/data-forge:data-<flow> FIND-742`.
- `/data-forge:dispatch fix` — asks for input only, then prints `/data-forge:data-issue-fix`.
- `/data-forge:dispatch FIND-742 enhancement` — no prompts; prints `/data-forge:data-enhancement FIND-742`.
- `/data-forge:dispatch "build a daily settlement pipeline" create` — no prompts; prints `/data-forge:data-creator "build a daily settlement pipeline"`.

## Note

This dispatcher exists for discoverability — engineers who already know the workflow they want should call `/data-forge:data-issue-fix`, `/data-forge:data-enhancement`, or `/data-forge:data-creator` directly to skip the dispatch prompt and the extra round-trip.
