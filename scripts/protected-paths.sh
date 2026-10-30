#!/usr/bin/env bash
# Print the AGENTS.md section 5 protected paths among the changed paths read
# from stdin (one per line, e.g. `git diff --name-only`). Prints nothing when
# none is protected. Exit 0 always; callers test for output.
#
# Existing-test edits need the diff, not just the path, so they are not
# decided here. Generated work orders under agents/work-orders/ are
# bookkeeping, not instruction, so they are not protected (#162).
set -euo pipefail

protected='^(\.github/(workflows|actions)/|\.github/factory\.yml$|\.github/CODEOWNERS$|\.coderabbit\.yaml$|CODEOWNERS$|AGENTS\.md$|agents/)|(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|go\.sum|[^/]*\.lock)$'
work_orders='^agents/work-orders/'

grep -E "$protected" | grep -vE "$work_orders" || true
