#!/usr/bin/env bash
# Behaviour tests for scripts/station-run.sh --read-only. ShellCheck covers this
# file. A fake provider records where it ran and tries to write; no real
# provider is invoked and nothing contacts GitHub.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
pass() { echo "ok: $tname"; }

BIN=$work/bin
mkdir -p "$BIN"
OUT=$work/out

# Behaves like the reviewer did on #141: edits a test, stages it, commits it,
# then tries to push.
cat > "$BIN/opencode" << 'FAKE'
#!/usr/bin/env bash
if [[ "$*" == *--help* ]]; then printf '%s\n' "--auto --title --file"; exit 0; fi
{
  echo "cwd=$PWD"
  echo "origin=$(git remote get-url origin 2>&1 | head -1)"
  if sed -i.bak 's/^set -euo pipefail$/set -u/' scripts/station-run.sh 2>/dev/null; then
    echo "edited=yes"
  else
    echo "edited=no"
  fi
  git add -A > /dev/null 2>&1 && echo "staged=yes"
  git -c user.email=t@e.com -c user.name=t commit -q -m tamper > /dev/null 2>&1 && echo "committed=yes"
  git push origin HEAD > /dev/null 2>&1 && echo "pushed=yes" || echo "pushed=no"
} > "$FAKE_OUT"
exit 0
FAKE
chmod +x "$BIN/opencode"

run_ro() {
  PATH="$BIN:$PATH" FACTORY_PROVIDER=opencode FAKE_OUT="$OUT" \
    bash "$root_dir/scripts/station-run.sh" --read-only "$@" 2>&1
}

# Recorded before any station runs, so the origin check below can tell "the
# station removed it" from "there was never one here".
had_origin=no
if git -C "$root_dir" remote get-url origin > /dev/null 2>&1; then
  had_origin=yes
fi

tname="builder is refused --read-only"
out=$(PATH="$BIN:$PATH" FACTORY_PROVIDER=opencode \
  bash "$root_dir/scripts/station-run.sh" --read-only builder /dev/null 2>&1 || true)
[[ "$out" == *"builder cannot run --read-only"* ]] || fail "expected a refusal, got [$out]"
pass

tname="a read-only station runs outside the repo"
run_ro reviewer /dev/null > /dev/null
grep -q "^cwd=" "$OUT" || fail "fake provider never ran"
cwd=$(grep '^cwd=' "$OUT" | cut -d= -f2-)
[[ "$cwd" != "$root_dir" ]] || fail "station ran in the real repo: $cwd"
pass

tname="the read-only clone can still read its origin"
# Deliberately not removed: gh needs the remote to infer the repository, or the
# reviewer cannot read the pull request it is reviewing (#149).
want_origin=$(git -C "$root_dir" remote get-url origin)
grep -qxF "origin=$want_origin" "$OUT" \
  || fail "clone's fetch URL is not the source repo's ($want_origin): $(grep '^origin=' "$OUT")"
pass

tname="a write inside it cannot be pushed"
grep -qx "pushed=no" "$OUT" || fail "push was not refused"
pass

tname="its edits do not reach the repo"
grep -qx "edited=yes" "$OUT" || fail "the fake provider did not write, so this proves nothing"
grep -q '^set -euo pipefail$' "$root_dir/scripts/station-run.sh" \
  || fail "station-run.sh was modified by the station"
pass

# Regression: a linked worktree shares .git/config, so removing the worktree's
# origin removed the real repository's remote. That broke push while building
# #142. A clone keeps its own config.
tname="the read-only clone cannot push"
grep -qx "pushed=no" "$OUT" || fail "push was not refused"
pass

tname="the repo keeps its own origin afterwards"
if [[ "$had_origin" == "yes" ]]; then
  git -C "$root_dir" remote get-url origin > /dev/null 2>&1 \
    || fail "the real repository lost its origin remote"
  pass
else
  # The suite itself can run inside a read-only sandbox, which has no origin by
  # design, so there is nothing to lose. Checked before the station ran rather
  # than assumed.
  echo "skip: $tname (this checkout has no origin to begin with)"
