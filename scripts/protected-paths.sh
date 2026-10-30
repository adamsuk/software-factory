#!/usr/bin/env bash
# Print the AGENTS.md section 5 protected paths among the changed paths read
# from stdin, NUL-delimited (e.g. `git diff -z --name-only`). NUL delimiters
# matter: with the default core.quotePath, git wraps a non-ASCII path (say
# `agents/roles/révision.md`) in double quotes and C-escapes it when printed
# one-per-line, which would hide it from the pattern below. `-z` disables
# that quoting entirely, so every path is read as plain bytes.
# Prints nothing when none is protected. Exit 0 always; callers test for output.
#
# Existing-test edits need the diff, not just the path, so they are not
# decided here. Generated work orders under agents/work-orders/ are
# bookkeeping, not instruction, so they are not protected (#162).
set -euo pipefail

protected='^(\.github/(workflows|actions)/|\.github/factory\.yml$|\.github/CODEOWNERS$|\.coderabbit\.yaml$|CODEOWNERS$|AGENTS\.md$|agents/)|(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|go\.sum|[^/]*\.lock)$'
work_orders='^agents/work-orders/'

while IFS= read -r -d '' path; do
  [[ "$path" =~ $protected ]] || continue
  [[ "$path" =~ $work_orders ]] && continue
  printf '%s\n' "$path"
done
