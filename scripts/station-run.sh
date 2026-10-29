#!/usr/bin/env bash
# Provider-agnostic station runner for software factory
# Assembles canonical AGENTS.md + agents/roles/<role>.md and context, then
# delegates to the selected provider via adapters.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "station-run: $2" >&2; exit "$1"; }

usage() {
  cat >&2 << 'EOF'
Usage: scripts/station-run.sh [options] <role> <context>
Options:
  --provider <name>   Provider adapter to use (opencode|grok|claudecode|custom). Default: $FACTORY_PROVIDER or opencode
  --work-order <path> Path to work order file
  --issue <n>         Issue number
  --repo <owner/repo> Repo context
  --dry-run           Print composed prompt bundle without invoking provider
  --writable          Let the station change the real repo. The reading roles
                      (intake, research, reviewer, monitor) are read-only by
                      default and this is the deliberate escape. builder and
                      foreman write by design and are unaffected.
  --read-only         Run the station in a throwaway clone with no remote, so
                      file writes are discarded and there is nothing to push to.
                      Committed state only: uncommitted changes are not copied.
                      For roles that must not change the repo (see
                      stations/README.md, "Which roles may write").
  --help              Show this help
EOF
  exit 2
}

provider="${FACTORY_PROVIDER:-opencode}"
dry_run=false
read_only=""   # empty: decide from the role. Only builder writes.
work_order=""
issue=""
repo_ctx=""
context_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      [[ $# -ge 2 ]] || die 2 "missing value for --provider"
      provider="$2"; shift 2;;
    --work-order)
      [[ $# -ge 2 ]] || die 2 "missing value for --work-order"
      [[ -f "$2" ]] || die 2 "work order not found: $2"
      work_order="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
      shift 2;;
    --issue)
      [[ $# -ge 2 ]] || die 2 "missing value for --issue"
      issue="$2"; shift 2;;
    --repo)
      [[ $# -ge 2 ]] || die 2 "missing value for --repo"
      repo_ctx="$2"; shift 2;;
    --dry-run)
      dry_run=true; shift;;
    --read-only)
      read_only=true; shift;;
    --writable)
      read_only=false; shift;;
    --help)
      usage;;
    -*)
      die 2 "unknown option: $1";;
    *)
      break;;
  esac
done

