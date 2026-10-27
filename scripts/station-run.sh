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
  --help              Show this help
EOF
  exit 2
}

provider="${FACTORY_PROVIDER:-opencode}"
dry_run=false
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
      work_order="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2;;
    --issue)
      [[ $# -ge 2 ]] || die 2 "missing value for --issue"
      issue="$2"; shift 2;;
    --repo)
      [[ $# -ge 2 ]] || die 2 "missing value for --repo"
      repo_ctx="$2"; shift 2;;
    --dry-run)
      dry_run=true; shift;;
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

# Validate role exists in canonical roles
role_file="$here/agents/roles/${role}.md"
[[ -f "$role_file" ]] || die 2 "unknown role: $role (missing $role_file)"

agents_md="$here/AGENTS.md"
[[ -f "$agents_md" ]] || die 2 "missing $agents_md"

# Build context bundle
bundle_dir="$(mktemp -d /tmp/station-bundle-XXXXXX)"
trap 'rm -rf "$bundle_dir"' EXIT

# Validate supplied paths
if [[ -n "$work_order" && ! -e "$work_order" ]]; then
  die 2 "work order does not exist: $work_order"
fi
if [[ -n "$context_path" && "$context_path" != "/dev/null" && ! -e "$context_path" ]]; then
  die 2 "context path does not exist: $context_path"
fi

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
if [[ -n "$context_path" && "$context_path" == "/dev/null" ]]; then
  # Accept /dev/null as a context path
  :
elif [[ -n "$context_path" && -f "$context_path" ]]; then
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

"$adapter" --role "$role" --prompt "$prompt_bundle" --work-order "${work_order:-}" --issue "${issue:-}" --repo "${repo_ctx:-}" "$@"
exit $?