fi

# A global remote.origin.pushurl survives into the clone alongside the blocked
# one, because pushurl is multi-valued, so git would push to it. Simulated
# through GIT_CONFIG_GLOBAL so the real user config is never touched.
tname="an inherited push URL is refused, not silently bypassed"
fake_global=$work/gitconfig
printf '[remote "origin"]\n\tpushurl = https://example.invalid/leak.git\n' > "$fake_global"
out=$(GIT_CONFIG_GLOBAL="$fake_global" PATH="$BIN:$PATH" FACTORY_PROVIDER=opencode \
  FAKE_OUT="$OUT" bash "$root_dir/scripts/station-run.sh" reviewer /dev/null 2>&1 || true)
[[ "$out" == *"inherited push URL would bypass"* ]] \
  || fail "expected a refusal, got [$out]"
[[ "$out" == *"example.invalid/leak.git"* ]] || fail "refusal did not name the URL"
pass

tname="the sandbox is cleaned up"
[[ ! -d "$cwd" ]] || fail "sandbox left behind at $cwd"
pass

# --- read-only is the default, not an opt-in (CodeRabbit, PR #143) ----------
run_plain() {
  PATH="$BIN:$PATH" FACTORY_PROVIDER=opencode FAKE_OUT="$OUT" \
    bash "$root_dir/scripts/station-run.sh" "$@" 2>&1
}

tname="a non-builder role is read-only with no flag"
rm -f "$OUT"
run_plain reviewer /dev/null > /dev/null
cwd=$(grep '^cwd=' "$OUT" | cut -d= -f2-)
[[ "$cwd" != "$root_dir" ]] || fail "reviewer ran in the real repo without --read-only"
# The sandbox is identified by its directory, not by a missing origin: the
# clone keeps a readable fetch URL on purpose (#149).
grep -qx "pushed=no" "$OUT" || fail "no sandbox: the push was not refused"
pass

tname="intake is read-only by default too"
rm -f "$OUT"
run_plain intake /dev/null > /dev/null
cwd=$(grep '^cwd=' "$OUT" | cut -d= -f2-)
[[ "$cwd" != "$root_dir" ]] || fail "intake ran in the real repo"
pass

tname="foreman is writable by default: it writes the work order"
rm -f "$OUT"
cat > "$BIN/opencode" << 'SAFE'
#!/usr/bin/env bash
if [[ "$*" == *--help* ]]; then printf '%s\n' "--auto --title --file"; exit 0; fi
printf 'cwd=%s\n' "$PWD" > "$FAKE_OUT"
exit 0
SAFE
chmod +x "$BIN/opencode"
run_plain foreman /dev/null > /dev/null
cwd=$(grep '^cwd=' "$OUT" | cut -d= -f2-)
[[ "$cwd" == "$root_dir" ]] || fail "foreman must run in the repo to write agents/work-orders/, ran in $cwd"
pass

tname="--writable opts out deliberately"
# A reporting-only provider for this one case: the default fake edits tracked
# files, and --writable runs in the real repository, so using it here would
# damage the checkout. It did exactly that once while this test was written.
cat > "$BIN/opencode" << 'SAFE'
#!/usr/bin/env bash
if [[ "$*" == *--help* ]]; then printf '%s\n' "--auto --title --file"; exit 0; fi
printf 'cwd=%s\n' "$PWD" > "$FAKE_OUT"
exit 0
SAFE
chmod +x "$BIN/opencode"
rm -f "$OUT"
# Compared before and after, not against HEAD: the checkout may legitimately
# have uncommitted edits while this suite runs.
before=$(cksum < "$root_dir/scripts/station-run.sh")
run_plain --writable reviewer /dev/null > /dev/null
cwd=$(grep '^cwd=' "$OUT" | cut -d= -f2-)
[[ "$cwd" == "$root_dir" ]] || fail "--writable should run in the repo, ran in $cwd"
[[ "$(cksum < "$root_dir/scripts/station-run.sh")" == "$before" ]] \
  || fail "the --writable case modified a tracked file"
