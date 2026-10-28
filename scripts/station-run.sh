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
  --writable          Let the station change the real repo. Only meaningful for
                      builder, which is writable anyway; everything else is
                      read-only by default and this is the deliberate escape.
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
if [[ -z "$read_only" ]]; then
  if [[ "$role" == "builder" ]]; then
    read_only=false
  else
    read_only=true
  fi
fi

workdir="$here"
sandbox=""
cleanup_station() {
  local st=$?
  [[ -z "$sandbox" ]] || rm -rf "$sandbox"
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
  sandbox="$(mktemp -d /tmp/station-ro-XXXXXX)"
  # A clone, not a worktree. A linked worktree shares .git/config with the real
  # repository, so removing the worktree's origin removes the repository's own
  # remote. That happened while building #142 and broke push until origin was
  # added back. A clone has its own config, so dropping origin there is local.
  git clone --quiet --local --no-hardlinks --no-checkout "$here" "$sandbox/repo" \
    || die 7 "could not create the read-only clone"
  git -C "$sandbox/repo" checkout --quiet --detach "$head_sha" \
    || die 7 "could not check out $head_sha in the read-only clone"
  git -C "$sandbox/repo" remote remove origin > /dev/null 2>&1 \
    || die 7 "could not remove origin from the read-only clone"
  workdir="$sandbox/repo"
  echo "station-run: read-only clone of ${head_sha:0:7} at $workdir (no origin)" >&2
fi

# Not exec: the sandbox has to be cleaned up after the adapter returns. The
# trap is already installed above.
"$adapter" --role "$role" --prompt "$prompt_bundle" --work-order "${work_order:-}" \
  --issue "${issue:-}" --repo "${repo_ctx:-}" --workdir "$workdir" "$@"
