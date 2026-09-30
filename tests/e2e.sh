#!/usr/bin/env bash
# End-to-end: two simulated devices (separate HOMEs), local bare repos as "GitHub",
# a fake `gh` for PR checkpoints. Touches nothing outside a temp dir.
set -euo pipefail

H="$(cd "$(dirname "$0")/.." && pwd)/bin/handoff"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false
unset HANDOFF_STORE CLAUDE_CONFIG_DIR CODEX_HOME

# fake gh: PRs are files in $T/prs
mkdir -p "$T/fakebin" "$T/prs"
cat > "$T/fakebin/gh" <<'EOF'
#!/usr/bin/env bash
d="$FAKE_GH_DIR"
case "$1 $2" in
  "pr view") b="${3//\//_}"; [ -f "$d/$b" ] && cat "$d/$b"; exit 0 ;;
  "pr create") while [ $# -gt 0 ]; do [ "$1" = --head ] && b="${2//\//_}"; shift; done
               echo "https://example.test/pr/$b" > "$d/$b"; echo "$*" > "$d/$b.args"; cat "$d/$b" ;;
  "pr comment") echo "$*" >> "$d/comments" ;;
  "auth status") exit 0 ;;
esac
EOF
chmod +x "$T/fakebin/gh"
export PATH="$T/fakebin:$PATH" FAKE_GH_DIR="$T/prs"

pass() { echo "PASS: $*"; }
die() { echo "FAIL: $*" >&2; exit 1; }
expect_fail() { if "$@" >"$T/out" 2>&1; then cat "$T/out"; die "expected failure: $*"; fi; }
fill() { perl -pi -e 's/TODO\(handoff\)/filled/g' "$@"; }
ref_of() { sed -n 's#^created .*/handoff/\(.*\)$#\1#p'; }

# --- remotes: a project, and a generic synced repo that will hold the store in a subfolder
git init -q --bare "$T/gh/proj.git"
git init -q --bare "$T/gh/dotfiles.git"
seed() { git clone -q "$1" "$T/seed" 2>/dev/null && (cd "$T/seed" && eval "$2" && git add -A && git commit -qm init && git push -q origin main) && rm -rf "$T/seed"; }
seed "$T/gh/proj.git" 'echo "print(1)" > app.py'
seed "$T/gh/dotfiles.git" 'mkdir nvim && echo x > nvim/init.lua'

# --- device A
A() { HOME="$T/A" HANDOFF_HOST=devA XDG_CONFIG_HOME="$T/A/.config" "$@"; }
mkdir -p "$T/A"
A git clone -q "$T/gh/dotfiles.git" "$T/A/dots"
A git clone -q "$T/gh/proj.git" "$T/A/proj"
A "$H" init "$T/A/dots/handoff" | grep -q "created from template" || die "config not created"
A "$H" config set checkpoint push >/dev/null
A "$H" config set pr_draft false >/dev/null
A "$H" config set --device mode remote >/dev/null
expect_fail A "$H" config set mode sideways
expect_fail A "$H" config set nope 1
A "$H" config show | grep -q 'defaults.checkpoint *= "push"' || die "config set/show"
grep -q '^checkpoint  = "push" ' "$T/A/dots/handoff/config.toml" || die "comment layout lost"
grep -q '\[devices.devA.defaults\]' "$T/A/dots/handoff/config.toml" || die "device section"
HANDOFF_TOML_FALLBACK=1 A "$H" config show | grep -q 'defaults.pr_draft *= false' || die "fallback parser"
A "$H" config save --push | grep -q pushed || die "config save"
A "$H" config set checkpoint auto >/dev/null && A "$H" config save --push >/dev/null
pass "init + config show/set/save (+ validation, device override, fallback parser)"

cd "$T/A/proj"
A git switch -qc feat/login
echo "def login(): pass" > login.py
echo "unrelated" > "$T/A/dots/nvim/dirty.lua"

REF=$(A "$H" new --slug login --mode remote --agent claude | ref_of)
[ -n "$REF" ] || die "no ref"
HD="$T/A/dots/handoff/$REF"

expect_fail A "$H" publish "$REF"
grep -q "templates filled" "$T/out" || die "template check missing"
[ -z "$(A git ls-remote "$T/gh/proj.git" refs/heads/feat/login)" ] || die "pushed despite failed content check"
pass "unfilled templates block publish"

