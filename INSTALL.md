# Installing and configuring handoff (instructions for an agent)

The user said something like "here's the handoff skill repo, configure it for all my agents", or "…for claude and codex". Follow these steps in order. Run the commands yourself; don't just print them.

**Assume nothing about this device.** Don't guess the user's repos, dotfiles layout, paths or preferences. Detect what you can, and ask about the rest. Needs `git` and `python3` 3.9 or newer.

## 1. Get the skill

If you're not already inside a clone of this repo, ask the user where to keep it. It has to be a permanent location, because the install symlinks to it; never use a temp dir. Then clone it there.

Below, `H=<clone>/bin/handoff`.

## 2. Install for the agents

Run `$H install` (every agent detected on this device) or `$H install --agents claude,codex` (just those). Show the user which agents were detected and where the skill was linked.

- Known agents: `claude`, `codex`, `opencode`, `cursor`, `agy`, `gemini`.
- If `CLAUDE_CONFIG_DIR` or `CODEX_HOME` is set, those dirs are used too. Ask whether the user runs any agent with another config dir (a second Claude profile, for example). If so, add `--skill-dir <that-dir>/skills`.
- **A target already exists and isn't this skill:** it is skipped. Tell the user. Only pass `--force` (backs it up, then replaces it) if they agree.
- `handoff` is linked into `~/.local/bin` by default. If that dir isn't on the user's PATH, ask where to put it (`--bin-dir`), or note that agents can call `bin/handoff` by its full path.

## 3. Onboarding

Walk the user through this conversationally: one short explanation, then the questions, about four at a time. Offer the default for each question so the user can just accept it.

### 3a. Explain (keep it short)

> Handoff moves an agent session to another session, here or on another device. You say `/handoff`. The agent writes a condensed context and a main prompt, pushes the work (branch or PR) when needed, and gives you one line to paste in the other session: `/handoff pickup <id>`.
>
> The handoffs and one shared config live in a folder inside a git repo you choose. Every device points at that same folder.

### 3b. Where the store lives

Ask:
1. **Which git repo should hold the handoffs, and which folder inside it?** Any repo the user syncs between devices works: a dotfiles or config repo, a notes repo, or a new dedicated one. Suggest `<repo>/handoff`.
   - Warn the user: handoffs contain task context. The repo should be **private**, unless they are sure that context can be public.
   - **The repo isn't on this device yet:** `$H init <dir> --clone <git-url> --clone-to <repo-dir>`
   - **They want a new repo:** offer to create it, e.g. `gh repo create <name> --private --clone`, then run init. Only create it after they confirm.
2. `$H init <repo>/<folder>`
   - It prints `[existing, shared]` if a config is already there. That means another device already set up the store: skip to 3d and only ask about per-device overrides.

### 3c. Defaults (shared by all devices)

Show the current values with `handoff config show`, then ask:

| Question | Key | Values (default first) |
|---|---|---|
| Where will you usually pick up handoffs? On another device, or in another session on this one? | `mode` | `remote` / `local` |
| How should your work reach the other session? Let the skill decide (a PR if the branch already has one, otherwise push the branch), always push the branch, always use a PR, or never push? | `checkpoint` | `auto` / `push` / `pr` / `none` |
| *(only if `pr` or `auto`)* Should new PRs start as drafts? Should the skill comment on the PR at each handoff? | `pr_draft`, `pr_comment` | `true`, `false` |
| Uncommitted work on a remote handoff: make a WIP commit, or stop and let you commit? | `wip` | `commit` / `refuse` |
| Uncommitted work on a same-device handoff: leave it in the working tree, commit it, or stop? | `local_wip` | `keep` / `commit` / `refuse` |
| WIP commit message? | `wip_message` | `wip(handoff): {slug}` |
| Push the store repo automatically? Only for remote handoffs, always, or never (you push)? | `store.push` | `auto` / `always` / `never` |
| Scan handoffs and WIP changes for secrets? | `secret_scan` | `true` |

Apply each answer with `handoff config set <key> <value>`. Also tell the user that any of these can be overridden per handoff by just saying it, e.g. "handoff via PR", "same device", or "don't push".

### 3d. This device

Ask whether this device should differ from the shared defaults. For example, a desktop where the user mostly hands off locally: `handoff config set --device mode local`. The override is stored in the same config file, under `[devices.<hostname>]`.

### 3e. Save

Show the final `handoff config show`. Then ask whether to commit and push the config: `handoff config save --push`. Without `--push` it only commits. It commits only `config.toml`; nothing else in the repo is touched.

## 4. Check

Run `handoff doctor` and report the results. Every detected agent should show the skill as installed, the store should be found, and the store remote should be reachable. `gh auth` is only needed for PR checkpoints.

Tell the user:
- Restart any open agent sessions so they load the skill.
- **On each other device:** clone this skill repo and tell that device's agent "configure the handoff skill from <repo>". The shared config is picked up automatically, so only the store location and per-device questions come up.
- Try it: `/handoff` in a session, then `/handoff pickup` in the other one.

## Uninstall

```sh
handoff uninstall           # remove the skill links from every agent, and the CLI link
handoff uninstall --purge   # also forget this device's store pointer (~/.config/handoff)
```

It only removes symlinks that point into this skill. The store, its config and its handoffs stay in the user's repo; delete that folder yourself only if the user asks.