[[ $# -ge 2 ]] || usage
role="$1"
context_path="$2"
shift 2

# Validate role exists in canonical roles
role_file="$here/agents/roles/${role}.md"
[[ -f "$role_file" ]] || die 2 "unknown role: $role (missing $role_file)"

agents_md="$here/AGENTS.md"
[[ -f "$agents_md" ]] || die 2 "missing $agents_md"
[[ -f "$here/stations/github-writes.md" ]] || die 2 "missing stations/github-writes.md"

# Build context bundle
bundle_dir="$(mktemp -d /tmp/station-bundle-XXXXXX)"
trap 'rm -rf "$bundle_dir"' EXIT  # replaced by cleanup_station once a sandbox may exist

# Copy canonical files
cp "$agents_md" "$bundle_dir/AGENTS.md"
cp "$role_file" "$bundle_dir/ROLE.md"

# Create context file with metadata
{
  echo "# Station Context"
  echo "role: $role"
  echo "provider: $provider"
  [[ -n "$issue" ]] && echo "issue: $issue"
  [[ -n "$repo_ctx" ]] && echo "repo: $repo_ctx"
  [[ -n "$work_order" ]] && echo "work_order: $work_order"
  echo "---"
  echo
} > "$bundle_dir/CONTEXT.md"

# Include work order if provided
if [[ -n "$work_order" && -f "$work_order" ]]; then
  {
    echo "# Work Order"
    echo
    cat "$work_order"
    echo
  } >> "$bundle_dir/CONTEXT.md"
fi

# Include additional context
if [[ -n "$context_path" && -f "$context_path" ]]; then
  {
    echo "# Additional Context"
    echo
    cat "$context_path"
    echo
  } >> "$bundle_dir/CONTEXT.md"
elif [[ -n "$context_path" && -d "$context_path" ]]; then
  # Could be a directory of context files
  for f in "$context_path"/*.md "$context_path"/*.txt; do
    [[ -f "$f" ]] || continue
    {
      echo "# Context: $(basename "$f")"
      echo
      cat "$f"
      echo
    } >> "$bundle_dir/CONTEXT.md"
  done
fi

# Compose full prompt
prompt_bundle="$bundle_dir/PROMPT.md"
{
  echo "<system>"
  echo "# Canonical Rules"
  echo
  cat "$bundle_dir/AGENTS.md"
  echo
  echo "# Role: $role"
  echo
  cat "$bundle_dir/ROLE.md"
  echo
  echo "# GitHub writes"
  echo
  cat "$here/stations/github-writes.md"
  echo
  echo "</system>"
  echo
  echo "<context>"
  cat "$bundle_dir/CONTEXT.md"
  echo
  echo "</context>"
} > "$prompt_bundle"

if $dry_run; then
  echo "=== DRY RUN ==="
  echo "role: $role"
  echo "provider: $provider"
  echo "bundle: $prompt_bundle"
  echo "=== PROMPT BUNDLE ==="
  cat "$prompt_bundle"
  exit 0
fi

# Invoke adapter
adapter="$here/adapters/$provider/run.sh"
if [[ ! -x "$adapter" ]]; then
  # Try to find adapter
  adapter="$here/adapters/$provider/run"
  if [[ ! -x "$adapter" ]]; then
    die 2 "no adapter found for provider '$provider' at $here/adapters/$provider/run.sh"
  fi
fi

# A read-only station runs in a throwaway clone with its origin removed, so an
# edit it makes under its working directory is thrown away and it has nothing to
# push to.
#
# This is weaker than a boundary, and stations/README.md says so. It does not
# deny access to the original checkout: the providers run with blanket approval,
# and the work order's absolute path is in the prompt, so an agent can still
# write to the real tree by absolute path. Real isolation is #44. API writes are
# not blocked either, since the agent holds the caller's gh credentials (#7).
# Read-only is the default for every role that is not the builder. CodeRabbit
# found this on PR #143: with read_only defaulting to false, a direct
# `station-run.sh reviewer /dev/null` handed the real repository to the adapter,
# and only `foreman-orchestrate.sh review` opted in. The boundary now applies to
# direct callers, and `--writable` is the explicit way out.
# Named list, not "everything except builder". CodeRabbit found on PR #149 that
# "everything except builder" broke the foreman: it writes the work order to
# agents/work-orders/ (agents/roles/foreman.md step 3), so a disposable clone
# would take it away and the later gate run, which needs that file, would have
# nothing to read.
case "$role" in
  intake|research|reviewer|monitor) reads_only=true ;;
  *) reads_only=false ;;
esac
if [[ -z "$read_only" ]]; then
  read_only=$reads_only
fi

workdir="$here"
ro_sandbox=""
xr_sandbox=""
cleanup_station() {
  local st=$?
  # Only the read-only clone: the writable cross-repo clone holds the builder's
  # work and is never deleted here.
  [[ -z "$ro_sandbox" ]] || rm -rf "$ro_sandbox"
  rm -rf "$bundle_dir"
  return "$st"
}

# Installed before anything can create the sandbox: a die between the clone and
# the end of the block would otherwise leave /tmp/station-ro-* behind, because
# the earlier trap only removes the bundle.
trap cleanup_station EXIT

if $read_only; then
  [[ "$role" != "builder" ]] || die 2 "builder cannot run --read-only: it exists to change the repo"
  command -v git > /dev/null 2>&1 || die 2 "git not found in PATH"

  # An exported GIT_DIR or GIT_WORK_TREE would make the git calls below act on
  # the caller's repository instead of the clone, so `remote remove origin`
  # could strip the real remote. That exact damage happened once already while
  # building #142, by a different route.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CEILING_DIRECTORIES
  head_sha=$(git -C "$here" rev-parse HEAD) || die 7 "could not read HEAD"
  ro_sandbox="$(mktemp -d /tmp/station-ro-XXXXXX)"
  # A clone, not a worktree. A linked worktree shares .git/config with the real
  # repository, so removing the worktree's origin removes the repository's own
  # remote. That happened while building #142 and broke push until origin was
  # added back. A clone has its own config, so dropping origin there is local.
  git clone --quiet --local --no-hardlinks --no-checkout "$here" "$ro_sandbox/repo" \
    || die 7 "could not create the read-only clone"
  git -C "$ro_sandbox/repo" checkout --quiet --detach "$head_sha" \
    || die 7 "could not check out $head_sha in the read-only clone"
  # Keep origin's fetch URL and break only its push URL. Removing the remote
  # outright blinded the reviewer: gh infers the repository from the remote, so
  # from inside the sandbox it could not read the pull request, CI, or
  # CodeRabbit's comments — which is exactly what AGENTS.md section 10.4 asks it
  # to review against. Found by the reviewer on PR #149.
  #
  # This stops an accidental push, not a determined one: an agent can still push
  # to an explicit URL. The boundary's real limits are in stations/README.md.
  origin_url=$(git -C "$here" remote get-url origin 2>/dev/null || true)
  if [[ -n "$origin_url" ]]; then
    git -C "$ro_sandbox/repo" remote set-url origin "$origin_url" > /dev/null 2>&1 \
      || die 7 "could not set the read-only clone's fetch URL"
  fi
  # pushurl is multi-valued and inherits from global config, so a global
  # remote.origin.pushurl survives alongside the blocked one and git pushes to
  # both. Confirmed by experiment. Clear the local list, set the blocked URL,
  # then verify it is the only one and refuse to run if it is not.
  git -C "$ro_sandbox/repo" config --unset-all remote.origin.pushurl > /dev/null 2>&1 || true
  git -C "$ro_sandbox/repo" remote set-url --push origin \
    "no-push://blocked-by-read-only-station" > /dev/null 2>&1 \
    || die 7 "could not block pushes from the read-only clone"
  effective_push=$(git -C "$ro_sandbox/repo" remote get-url --push --all origin 2>/dev/null \
    | grep -v '^no-push://blocked-by-read-only-station$' || true)
  if [[ -n "$effective_push" ]]; then
    die 7 "inherited push URL would bypass the read-only station: ${effective_push//$'\n'/ }. Remove remote.origin.pushurl from your global git config."
  fi
  workdir="$ro_sandbox/repo"
  echo "station-run: read-only clone of ${head_sha:0:7} at $workdir (push blocked)" >&2
fi

# A writable builder on opencode or claudecode builds in a clone of the repo the
# work order names (#171). grok does its own clone in run-work-order.sh, and a
# work order naming this repo keeps running in place. This path is separate from
# the read-only one on purpose: it must keep a real push URL, so it shares none
# of that block's no-push wiring or its guard.
if ! $read_only && [[ "$role" == "builder" && "$provider" != "grok" && -n "$work_order" ]]; then
  # Before any git call: an exported GIT_DIR or GIT_COMMON_DIR would redirect the
  # origin lookup below, and self_repo decides whether this runs in place.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CEILING_DIRECTORIES
  # Only the front matter's repo line, not a later `repo:` in the body.
  target_repo=$(awk 'NR==1 && $0=="---"{fm=1;next} fm&&$0=="---"{exit} fm&&/^repo:/{sub(/^repo:[ \t]*/,"");gsub(/["\047 \r]/,"");print;exit}' "$work_order")
  self_repo="${FACTORY_SELF_REPO:-}"
  if [[ -z "$self_repo" ]]; then
    self_repo=$(git -C "$here" remote get-url origin 2>/dev/null \
      | sed -E 's#(\.git)?/?$##; s#^.*[:/]([^/:]+/[^/:]+)$#\1#' || true)
  fi
  if [[ -n "$target_repo" && "$target_repo" != "$self_repo" ]]; then
    [[ "$target_repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] \
      || die 2 "work order repo is not owner/repo: $target_repo"
    command -v git > /dev/null 2>&1 || die 2 "git not found in PATH"
    xr_sandbox="$(mktemp -d /tmp/station-xr-XXXXXX)"
    git clone --quiet "${FACTORY_CLONE_BASE:-https://github.com}/$target_repo" "$xr_sandbox/repo" \
      || die 7 "could not clone $target_repo"
    workdir="$xr_sandbox/repo"
    repo_ctx="$target_repo"
    echo "station-run: writable clone of $target_repo at $workdir" >&2
  fi
fi

# A station reading another repository must not have unqualified gh calls fall
# back to this checkout's origin. GH_REPO makes gh default to the repo the
# station was given, which the adapters do not pass through.
if [[ -n "${repo_ctx:-}" ]]; then
  export GH_REPO="$repo_ctx"
fi

# Not exec: the read-only sandbox has to be cleaned up after the adapter
# returns. The trap is already installed above.
adapter_rc=0
"$adapter" --role "$role" --prompt "$prompt_bundle" --work-order "${work_order:-}" \
  --issue "${issue:-}" --repo "${repo_ctx:-}" --workdir "$workdir" "$@" || adapter_rc=$?
if [[ "$adapter_rc" -eq 0 && -n "$xr_sandbox" ]]; then
  # Deliberately not deleted by station-run.sh on any path: whoever reads this
  # line owns the clone and must remove it when done.
  echo "station-run: writable-clone-path $workdir"
fi
exit "$adapter_rc"
