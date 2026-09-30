# handoff

Move a coding-agent session to another session: on **another device**, or **another session on the same device**. Works with Claude Code, Codex, Cursor, Antigravity (agy), opencode and Gemini CLI.

```
session A                                   session B
─────────                                   ─────────
/handoff                                    /handoff pickup <project>/<id>
  → agent writes condensed CONTEXT.md         → pulls the store
    + main PROMPT.md (+ context/ files)       → clones/fetches the repo, switches branch,
  → checkpoints the work: push or PR            fast-forwards to the handoff commit
  → commits (and pushes) the handoff          → prints the main prompt, agent continues
  → checks the other side can reach it
  → prints: /handoff pickup <project>/<id>
```

## Configure with your agent

Paste this into any supported agent:

> Configure the handoff skill from https://github.com/Rfluid/handoff for all my coding agents. Follow its `INSTALL.md`.

Or, for specific agents only:

> Configure the handoff skill from https://github.com/Rfluid/handoff for claude and codex. Follow its `INSTALL.md`.

The agent clones the repo and installs the skill for your agents. It then walks you through onboarding:

1. Which git repo and folder holds your handoffs. Any repo you sync works, e.g. a dotfiles repo.
2. Your defaults: mode, checkpoint (branch push or PR), how to handle uncommitted work, store pushing.
3. Anything specific to this device.

Do the same on every device. They share one config, stored with the handoffs.

## Manual install

```sh
git clone https://github.com/Rfluid/handoff ~/somewhere/handoff
~/somewhere/handoff/bin/handoff install                 # all detected agents
~/somewhere/handoff/bin/handoff install --agents claude,codex
handoff init <repo-you-sync>/handoff                            # point this device at the store
handoff config show                                             # review defaults
handoff config set checkpoint pr                                # change any of them
handoff config save --push                                      # commit (+ push) config.toml only
handoff doctor
```

Requirements: `git`, `python3` 3.9 or newer. Optional: `gh` for PR checkpoints, and `gitleaks` for better secret scanning (a regex fallback is built in). Runs on Linux and macOS. On Windows, use WSL.

## Uninstall

```sh
handoff uninstall           # remove skill links from every agent + the CLI link
handoff uninstall --purge   # also forget this device's store pointer (~/.config/handoff)
```

Only symlinks that point into this repo are removed. Your store folder, its config and its handoffs stay in your repo. Delete that folder by hand if you want them gone, then delete the clone of this repo.

If `handoff` isn't on your PATH, run `<clone>/bin/handoff uninstall`.

## Usage

In the session you're leaving, say `/handoff`, or in plain words:

- "hand this off to my laptop"
- "handoff, same device"
- "handoff via PR"
- "handoff on branch feat/x"
- "handoff, don't push"

In the other session, paste the printed line: `/handoff pickup <project>/<id>`. With no id, it takes the latest open handoff for the current repo.

| Command | What it does |
|---|---|
| `handoff new` | Creates a draft handoff for the current repo. The agent fills in the templates |
| `handoff publish [ref]` | Checks → WIP commit → checkpoint → store commit/push → reachability checks → paste line |
| `handoff pickup [ref]` | Pulls the store, puts the repo in position, prints the main prompt |
| `handoff verify [ref]` | Re-runs all checks |
| `handoff list` / `close [ref]` | Lists open handoffs / marks one done |
| `handoff config show\|set\|save` | The one shared config |
| `handoff install` / `uninstall` / `doctor` | Setup |

### Checkpoint: how the work reaches the receiver

Set it per handoff (`--checkpoint`, or just say it) or in the config:

- `auto` (default): remote handoff → `pr` if the branch already has an open PR, otherwise `push`. Local handoff → `none`.
- `push`: WIP-commit uncommitted work and push the current branch.
- `pr`: `push`, plus make sure a PR exists (draft by default). Its URL goes in the handoff.
- `none`: nothing is pushed. Same device only.
- `--branch <name>`: first moves the work to a new branch.

No branches are created unless you ask. The skill never WIP-pushes to `main`/`master` without `--allow-default-branch`.

### Same device

Local mode leaves uncommitted work in the shared working tree and pushes nothing. If the first session is still running on the branch, run `handoff pickup <ref> --worktree <dir>`. That starts the second session in its own worktree on its own branch.

## Where things live

```
<your repo>/<store folder>/
  config.toml                     # one config, shared by all devices ([devices.<host>] for overrides)
  <project>/LATEST
  <project>/<id>/PROMPT.md        # main prompt: entry point for the receiving agent
  <project>/<id>/CONTEXT.md       # condensed context
  <project>/<id>/context/         # small useful files (samples, excerpts, notes)
  <project>/<id>/manifest.json    # repo, branch, sha, PR, mode, checks, pickups
~/.config/handoff/store           # per-device pointer to the store folder
```

Store commits only touch the handoff's own paths. Other changes in your repo are left alone. Pushing stops if the repo has unrelated unpushed commits.

## Safety checks

Before anything is committed or pushed, `publish` fails on:

- templates left unfilled
- device-local paths in a remote handoff
- secrets in the handoff or in the WIP changes

After pushing, it checks that:

- the branch is on the remote at the handoff commit
- the store is pushed
- a fresh clone of the store sees the handoff

Keep the store repo private: handoffs describe your work.

## Tests

```sh
bash tests/e2e.sh   # two simulated devices, local bare repos, temp HOMEs; touches nothing real
```