pass

# --- an exported GIT_DIR must not redirect the sandbox's git calls -----------
# Without unsetting it, `git -C sandbox remote remove origin` can act on the
# caller's repository and strip the real remote.
tname="an exported GIT_DIR cannot reach the real repo"
probe=$work/probe
rm -rf "$probe"; mkdir -p "$probe"
# Stripped before the probe is built: an inherited GIT_DIR would make even
# `git init` act on that repository instead (git-scm.com, git(1)). The
# deliberate export below stays scoped to the run_plain call.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CEILING_DIRECTORIES
git -C "$probe" init -q -b main
git -C "$probe" config user.email t@e.com
git -C "$probe" config user.name t
git -C "$probe" commit -q --allow-empty -m base
git -C "$probe" remote add origin https://example.invalid/x.git
rm -f "$OUT"
GIT_DIR="$probe/.git" GIT_WORK_TREE="$probe" run_plain reviewer /dev/null > /dev/null
git -C "$probe" remote get-url origin > /dev/null 2>&1 \
  || fail "the station stripped the origin of the repo named by GIT_DIR"
pass

# --- a writable builder on a non-grok provider builds cross-repo (#171) ------
# Offline: FACTORY_CLONE_BASE points at a local fixture, not GitHub. The
# reporting-only fake never edits, commits or pushes; the real tree is
# checksummed before and after.
xr_base=$work/xr; mkdir -p "$xr_base/acme"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CEILING_DIRECTORIES
git init -q -b main "$xr_base/acme/widgets"
git -C "$xr_base/acme/widgets" -c user.email=t@e.com -c user.name=t \
  commit -q --allow-empty -m base
cat > "$BIN/opencode" << 'SAFE'
#!/usr/bin/env bash
if [[ "$*" == *--help* ]]; then printf '%s\n' "--auto --title --file"; exit 0; fi
{
  echo "cwd=$PWD"
  echo "gh_repo=${GH_REPO:-}"
  echo "push=$(git remote get-url --push --all origin 2>&1 | tr '\n' ' ')"
  echo "exists=yes"
} > "$FAKE_OUT"
exit 0
SAFE
chmod +x "$BIN/opencode"
mkwo() { printf -- '---\nrepo: %s\nissue: 1\n---\nbody\nrepo: other/ignored\n' "$1" > "$work/wo-$2.md"; }
run_xr() {
  PATH="$BIN:$PATH" FACTORY_PROVIDER=opencode FAKE_OUT="$OUT" \
    FACTORY_SELF_REPO=adamsuk/software-factory FACTORY_CLONE_BASE="$xr_base" \
    bash "$root_dir/scripts/station-run.sh" --work-order "$work/wo-$1.md" builder /dev/null 2>&1
}
tree_sum() { (cd "$root_dir" && git ls-files -z | xargs -0 cksum | cksum; git rev-parse HEAD); }

tname="a cross-repo builder runs in a clone with a real push URL"
mkwo acme/widgets xr
rm -f "$OUT"
before=$(tree_sum)
msg=$(run_xr xr)
cwd=$(grep '^cwd=' "$OUT" | cut -d= -f2-)
[[ "$cwd" != "$root_dir"* ]] || fail "ran inside this checkout: $cwd"
[[ "$msg" == *"writable clone of acme/widgets at $cwd"* ]] || fail "no directory notice: $msg"
grep -qx "gh_repo=acme/widgets" "$OUT" || fail "GH_REPO not exported"
grep -q "no-push://" "$OUT" && fail "inherited the no-push placeholder"
grep -q "push=$xr_base/acme/widgets " "$OUT" || fail "push URL is not the real remote: $(grep ^push= "$OUT")"
[[ "$(tree_sum)" == "$before" ]] || fail "this repo's working tree changed"
pass

