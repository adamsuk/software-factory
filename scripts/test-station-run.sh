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

# Every run that reaches a provider starts a container (#424). The fake runtime
# starts none: it records its argv and runs the adapter with only the
# environment a container would get. FAKE_RUNTIME_PASS names this harness's own
# recording paths, which a real container would not see.
cp "$here/fixtures/fake-container-runtime.sh" "$BIN/podman"
chmod +x "$BIN/podman"
RUNTIME_LOG=$work/runtime.log
export FACTORY_CONTAINER_RUNTIME="$BIN/podman" FACTORY_CONTAINER_IMAGE=factory-station:test \
  FACTORY_CONTAINER_NETWORK=factory-egress-test FAKE_RUNTIME_LOG="$RUNTIME_LOG" \
  FAKE_RUNTIME_PASS="FAKE_OUT FIXTURE FAKE_SANDBOX"
# Stand-ins, never real credentials: station-run refuses to start without them.
export GH_TOKEN=test-gh-token OPENCODE_API_KEY=test-opencode-key
unset FACTORY_CONTAINER_PROXY FACTORY_GH_APP_ID FACTORY_GH_APP_INSTALLATION_ID FACTORY_GH_APP_KEY_FILE \
  CLAUDE_CODE_OAUTH_TOKEN XAI_API_KEY OPENROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY GH_REPO

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

tname="auditor is read-only with no flag"
rm -f "$OUT"
# HEAD, not the latest v* tag: the tag predates agents/roles/auditor.md.
FACTORY_RELEASE_REF=HEAD run_plain auditor /dev/null > /dev/null
cwd=$(grep '^cwd=' "$OUT" | cut -d= -f2-)
[[ "$cwd" != "$root_dir" ]] || fail "auditor ran in the real repo without --read-only"
grep -qx "pushed=no" "$OUT" || fail "no sandbox: the push was not refused"
pass

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
    FACTORY_SELF_REPO=acme/software-factory FACTORY_CLONE_BASE="$xr_base" \
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
  FACTORY_SELF_REPO=acme/software-factory FACTORY_CLONE_BASE="$xr_base" \
  bash "$root_dir/scripts/station-run.sh" --work-order "$work/wo-xr.md" builder /dev/null 2> /dev/null)
cwd=$(grep '^cwd=' "$OUT" | cut -d= -f2-)
[[ "$(printf '%s\n' "$out_stdout" | tail -n1)" == "station-run: writable-clone-path $cwd" ]] \
  || fail "last stdout line is not the clone path line: $out_stdout"
[[ -d "$cwd/.git" ]] || fail "clone missing after exit: $cwd"
git -C "$cwd" -c user.email=t@e.com -c user.name=t commit -q --allow-empty -m work
rm -rf "$(dirname "$cwd")"
pass

tname="a work order naming this repo still runs in place"
mkwo acme/software-factory self
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
out=$(bash "$root_dir/scripts/station-run.sh" --no-such-flag 2>&1 || true)
snap=$(sed -n 's/^station-run: running from snapshot //p' <<< "$out")
[[ -n "$snap" ]] || fail "never re-exec'd: $out"
[[ ! -e "$snap" ]] || fail "early exit leaked the snapshot: $snap"
pass

echo "all station-run snapshot tests passed"

# --- every station runs in the container, or not at all (#424) ---------------
cat > "$BIN/opencode" << 'FAKE'
#!/usr/bin/env bash
if [[ "$*" == *--help* ]]; then printf '%s\n' "--auto --title --file"; exit 0; fi
{
  echo "cwd=$PWD"
  echo "marker=${FACTORY_STATION_CONTAINER:-}"
  echo "host_only=${HOST_ONLY_SENTINEL:-}"
  echo "key_file=${FACTORY_GH_APP_KEY_FILE:-}"
  echo "gh_token=${GH_TOKEN:+set}"
  echo "opencode_key=${OPENCODE_API_KEY:+set}"
  echo "claude_token=${CLAUDE_CODE_OAUTH_TOKEN:+set}"
  echo "xai_key=${XAI_API_KEY:+set}"
  echo "proxy=${HTTPS_PROXY:-}"
  echo "model=${FACTORY_MODEL:-}"
} > "$FAKE_OUT"
exit 0
FAKE
chmod +x "$BIN/opencode"
run_c() {
  PATH="$BIN:$PATH" FACTORY_PROVIDER=opencode FAKE_OUT="$OUT" \
    bash "$root_dir/scripts/station-run.sh" "$@" 2>&1
}
last_run() { tail -n 1 "$RUNTIME_LOG"; }

