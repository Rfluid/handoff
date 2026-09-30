---
name: handoff
description: Hand off the current coding session to another agent session, on this device or another one, or pick up a handoff. Use when the user says "handoff", "hand this off", "continue on my laptop/other machine", "move this session", "pick up the handoff", or runs /handoff [pickup|list|verify|close|setup|config]. Writes a condensed context + main prompt to a git-backed store, checkpoints the work (branch push or PR) as needed, and checks the other session can reach everything.
---

# handoff

Moves a session to another session. Two sides:

- **Give** (`/handoff`, "hand this off to my laptop"): write a condensed handoff and make sure the receiver can reach it.
- **Take** (`/handoff pickup [ref]`): pull the handoff, put the repo on the right branch and commit, then work from the main prompt.

The `handoff` CLI does git, transport and checks. You do the writing and the judgment calls. If `handoff` is not on PATH, run `bin/handoff` from the directory that contains this SKILL.md. If it says "not configured", follow **Setup** below.

## Arguments

`/handoff [give|pickup|list|verify|close|setup|config] [ref] [local|remote] [pr|push|branch <name>|no-push] [to <agent>]`

- No subcommand means **give**. Free-form words work too, e.g. "handoff to my laptop via a PR".
- `local` means the receiver is on this device. `remote` means another device.
- `pr`, `push`, `branch <name>` and `no-push` choose the checkpoint (see below).
- `ref` is `project/id`, `id`, or `latest` (the default).

Anything the user states wins over the config. For anything they didn't state, use the config (`handoff config show`).

## Deciding the checkpoint

The checkpoint is how the work itself reaches the receiver.

| User says / situation | Do |
|---|---|
| "via PR", "open a PR", "update the PR" | `--checkpoint pr` (plus `--ready` or `--pr-base <b>` if they said so) |
| "just push", "push the branch" | `--checkpoint push` |
| "on branch X", "use branch X" | `--branch X` (moves the work there, committed and uncommitted), then push, or `pr` if they asked |
| "don't push", "keep it local" | `--mode local --checkpoint none` |
| Nothing said | leave it to config. The default `auto` means: remote → `pr` if the branch already has an open PR, otherwise `push`; local → `none` |
| On `main`/`master` with uncommitted work, remote | don't push WIP there. Propose a branch name, and ask the user unless the config or their words already decide. Then `--branch <name>` |

Report which checkpoint you used and why, in one line.

## Give

1. **Create the draft** from inside the project repo:
   ```sh
   handoff new --slug <short-task-name> --mode <local|remote> --agent <claude|codex|cursor|agy|opencode|gemini> [--to <agent>]
   ```
   It prints the handoff dir, which holds `PROMPT.md`, `CONTEXT.md`, `manifest.json` and `context/`.

2. **Write `CONTEXT.md`.** Replace every `TODO(handoff)` and condense:
   - Only what the next session can't get from the code, `git log` or the diff: goal, state, decisions and why, dead ends, gotchas, and what's left.
   - No transcript, no replaying the conversation, no pasted diffs, no long logs. Summarize and point to files or commits.
   - Stay under about 150 lines. `publish` warns above 12 KB.
   - Use repo-relative paths only. For `remote`, device paths like `/home/...` or `~/...` fail the check.
   - Write env var **names** only, never values, and never secrets. The secret scan blocks publishing.

3. **Write `PROMPT.md`.** This is the receiving agent's entry point. Replace every `TODO(handoff)`: the title, what to read, commands that confirm the state (with their expected output), the next step, the finish line, and the user's rules. Leave the `handoff:auto` block alone. `publish` fills it with the repo, branch, commit, PR and clone steps.

4. **Put useful files in `context/`,** but only if they help and can't be regenerated: a short failing-test excerpt, an API response sample, a design note, a spec the user pasted. Keep them small and list each one in `PROMPT.md` step 1. Leave the folder empty if nothing qualifies.

5. **Publish** from inside the project repo:
   ```sh
   handoff publish <project/id> [--checkpoint auto|none|push|pr] [--branch <name>] [--pr-base <b>] [--draft|--ready] \
     [--wip commit|refuse|keep] [--manual-file .env]
   ```
   In order:
   1. Checks the content: templates filled, size, device paths, secrets. Nothing is committed if these fail.
   2. Handles uncommitted work. With `remote`, it makes a WIP commit on the branch. With `local`, it leaves the shared tree alone by default.
   3. Runs the checkpoint: `push` pushes the branch; `pr` also makes sure a PR exists and records its URL.
   4. Commits only the handoff's own paths in the store repo, and pushes them for `remote`.
   5. Checks the receiver can reach it: branch on the remote at the right commit, store pushed, and a fresh clone of the store sees the handoff.

   When `publish` stops:
   - **It refuses a WIP commit on main/master:** use `--branch` (see the table above), or `--allow-default-branch` if the user says so.
   - **The store repo has unrelated unpushed commits:** tell the user. Pass `--push-extra` only if they agree.
   - **Anything else fails:** fix the cause and re-run `publish`. It is safe to re-run. Don't use `--force` unless the user asks.
   - **The task needs files git ignores** (`.env`, local certs): pass `--manual-file`. They are listed for the receiver, never copied.

6. **Report** the check summary and the paste line `publish` printed (`/handoff pickup <project/id>`). That line is all the user needs in the other session.

## Take (pickup)

1. Run this from inside the project repo if it exists on this device. Otherwise run it anywhere and add `--clone-to <dir>`:
   ```sh
   handoff pickup [ref] --agent <your agent name>
   ```
   It pulls the store and finds the handoff. Without a ref, it takes the latest open one for the current repo, or the newest overall. It fetches the branch, switches to it, fast-forwards to the handoff commit, and prints the **main prompt**.
   - **Same device, and the source session still has that branch checked out:** pickup refuses. Ask whether the other session has stopped. If both keep running, use `handoff pickup <ref> --worktree ../<repo>-<slug>`, which gives you a new branch in a separate worktree. Then work in that dir.
   - **The local tree is dirty or has diverged:** stop and ask the user. Never discard their changes.
2. Read the printed prompt, then `CONTEXT.md` and `context/` in the handoff dir it printed.
3. Follow the prompt. Run its "confirm the state" commands first.
4. When the task is done, run `handoff close <ref>`. If you stop before it's done, do **Give** again.

## Other commands

- `handoff list [--all]`: list open handoffs across projects.
- `handoff verify [ref]`: re-run every check.
- `handoff close [ref]`: mark a handoff done.
- `handoff config show | set <key> <value> [--device] | save [--push]`: the one shared config.
- `handoff doctor`: check this device's setup.

## Setup

Follow `INSTALL.md` next to this file. It installs the skill for the user's agents and walks the user through onboarding for the config.
