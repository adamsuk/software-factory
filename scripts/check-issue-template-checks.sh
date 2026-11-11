#!/usr/bin/env bash
# Fail when a markdown checkbox under .github/ISSUE_TEMPLATE/ names neither a
# path under scripts/ nor a workflow job from .github/workflows/.
#
# A script path looks like scripts/check-issue-template-checks.sh. It must be
# an existing regular file under ROOT, the tree being checked. It is not
# executed (a placeholder that names this gate would recurse). A workflow job
# is a job id plus that file's repo-relative path, for example the tests job
# in .github/workflows/lint.yml. A job id that occurs only inside that path
# does not count.
#
# Usage: scripts/check-issue-template-checks.sh [ROOT]
# ROOT defaults to this repo. Exit 0 when every checkbox names an existing
# scripts/ file or a workflow job. Exit 1 when one does not, including a
# scripts/ path that is not a regular file under ROOT. Exit 2 on bad usage
# or a missing ISSUE_TEMPLATE directory.
# Reads the tree only; no network calls and no writes.
set -euo pipefail

die() { echo "check-issue-template-checks: $2" >&2; exit "$1"; }

root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      sed -n '2,17p' "$0"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die 2 "unknown argument: $1"
      ;;
    *)
      [[ -z "$root" ]] || die 2 "unexpected argument: $1"
      root=$1
      shift
      ;;
  esac
done

if [[ -z "$root" ]]; then
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fi
root=$(cd "$root" && pwd) || die 2 "not a directory: $root"

template=$root/.github/ISSUE_TEMPLATE
[[ -d "$template" ]] || die 2 "no ISSUE_TEMPLATE directory at $template"

# A task-list item. An empty body names nothing, so it fails the checks below.
checkbox_re='^[[:space:]]*[-*+][[:space:]]+\[[[:space:]]*[xX]?[[:space:]]*\][[:space:]]*(.*)$'
# The character before "scripts/" is the start or a non-identifier, so
# myscripts/foo.sh does not count as a path under scripts/.
script_path_re='(^|[^A-Za-z0-9_])scripts/[A-Za-z0-9_][A-Za-z0-9._/-]*'

# Repo-relative workflow path, tab, job id. Empty when the tree has no workflows.
wf_pairs=()

load_workflow_jobs() {
  local wf rel line in_jobs id nullglob_was
  local -a files=()
  nullglob_was=0
  if shopt -q nullglob; then
    nullglob_was=1
  fi
  shopt -s nullglob
  files=("$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml)
  if [[ $nullglob_was -eq 0 ]]; then
    shopt -u nullglob
  fi
  for wf in "${files[@]}"; do
    [[ -f "$wf" ]] || continue
    rel=${wf#"$root"/}
    in_jobs=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      line=${line%$'\r'}
      if [[ "$line" =~ ^jobs:[[:space:]]*(#.*)?$ ]]; then
        in_jobs=1
        continue
      fi
      [[ $in_jobs -eq 1 ]] || continue
      # The next top-level key ends the jobs map. Comments and blank lines do not.
      if [[ "$line" =~ ^[^[:space:]#] ]]; then
        in_jobs=0
        continue
      fi
      if [[ "$line" =~ ^[[:space:]]{2}([A-Za-z_][A-Za-z0-9_-]*):[[:space:]]*(#.*)?$ ]]; then
        id=${BASH_REMATCH[1]}
        wf_pairs+=("${rel}"$'\t'"${id}")
      fi
    done < "$wf"
  done
}

# Paths named in one checkbox body. The leading boundary character from
# script_path_re is not part of the path. script_paths is global.
script_paths=()
collect_script_paths() {
  local text=$1 match path prefix before
  script_paths=()
  while [[ "$text" =~ $script_path_re ]]; do
    match=${BASH_REMATCH[0]}
    if [[ "$match" == scripts/* ]]; then
      path=$match
    else
      path=${match:1}
    fi
    script_paths+=("$path")
    prefix=${text%%"$match"*}
    before=$text
    text=${text#"$prefix$match"}
    # A match that does not consume text would loop forever.
    [[ "$text" != "$before" ]] || break
  done
}

# 0 when rel is an existing regular file under root. The named script is
# not executed. "." and ".." components are rejected so the path cannot
# leave root.
regular_file_under_root() {
  local rel=$1 part candidate
  local -a parts=()
  [[ "$rel" == scripts/* ]] || return 1
  local IFS=/
  read -r -a parts <<< "$rel" || return 1
  for part in "${parts[@]}"; do
    [[ -n "$part" && "$part" != "." && "$part" != ".." ]] || return 1
  done
  candidate=$root/$rel
  [[ -f "$candidate" ]]
}

names_workflow_job() {
  local text=$1 pair rel job job_re outside
  [[ ${#wf_pairs[@]} -gt 0 ]] || return 1
  for pair in "${wf_pairs[@]}"; do
    rel=${pair%%$'\t'*}
    job=${pair#*$'\t'}
    [[ -n "$job" && "$text" == *"$rel"* ]] || continue
    # Ignore a job id that occurs only inside its workflow path. Blank each
    # copy of the path so "changelog" in changelog.yml is not a mention, while
    # a separate "changelog" beside that path still is. A space keeps the
    # surrounding text from joining into a new id.
    outside=${text//"$rel"/" "}
    job_re="(^|[^A-Za-z0-9_-])${job}([^A-Za-z0-9_-]|\$)"
    [[ "$outside" =~ $job_re ]] || continue
    return 0
  done
  return 1
}

load_workflow_jobs

files=()
while IFS= read -r -d '' f; do
  files+=("$f")
done < <(find "$template" -type f -print0 | sort -z)

count=0
bad=0
for f in "${files[@]}"; do
  rel=${f#"$root"/}
  lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    line=${line%$'\r'}
    [[ "$line" =~ $checkbox_re ]] || continue
    body=${BASH_REMATCH[1]}
    count=$((count + 1))
    collect_script_paths "$body"
    if [[ ${#script_paths[@]} -gt 0 ]]; then
      missing=
      for path in "${script_paths[@]}"; do
        if ! regular_file_under_root "$path"; then
          missing=$path
          break
        fi
      done
      if [[ -n "$missing" ]]; then
        bad=1
        echo "check-issue-template-checks: ${rel}:${lineno}: checkbox names ${missing}, which is not an existing regular file" >&2
        echo "    ${line}" >&2
      fi
      continue
    fi
    if ! names_workflow_job "$body"; then
      bad=1
      echo "check-issue-template-checks: ${rel}:${lineno}: checkbox names neither a scripts/ path nor a workflow job" >&2
      echo "    ${line}" >&2
    fi
  done < "$f"
done

if [[ $bad -ne 0 ]]; then
  exit 1
fi

shown=${template#"$root"/}
if [[ $count -eq 0 ]]; then
  echo "check-issue-template-checks: no checkboxes in ${shown}."
elif [[ $count -eq 1 ]]; then
  echo "check-issue-template-checks: 1 checkbox in ${shown} names a scripts/ path or a workflow job."
else
  echo "check-issue-template-checks: ${count} checkboxes in ${shown} name a scripts/ path or a workflow job."
fi
exit 0