tname="a station is started through the runtime, on the restricted network"
rm -f "$OUT"; : > "$RUNTIME_LOG"
HOST_ONLY_SENTINEL=must-not-arrive FACTORY_GH_APP_KEY_FILE=/nonexistent/app-key.pem \
  CLAUDE_CODE_OAUTH_TOKEN=other-provider XAI_API_KEY=other-provider FACTORY_MODEL=test-model \
  FACTORY_CONTAINER_PROXY=http://egress-proxy:8888 run_c reviewer /dev/null > /dev/null
[[ $(wc -l < "$RUNTIME_LOG") -eq 1 ]] || fail "expected one container start, got $(wc -l < "$RUNTIME_LOG")"
argv=" $(last_run) "
[[ "$argv" == " run --rm "* ]] || fail "the container is not disposable: $argv"
[[ "$argv" == *" --network factory-egress-test "* ]] || fail "the container is not on the restricted network"
[[ "$argv" == *" --cap-drop ALL "* ]] || fail "capabilities were not dropped"
[[ "$argv" == *" --tmpfs /factory-home "* && "$argv" == *" --env HOME=/factory-home "* ]] \
  || fail "HOME is not an empty tmpfs"
[[ "$argv" == *" factory-station:test "* ]] || fail "the image is not FACTORY_CONTAINER_IMAGE"
# Never root: Claude Code refuses to run with approval off as root, and rootless
# podman maps the caller to root unless told to keep the id.
[[ "$argv" == *" --user $(id -u):$(id -g) "* ]] || fail "the container does not run as the calling user"
[[ "$argv" == *" --userns keep-id "* ]] || fail "podman would map the calling user to container root"
pass

tname="the container gets the marker, the proxy and its own credentials, and nothing else of the host"
grep -qx "marker=1" "$OUT" || fail "the adapter was not told it is in the container"
grep -qx "proxy=http://egress-proxy:8888" "$OUT" || fail "the proxy was not set"
grep -qx "model=test-model" "$OUT" || fail "FACTORY_MODEL was not forwarded"
grep -qx "gh_token=set" "$OUT" || fail "GH_TOKEN was not forwarded"
grep -qx "opencode_key=set" "$OUT" || fail "the provider's own credential was not forwarded"
grep -qx "host_only=" "$OUT" || fail "a host-only variable reached the adapter"
grep -qx "key_file=" "$OUT" || fail "the App key file path reached the adapter"
grep -qx "claude_token=" "$OUT" || fail "another provider's credential was forwarded"
grep -qx "xai_key=" "$OUT" || fail "another provider's credential was forwarded"
pass

tname="no credential value is on the runtime's argv"
if grep -q -e test-gh-token -e test-opencode-key -e other-provider "$RUNTIME_LOG"; then
  fail "a credential value was passed on argv"
fi
pass

tname="a read-only station's container cannot see the real checkout"
cwd=$(grep '^cwd=' "$OUT" | cut -d= -f2-)
[[ "$argv" == *" --volume $cwd:$cwd "* ]] || fail "the throwaway clone is not mounted"
[[ "$argv" != *" --volume $root_dir:"* ]] || fail "the real checkout is mounted for a read-only station"
[[ $(grep -o -- ' --volume [^ ]*:ro' <<< "$argv" | wc -l) -eq 2 ]] \
  || fail "expected exactly the snapshot and the bundle read-only: $argv"