# Changed deliberately (#177): this used to assert the clone was removed on exit,
# which destroyed a writable builder's committed work before anyone could read it.
tname="the cross-repo clone survives exit and its path is printed on stdout"
rm -f "$OUT"
out_stdout=$(PATH="$BIN:$PATH" FACTORY_PROVIDER=opencode FAKE_OUT="$OUT" \
  FACTORY_SELF_REPO=adamsuk/software-factory FACTORY_CLONE_BASE="$xr_base" \
  bash "$root_dir/scripts/station-run.sh" --work-order "$work/wo-xr.md" builder /dev/null 2> /dev/null)
cwd=$(grep '^cwd=' "$OUT" | cut -d= -f2-)
[[ "$(printf '%s\n' "$out_stdout" | tail -n1)" == "station-run: writable-clone-path $cwd" ]] \
  || fail "last stdout line is not the clone path line: $out_stdout"
[[ -d "$cwd/.git" ]] || fail "clone missing after exit: $cwd"
git -C "$cwd" -c user.email=t@e.com -c user.name=t commit -q --allow-empty -m work
rm -rf "$(dirname "$cwd")"
pass

tname="a work order naming this repo still runs in place"
mkwo adamsuk/software-factory self
rm -f "$OUT"
run_xr self > /dev/null
[[ "$(grep '^cwd=' "$OUT" | cut -d= -f2-)" == "$root_dir" ]] || fail "did not run in place"
pass

tname="an exported GIT_DIR cannot flip a cross-repo run to in place"
# No FACTORY_SELF_REPO: the origin lookup itself must ignore GIT_DIR. The probe
# claims to be acme/widgets, so a redirected lookup would run in place here.
xr_probe=$work/xr-probe; git init -q -b main "$xr_probe"
git -C "$xr_probe" remote add origin https://github.com/acme/widgets.git
rm -f "$OUT"
before=$(tree_sum)
msg=$(GIT_DIR="$xr_probe/.git" GIT_WORK_TREE="$xr_probe" PATH="$BIN:$PATH" \
  FACTORY_PROVIDER=opencode FAKE_OUT="$OUT" FACTORY_CLONE_BASE="$xr_base" \
  bash "$root_dir/scripts/station-run.sh" --work-order "$work/wo-xr.md" builder /dev/null 2>&1)
cwd=$(grep '^cwd=' "$OUT" | cut -d= -f2-)
[[ "$cwd" != "$root_dir"* && "$cwd" != "$xr_probe"* ]] || fail "ran in place: $cwd"
[[ "$msg" == *"writable clone of acme/widgets at $cwd"* ]] || fail "no clone notice: $msg"
[[ "$(tree_sum)" == "$before" ]] || fail "this repo's working tree changed"
pass

echo "all station-run read-only tests passed"

tname="prompt is read from the release ref, not the working tree"
rel=$work/rel
git clone -q "$root_dir" "$rel" 2> /dev/null || cp -R "$root_dir" "$rel"
cp "$root_dir/scripts/station-run.sh" "$rel/scripts/station-run.sh"
git -C "$rel" add -A > /dev/null
git -C "$rel" -c user.email=t@e.com -c user.name=t commit -q -m snapshot --allow-empty
git -C "$rel" -c user.email=t@e.com -c user.name=t tag -f v9.9.9 HEAD > /dev/null
echo "LIVE-ONLY-MARKER" >> "$rel/agents/roles/reviewer.md"
out=$(bash "$rel/scripts/station-run.sh" --dry-run reviewer /dev/null 2>&1)
[[ "$out" != *LIVE-ONLY-MARKER* ]] || fail "working-tree edit leaked into the prompt"
out=$(FACTORY_RELEASE_REF=nonexistent-ref bash "$rel/scripts/station-run.sh" --dry-run reviewer /dev/null 2>&1 || true)
[[ "$out" == *"does not resolve"* ]] || fail "bad FACTORY_RELEASE_REF not refused: [$out]"
pass