fill "$HD/PROMPT.md" "$HD/CONTEXT.md"
echo "see $T/A/proj/app.py" >> "$HD/CONTEXT.md"
expect_fail A "$H" publish "$REF"
grep -q "no device-local paths" "$T/out" || { cat "$T/out"; die "abs path not caught"; }
perl -ni -e 'print unless /^see /' "$HD/CONTEXT.md"
pass "device path blocks remote publish"

echo 'aws_key = "AKIAABCDEFGHIJKLMNOP"' > "$HD/context/notes.txt"
expect_fail A "$H" publish "$REF"
grep -q "no secrets" "$T/out" || { cat "$T/out"; die "secret not caught"; }
echo "failing test: test_login expects 200" > "$HD/context/notes.txt"
pass "secret blocks publish"

expect_fail A "$H" publish "$REF" --checkpoint none
grep -q "remote handoff needs" "$T/out" || die "none+remote allowed"
pass "checkpoint none refused for remote"

A "$H" publish "$REF" --manual-file .env > "$T/pub" || { cat "$T/pub"; die "publish failed"; }
grep -q "/handoff pickup $REF" "$T/pub" || die "no paste line"
grep -q "checkpoint push" "$T/pub" || die "auto should resolve to push (no PR)"
grep -q "cold clone sees handoff" "$T/pub" || die "no cold check"
[ "$(A git log -1 --format=%s)" = "wip(handoff): login" ] || die "no wip commit"
[ -n "$(A git ls-remote "$T/gh/proj.git" refs/heads/feat/login)" ] || die "branch not pushed"
A git -C "$T/A/dots" log -1 --name-only | grep -q dirty.lua && die "store commit touched unrelated file"
[ -f "$T/A/dots/nvim/dirty.lua" ] || die "unrelated file lost"
pass "remote publish: auto→push, wip commit, branch + store pushed, unrelated dirt untouched"

# --- device B
B() { HOME="$T/B" HANDOFF_HOST=devB XDG_CONFIG_HOME="$T/B/.config" "$@"; }
mkdir -p "$T/B"
B "$H" init "$T/B/dots/handoff" --clone "$T/gh/dotfiles.git" --clone-to "$T/B/dots" | grep -q existing || die "B did not reuse config"
B "$H" config show | grep -q 'defaults.checkpoint *= "auto"' || die "B config not shared"
cd "$T/B"
B "$H" pickup --clone-to "$T/B/proj" > "$T/pick" || { cat "$T/pick"; die "pickup failed"; }
grep -q "MAIN PROMPT" "$T/pick" || die "no prompt printed"
grep -q "copy by hand.*\.env" "$T/pick" || die "manual file not surfaced"
[ -f "$T/B/proj/login.py" ] || die "wip not on B"
[ "$(B git -C "$T/B/proj" rev-parse --abbrev-ref HEAD)" = feat/login ] || die "wrong branch on B"
pass "pickup on other device (latest, clone, branch, prompt)"

cd "$T/B/proj"
B "$H" verify "$REF" >/dev/null || die "verify on B"
B "$H" close "$REF" >/dev/null
B "$H" list | grep -q "no handoffs" || die "closed still listed"
pass "verify + close on B"

# --- PR checkpoint from B, then auto picks PR when one exists
echo "more" >> login.py
REFP=$(B "$H" new --slug pr-one --mode remote | ref_of)
fill "$T/B/dots/handoff/$REFP/"*.md
B "$H" publish "$REFP" --checkpoint pr --ready > "$T/pubp" || { cat "$T/pubp"; die "pr publish"; }
grep -q "https://example.test/pr/feat_login" "$T/pubp" || die "pr url not reported"
grep -q -- "--draft" "$T/prs/feat_login.args" && die "--ready ignored"
grep -q "example.test/pr" "$T/B/dots/handoff/$REFP/PROMPT.md" || die "PR not in prompt"
B "$H" close "$REFP" >/dev/null
echo "again" >> login.py
REFQ=$(B "$H" new --slug auto-pr | ref_of)
fill "$T/B/dots/handoff/$REFQ/"*.md
B "$H" publish "$REFQ" > "$T/pubq" || { cat "$T/pubq"; die "auto pr publish"; }
grep -q "checkpoint pr" "$T/pubq" || die "auto did not pick existing PR"
B "$H" close "$REFQ" >/dev/null
pass "checkpoint pr (--ready) and auto→pr when branch has an open PR"