pass

tname="a writing station gets the real checkout"
rm -f "$OUT"; : > "$RUNTIME_LOG"
run_c foreman /dev/null > /dev/null
argv=" $(last_run) "
[[ "$argv" == *" --volume $root_dir:$root_dir "* ]] || fail "the foreman's container does not mount the checkout"
pass

expect_9() { # label, then the environment for the run
  local label=$1; shift
  local code=0 out
  rm -f "$OUT"; : > "$RUNTIME_LOG"
  out=$(env "$@" PATH="$BIN:$PATH" FACTORY_PROVIDER=opencode FAKE_OUT="$OUT" \
    bash "$root_dir/scripts/station-run.sh" reviewer /dev/null 2>&1) || code=$?
  [[ $code -eq 9 ]] || fail "$label exited $code, want 9: $out"
  [[ "$out" == *"cannot start a container"* ]] || fail "$label did not say it cannot start a container: $out"
  [[ ! -e "$OUT" ]] || fail "$label still ran the provider"
  [[ ! -s "$RUNTIME_LOG" ]] || fail "$label still started a container"
}

tname="no image, no network, an ordinary network or a missing one is exit 9"
expect_9 "no image" FACTORY_CONTAINER_IMAGE=
expect_9 "no network" FACTORY_CONTAINER_NETWORK=
expect_9 "bridge network" FACTORY_CONTAINER_NETWORK=bridge
expect_9 "host network" FACTORY_CONTAINER_NETWORK=host
expect_9 "a network that is not internal" FAKE_RUNTIME_NET=external
expect_9 "a network that does not exist" FAKE_RUNTIME_NET=missing
expect_9 "a runtime that is not installed" FACTORY_CONTAINER_RUNTIME=no-such-runtime
expect_9 "a proxy URL with credentials" FACTORY_CONTAINER_PROXY=http://user:pass@proxy:8888
pass

tname="no provider credential or no GitHub token is exit 9"
expect_9 "no provider credential" OPENCODE_API_KEY=
expect_9 "no GitHub token" GH_TOKEN=
pass

tname="--dry-run needs no container"
: > "$RUNTIME_LOG"
out=$(env FACTORY_CONTAINER_IMAGE= FACTORY_CONTAINER_NETWORK= GH_TOKEN= OPENCODE_API_KEY= \
  PATH="$BIN:$PATH" FACTORY_PROVIDER=opencode bash "$root_dir/scripts/station-run.sh" --dry-run reviewer /dev/null 2>&1) \
  || fail "--dry-run failed without container settings: $out"
[[ "$out" == *"=== PROMPT BUNDLE ==="* ]] || fail "--dry-run printed no bundle"
[[ ! -s "$RUNTIME_LOG" ]] || fail "--dry-run started a container"
pass

tname="the grok builder is handed over unwrapped: run-work-order.sh starts its own container"
: > "$RUNTIME_LOG"
gfx=$work/grok-fixture
mkdir -p "$gfx/agents" "$gfx/stations"
cp -R "$root_dir/scripts" "$root_dir/adapters" "$gfx/"
cp "$root_dir/AGENTS.md" "$gfx/AGENTS.md"
cp -R "$root_dir/agents/roles" "$gfx/agents/roles"
cp "$root_dir/stations/github-writes.md" "$gfx/stations/"
# shellcheck disable=SC2016  # the stub's literal text
printf '#!/usr/bin/env bash\necho "run-work-order marker=${FACTORY_STATION_CONTAINER:-none} args=$*"\n' > "$gfx/scripts/run-work-order.sh"
git -C "$gfx" init -q
git -C "$gfx" add -A > /dev/null
git -C "$gfx" -c user.email=t@e.com -c user.name=t commit -q -m fixture
mkwo acme/software-factory grok
out=$(cd "$gfx" && env XAI_API_KEY= GH_TOKEN= FACTORY_CONTAINER_IMAGE= PATH="$BIN:$PATH" \
  bash "$gfx/scripts/station-run.sh" --provider grok --work-order "$work/wo-grok.md" builder /dev/null 2>&1) \
  || fail "the grok builder hand-over failed: $out"
