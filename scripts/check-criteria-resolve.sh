#!/usr/bin/env bash
# Check that what an issue's done-checks name actually exists (#345).
#
# Usage: scripts/check-criteria-resolve.sh <criteria-file> [ROOT]
#        scripts/check-criteria-resolve.sh <criteria-file> --repo <owner/repo>
#
# <criteria-file> holds one criterion per line, with or without a markdown
# checkbox. Its text is data: it is parsed, never executed.
# Two kinds of name are resolved:
#   - a path under scripts/ or .github/workflows/ must be an existing regular
#     file under ROOT (default: this repo), e.g. scripts/ready-gate.sh;
#   - a workflow job, written as `name` job or job `name`, must be a job id
#     or job name in some .github/workflows/*.yml under ROOT.
# A name followed by (new), e.g. `scripts/foo.sh` (new), is a file or job the
# issue itself proposes to add, and is allowed. A criterion naming nothing
# passes: this check is about named things, not about shape (see
# scripts/triage-ask.sh for that).
# --repo resolves against the repo's default branch through gh (read-only)
# instead of a checkout.
#
# Exit 0: every named path or job resolves or is marked (new). Prints nothing.
# Exit 1: prints each missing name on its own line (once each).
# Exit 2: bad usage or unreadable criteria file. Exit 3: gh could not read the repo.
# shellcheck disable=SC2016  # literal backticks in the patterns, not expansion
set -euo pipefail

die() { echo "check-criteria-resolve: $2" >&2; exit "$1"; }

crit=""
root=""
repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      sed -n "2,24p" "$0"
      exit 0
      ;;
    --repo)
      [[ $# -ge 2 ]] || die 2 "--repo needs owner/repo"
      repo=$2
      shift 2
      ;;
    -*)
      die 2 "unknown argument: $1"
      ;;
    *)
      if [[ -z "$crit" ]]; then
        crit=$1
      elif [[ -z "$root" ]]; then
        root=$1
      else
        die 2 "unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