# --- main branch guard, then --branch
cd "$T/A/proj"
A git switch -q main
A git -C "$T/A/dots" pull -q
echo "x" > hot.txt
REF2=$(A "$H" new --slug hot --mode remote | ref_of)
fill "$T/A/dots/handoff/$REF2/"*.md
expect_fail A "$H" publish "$REF2"
grep -q "refusing to push a WIP commit to .main." "$T/out" || { cat "$T/out"; die "main guard"; }
A "$H" publish "$REF2" --branch fix/hot > "$T/pub2" || { cat "$T/pub2"; die "--branch publish"; }
[ "$(A git rev-parse --abbrev-ref HEAD)" = fix/hot ] || die "--branch not switched"
[ -n "$(A git ls-remote "$T/gh/proj.git" refs/heads/fix/hot)" ] || die "--branch not pushed"
[ -z "$(A git ls-remote "$T/gh/proj.git" refs/heads/main | grep "$(A git rev-parse HEAD)")" ] || die "main was pushed"
A "$H" close "$REF2" >/dev/null
pass "default-branch guard + --branch moves work to a new branch"

# --- same device, local
A git switch -q feat/login
A git pull -q --ff-only origin feat/login
echo "wip2" > wip2.py
REF3=$(A "$H" new --slug local-one --mode local | ref_of)
fill "$T/A/dots/handoff/$REF3/"*.md
before=$(A git -C "$T/A/dots" rev-parse origin/main)
A "$H" publish "$REF3" > "$T/pub3" || { cat "$T/pub3"; die "local publish"; }
grep -q "checkpoint none" "$T/pub3" || die "local auto should be none"
[ -f wip2.py ] && [ -n "$(A git status --porcelain)" ] || die "local wip should stay in tree"
A git -C "$T/A/dots" fetch -q
[ "$before" = "$(A git -C "$T/A/dots" rev-parse origin/main)" ] || die "local mode pushed store"
pass "local publish (auto→none, tree kept, nothing pushed)"

cd "$T/A"
A "$H" pickup "$REF3" > "$T/pick3" || { cat "$T/pick3"; die "local pickup"; }
grep -q "work repo:   $T/A/proj" "$T/pick3" || die "local pickup did not find repo"
pass "local pickup (sequential, same dir)"

A git -C "$T/A/proj" stash -q -u
A git -C "$T/A/proj" switch -q main
A git -C "$T/A/proj" worktree add -q "$T/A/proj-other" feat/login
cd "$T/A/proj"
expect_fail A "$H" pickup "$REF3"
grep -q "checked out in another worktree" "$T/out" || { cat "$T/out"; die "worktree conflict not detected"; }
A "$H" pickup "$REF3" --worktree "$T/A/proj-par" > "$T/pick4" || { cat "$T/pick4"; die "worktree pickup"; }
[ "$(A git -C "$T/A/proj-par" rev-parse --abbrev-ref HEAD)" = "feat/login-local-one" ] || die "worktree branch"
pass "local pickup parallel (worktree)"

# --- install / uninstall into fake HOME
A "$H" install --agents claude,codex,agy,cursor --skill-dir "$T/A/.claude-work/skills" >/dev/null
for d in .claude/skills .agents/skills .gemini/config/skills .cursor/skills .claude-work/skills; do
  [ -f "$T/A/$d/handoff/SKILL.md" ] || die "install $d"
done
[ -x "$T/A/.local/bin/handoff" ] || die "cli link"
mkdir -p "$T/A/.cursor/skills-other" && echo mine > "$T/A/.cursor/skills-other/keep"
A "$H" uninstall --skill-dir "$T/A/.claude-work/skills" --purge >/dev/null
for d in .claude/skills .agents/skills .gemini/config/skills .cursor/skills .claude-work/skills; do
  [ ! -e "$T/A/$d/handoff" ] || die "uninstall $d"
done
[ ! -e "$T/A/.local/bin/handoff" ] || die "cli link not removed"
[ ! -e "$T/A/.config/handoff/store" ] || die "purge"
[ -f "$T/A/dots/handoff/config.toml" ] || die "uninstall touched the store"
[ -f "$T/A/.cursor/skills-other/keep" ] || die "uninstall touched unrelated files"
pass "install / uninstall --purge (store untouched)"

echo "ALL PASS"