[[ "$out" == *"run-work-order marker=none args=$work/wo-grok.md"* ]] || fail "run-work-order.sh was not called directly: $out"
[[ ! -s "$RUNTIME_LOG" ]] || fail "station-run wrapped the grok builder in a container"
pass

# --- scripts/station-container.sh: the same container for other callers ------
wrap="$root_dir/scripts/station-container.sh"
probe=$work/probe
mkdir -p "$probe"
printf 'x\n' > "$work/ro-file"

tname="station-container.sh runs the command in the container"
: > "$RUNTIME_LOG"
out=$(HOST_ONLY_SENTINEL=must-not-arrive FACTORY_MODEL=test-model PATH="$BIN:$PATH" bash "$wrap" \
  --provider opencode --workdir "$probe" --forward FACTORY_MODEL --ro "$work/ro-file" --ro "$probe" -- \
  bash -c 'echo "cwd=$PWD marker=${FACTORY_STATION_CONTAINER:-} model=${FACTORY_MODEL:-} host=${HOST_ONLY_SENTINEL:-} gh=${GH_TOKEN:-}"')
[[ "$out" == "cwd=$probe marker=1 model=test-model host= gh=" ]] || fail "unexpected view from inside: $out"
argv=" $(last_run) "
[[ "$argv" == *" --volume $work/ro-file:$work/ro-file:ro "* ]] || fail "the read-only path is not mounted read-only"
[[ $(grep -o -- " --volume $probe:" <<< "$argv" | wc -l) -eq 1 ]] || fail "the workdir was mounted twice"
[[ "$argv" == *" --network factory-egress-test "* ]] || fail "not on the restricted network"
pass

tname="station-container.sh keeps the command's exit code and starts nothing on exit 9"
code=0
PATH="$BIN:$PATH" bash "$wrap" --provider opencode --workdir "$probe" -- bash -c 'exit 7' || code=$?
[[ $code -eq 7 ]] || fail "exit code was $code, want 7"
for setting in FACTORY_CONTAINER_IMAGE= FACTORY_CONTAINER_NETWORK= FACTORY_CONTAINER_NETWORK=bridge OPENCODE_API_KEY=; do
  code=0; : > "$RUNTIME_LOG"
  env "$setting" PATH="$BIN:$PATH" bash "$wrap" --provider opencode --workdir "$probe" -- true > /dev/null 2>&1 || code=$?
  [[ $code -eq 9 ]] || fail "$setting exited $code, want 9"
  [[ ! -s "$RUNTIME_LOG" ]] || fail "$setting still started a container"
done
pass

tname="station-container.sh rejects bad arguments"
for bad in "--workdir relative/dir" "--workdir $work/no-such-dir" "--workdir $probe --forward BAD=NAME" "--workdir $probe --ro $work/no-such-file"; do
  code=0
  # shellcheck disable=SC2086  # $bad is a list of arguments, split on purpose
  PATH="$BIN:$PATH" bash "$wrap" --provider opencode $bad -- true > /dev/null 2>&1 || code=$?
  [[ $code -eq 2 ]] || fail "[$bad] exited $code, want 2"
done
code=0
PATH="$BIN:$PATH" bash "$wrap" --provider opencode --workdir "$probe" > /dev/null 2>&1 || code=$?
[[ $code -eq 2 ]] || fail "no command exited $code, want 2"
pass