[[ -n "$crit" ]] || die 2 "usage: scripts/check-criteria-resolve.sh <criteria-file> [ROOT | --repo owner/repo]"
[[ -f "$crit" ]] || die 2 "criteria file not found: $crit"
[[ -z "$repo" || -z "$root" ]] || die 2 "give ROOT or --repo, not both"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [[ -n "$repo" ]]; then
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 2 "bad repo"
  # Build a stand-in tree: an empty file per blob, and the real text of each
  # workflow file so its jobs can be read.
  root=$tmp/tree
  mkdir -p "$root"
  gh api "repos/$repo/git/trees/HEAD?recursive=1" --jq '.tree[] | select(.type == "blob") | .path' \
    > "$tmp/paths" 2> /dev/null || exit 3
  while IFS= read -r p || [[ -n "$p" ]]; do
    case "$p" in
      scripts/* | .github/workflows/*) ;;
      *) continue ;;
    esac
    [[ "$p" != *..* ]] || continue
    mkdir -p "$root/$(dirname "$p")"
    case "$p" in
      .github/workflows/*.yml | .github/workflows/*.yaml)
        gh api "repos/$repo/contents/$p" -H 'Accept: application/vnd.github.raw' \
          > "$root/$p" 2> /dev/null || exit 3
        ;;
      *) : > "$root/$p" ;;
    esac
  done < "$tmp/paths"
else
  if [[ -z "$root" ]]; then
    root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  fi
  root=$(cd "$root" && pwd) || die 2 "not a directory: $root"
fi

# Job ids and job names from every workflow file under root.
jobs=()
shopt -s nullglob
for wf in "$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml; do
  [[ -f "$wf" ]] || continue
  in_jobs=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    if [[ "$line" =~ ^jobs:[[:space:]]*(#.*)?$ ]]; then
      in_jobs=1
      continue
    fi
    [[ $in_jobs -eq 1 ]] || continue
    if [[ "$line" =~ ^[^[:space:]#] ]]; then
      in_jobs=0
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]{2}([A-Za-z_][A-Za-z0-9_-]*):[[:space:]]*(#.*)?$ ]]; then
      jobs+=("${BASH_REMATCH[1]}")
    elif [[ "$line" =~ ^[[:space:]]{4}name:[[:space:]]*[\"\']?([A-Za-z0-9_.\ /-]*[A-Za-z0-9_.-])[\"\']?[[:space:]]*(#.*)?$ ]]; then
      jobs+=("${BASH_REMATCH[1]}")
    fi
  done < "$wf"
done
shopt -u nullglob

# 0 when rel is a regular file under root. Empty, "." and ".." segments are
# rejected, and so is any symlink among the components (a link inside root
# that points inside root does not resolve either), so a link cannot fake a
# hit. The resolved real path must also stay inside the real root.
regular_file_under_root() {
  local rel=$1 part cur=$root real realroot
  local -a parts=()
  [[ "$rel" != */ && "$rel" != *//* ]] || return 1
  local IFS=/
  read -r -a parts <<< "$rel" || return 1
  for part in "${parts[@]}"; do
    [[ -n "$part" && "$part" != "." && "$part" != ".." ]] || return 1
    cur=$cur/$part
    [[ ! -L "$cur" ]] || return 1
  done
  [[ -f "$cur" ]] || return 1
  real=$(readlink -f -- "$cur") || return 1
  realroot=$(readlink -f -- "$root") || return 1
  [[ "$real" == "$realroot"/* ]]
}

job_exists() {
  local want=$1 j
  [[ ${#jobs[@]} -gt 0 ]] || return 1
  for j in "${jobs[@]}"; do
    [[ "$j" == "$want" ]] && return 0
  done
  return 1
}

# A path: scripts/... or .github/workflows/..., not glued to an identifier.
path_re='(^|[^A-Za-z0-9_./-])((scripts|\.github/workflows)/[A-Za-z0-9_./]([A-Za-z0-9._/-]*[A-Za-z0-9_])?)'
# A job: `name` job  or  job `name`.
job_a_re='`([A-Za-z_][A-Za-z0-9_. /-]*)`[[:space:]]+job([^A-Za-z0-9_]|$)'
job_b_re='(^|[^A-Za-z0-9_])job[[:space:]]+`([A-Za-z_][A-Za-z0-9_. /-]*)`'
# Allowed after a name: an optional closing backtick or quote, then (new).
new_re='^[`"'"'"'*_]*[[:space:]]*\(new\)'

missing=()
add_missing() {
  local m x
  m=$1
  if [[ ${#missing[@]} -gt 0 ]]; then
    for x in "${missing[@]}"; do
      [[ "$x" == "$m" ]] && return 0
    done
  fi
  missing+=("$m")
}

while IFS= read -r line || [[ -n "$line" ]]; do
  line=${line%$'\r'}
  text=$line
  while [[ "$text" =~ $path_re ]]; do
    path=${BASH_REMATCH[2]}
    match=${BASH_REMATCH[0]}
    prefix=${text%%"$match"*}
    text=${text#"$prefix$match"}
    # A sentence full stop is not part of the path.
    path=${path%.}
    if [[ "$text" =~ $new_re ]]; then
      continue
    fi
    regular_file_under_root "$path" || add_missing "$path"
  done
  text=$line
  while [[ "$text" =~ $job_a_re ]]; do
    name=${BASH_REMATCH[1]}
    match=${BASH_REMATCH[0]}
    prefix=${text%%"$match"*}
    text=${text#"$prefix$match"}
    # (new) may sit just after the backtick span, before the word "job".
    if [[ "${line#*"\`$name\`"}" =~ ^[[:space:]]*\(new\) ]] || [[ "$text" =~ ^[^A-Za-z0-9]*\(new\) ]]; then
      continue
    fi
    job_exists "$name" || add_missing "job $name"
  done
  text=$line
  while [[ "$text" =~ $job_b_re ]]; do
    name=${BASH_REMATCH[2]}
    match=${BASH_REMATCH[0]}
    prefix=${text%%"$match"*}
    text=${text#"$prefix$match"}
    if [[ "$text" =~ $new_re ]]; then
      continue
    fi
    job_exists "$name" || add_missing "job $name"
  done
done < "$crit"

if [[ ${#missing[@]} -gt 0 ]]; then
  printf '%s\n' "${missing[@]}"
  exit 1
fi
exit 0