# --- a run survives its own scripts being rewritten mid-run (#174) -----------
tname="rewriting station-run.sh and the adapter mid-run does not disturb a read-only run"
fx=$work/fixture
mkdir -p "$fx/agents" "$fx/stations"
cp -R "$root_dir/scripts" "$root_dir/adapters" "$fx/"
cp "$root_dir/AGENTS.md" "$fx/AGENTS.md"
cp -R "$root_dir/agents/roles" "$fx/agents/roles"
cp "$root_dir/stations/github-writes.md" "$fx/stations/" 2> /dev/null || true
# A read-only run clones the checkout, so the fixture must be a git repo.
git -C "$fx" init -q
git -C "$fx" add -A > /dev/null
git -C "$fx" -c user.email=t@e.com -c user.name=t commit -q -m fixture
cat > "$BIN/opencode" << 'FAKE'
#!/usr/bin/env bash
if [[ "$*" == *--help* ]]; then printf '%s\n' "--auto --title --file"; exit 0; fi
# The read-only sandbox must exist while the provider runs.
echo "sandbox=$PWD" > "$FAKE_SANDBOX"
# Insert lines near the top of the running scripts, shifting every later byte
# offset, as a builder editing them would. The sandbox is read-only, so edit the
# fixture through its absolute path.
for f in "$FIXTURE"/scripts/station-run.sh "$FIXTURE"/adapters/opencode/run.sh; do
  sed -i.bak '2i\
echo CLOBBERED-FRAGMENT >&2; false; false; false
' "$f"
done
echo ran > "$FAKE_OUT"
exit 0
FAKE
chmod +x "$BIN/opencode"
rc=0
out=$(cd "$fx" && PATH="$BIN:$PATH" FACTORY_PROVIDER=opencode FAKE_OUT="$OUT" \
  FIXTURE="$fx" FAKE_SANDBOX="$work/sandbox-path" \
  bash "$fx/scripts/station-run.sh" reviewer /dev/null 2>&1) || rc=$?
[[ "$rc" -eq 0 ]] || fail "run failed ($rc): $out"
[[ -s "$OUT" ]] || fail "provider never ran: $out"
[[ "$out" != *CLOBBERED-FRAGMENT* && "$out" != *"command not found"* && "$out" != *"syntax error"* ]] \
  || fail "the edited script was executed: $out"
grep -q CLOBBERED-FRAGMENT "$fx/scripts/station-run.sh" || fail "the edit never landed, so this proves nothing"
[[ "$out" == *"execution path"*"changed in the working tree during this run"* ]] \
  || fail "no notice that the scripts changed: $out"
sandbox=$(sed -n 's/^sandbox=//p' "$work/sandbox-path" 2> /dev/null)
[[ "$sandbox" == /tmp/station-ro-* || "$sandbox" == */station-ro-*/* ]] \
  || fail "the run was not in a read-only sandbox: [$sandbox]"
sandbox_root=${sandbox%%/repo*}
[[ ! -e "$sandbox_root" ]] || fail "read-only sandbox not removed: $sandbox_root"
snap=$(sed -n 's/^station-run: running from snapshot //p' <<< "$out")
[[ -n "$snap" && ! -e "$snap" ]] || fail "snapshot not cleaned up: [$snap]"
pass

tname="the snapshot is removed when validation fails early"
before_snaps=$(find /tmp -maxdepth 1 -name 'station-snap-*' 2> /dev/null | LC_ALL=C sort)
out=$(bash "$root_dir/scripts/station-run.sh" --no-such-flag 2>&1 || true)
snap=$(sed -n 's/^station-run: running from snapshot //p' <<< "$out")
[[ -n "$snap" ]] || fail "never re-exec'd: $out"
[[ ! -e "$snap" ]] || fail "early exit leaked the snapshot: $snap"
after_snaps=$(find /tmp -maxdepth 1 -name 'station-snap-*' 2> /dev/null | LC_ALL=C sort)
[[ "$before_snaps" == "$after_snaps" ]] || fail "snapshot dirs leaked"
pass

echo "all station-run snapshot tests passed"