tname="station-container.sh mounts --rw read-write and --ro read-only"
mkdir -p "$work/orders"
: > "$RUNTIME_LOG"
PATH="$BIN:$PATH" bash "$wrap" --provider opencode --workdir "$probe" --rw "$work/orders" --ro "$work/ro-file" -- true
argv=" $(last_run) "
[[ "$argv" == *" --volume $work/orders:$work/orders "* ]] || fail "--rw is not mounted read-write"
[[ "$argv" == *" --volume $work/ro-file:$work/ro-file:ro "* ]] || fail "--ro lost its read-only flag"
code=0
PATH="$BIN:$PATH" bash "$wrap" --provider opencode --workdir "$probe" --rw "$work/ro-file" -- true > /dev/null 2>&1 || code=$?
[[ $code -eq 2 ]] || fail "--rw on a file exited $code, want 2"
pass

# --- grok: its binary and its login (#428) -----------------------------------
printf '#!/usr/bin/env bash\nexit 0\n' > "$work/grok-bin"
chmod +x "$work/grok-bin"
printf 'login-file-sentinel\n' > "$work/grok-auth.json"
run_grok_wrap() { PATH="$BIN:$PATH" bash "$wrap" --provider grok --workdir "$probe" -- true; }

tname="grok with XAI_API_KEY mounts no login file"
: > "$RUNTIME_LOG"
XAI_API_KEY=test-xai-key FACTORY_GROK_AUTH_FILE="$work/grok-auth.json" run_grok_wrap
argv=" $(last_run) "
[[ "$argv" == *" --env XAI_API_KEY "* ]] || fail "XAI_API_KEY is not forwarded by name"
[[ "$argv" != *"auth.json"* ]] || fail "the login file was mounted although a key exists"
[[ "$argv" != *"test-xai-key"* ]] || fail "the key value is on argv"
pass

tname="grok with no key mounts the login file read-only in its own empty ~/.grok"
: > "$RUNTIME_LOG"
FACTORY_GROK_AUTH_FILE="$work/grok-auth.json" run_grok_wrap
argv=" $(last_run) "
[[ "$argv" == *" --volume $work/grok-auth.json:/factory-home/.grok/auth.json:ro "* ]] || fail "the login file is not mounted read-only: $argv"
[[ "$argv" == *" --tmpfs /factory-home/.grok "* ]] || fail "grok's home is not its own tmpfs"
[[ "$argv" != *"login-file-sentinel"* ]] || fail "the login file's content is on argv"
pass

tname="grok with neither a key nor a login file is exit 9"
code=0; : > "$RUNTIME_LOG"
run_grok_wrap > /dev/null 2>&1 || code=$?
[[ $code -eq 9 ]] || fail "exited $code, want 9"
code=0
FACTORY_GROK_AUTH_FILE="$work/no-such-auth.json" run_grok_wrap > /dev/null 2>&1 || code=$?
[[ $code -eq 9 ]] || fail "a missing login file exited $code, want 9"
[[ ! -s "$RUNTIME_LOG" ]] || fail "a container was started without a grok credential"
pass

tname="FACTORY_GROK_BIN is mounted read-only on PATH, and only for grok"
: > "$RUNTIME_LOG"
XAI_API_KEY=test-xai-key FACTORY_GROK_BIN="$work/grok-bin" run_grok_wrap
[[ " $(last_run) " == *" --volume $work/grok-bin:/usr/local/bin/grok:ro "* ]] || fail "the grok binary is not mounted read-only"
: > "$RUNTIME_LOG"
FACTORY_GROK_BIN="$work/grok-bin" FACTORY_GROK_AUTH_FILE="$work/grok-auth.json" \
  PATH="$BIN:$PATH" bash "$wrap" --provider opencode --workdir "$probe" -- true
argv=" $(last_run) "
[[ "$argv" != *"/usr/local/bin/grok"* && "$argv" != *"auth.json"* ]] || fail "another provider's container got grok's binary or login"
code=0
XAI_API_KEY=test-xai-key FACTORY_GROK_BIN="$work/no-such-grok" run_grok_wrap > /dev/null 2>&1 || code=$?
[[ $code -eq 9 ]] || fail "a missing FACTORY_GROK_BIN exited $code, want 9"
pass

echo "all station-run container tests passed"
