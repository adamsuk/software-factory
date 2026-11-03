---
repo: adamsuk/software-factory
issue: 211
issue_repo: adamsuk/software-factory
title: "fix: make the candidate-size guard testable, close the search-API 1000-cap off-by-one"
branch: factory/211-research-audit-cycle
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-audit-triage.sh && bash scripts/test-sub-issues-all-closed.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 5
created: 2026-11-03
---

## Goal

CodeRabbit's review of PR adamsuk/software-factory#254's round-4 fix found
two more real gaps, both confirmed:

1. **The 60,000-byte candidate-size guard isn't unit-testable.** It lives
   inline inside `.github/workflows/line-audit.yml`'s "Export the
   candidates for triage" step, which only runs in the real workflow
   runner. A change to the limit, or accidental removal of the guard,
   wouldn't fail any test.
2. **Off-by-one in the 1000-issue cap, verified against a real repo.**
   `gh issue list --repo ... --label factory --state open --limit N`
   goes through GitHub's search API when a label filter is present, and
   that API hard-caps at exactly 1000 results **no matter how high
   `--limit` is set**. Round 4's check (`-le $open_cap`, i.e. `-le 1000`)
   passes when exactly 1000 results come back — but that's exactly the
   case where there might be *more* than 1000 real open issues and the
   search API silently truncated to its own ceiling. The check needs to
   reject a count of exactly 1000, not just a count above it.

## What to change

1. **Extract the candidate-size check into a new, testable script**,
   `scripts/check-candidate-size.sh`:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   file=$1
   size=$(wc -c < "$file")
   if [ "$size" -gt 60000 ]; then
     echo "::error::candidates.md is $size bytes, over the 60000-byte limit; triage would silently drop candidates"
     exit 1
   fi
   ```
   Replace the inline check in `.github/workflows/line-audit.yml`'s
   "Export the candidates for triage" step with a call to this script.
   Add `scripts/test-check-candidate-size.sh` (or similar) asserting a
   60,000-byte file passes and a 60,001-byte file fails.
2. **Fix the off-by-one** in `scripts/audit-triage.sh`: change the
   rejection condition from `-le $open_cap` to `-lt $open_cap`, so a count
   of exactly 1000 is rejected (not just counts above 1000). Update the
   existing test fixture for this case (currently simulates "1001 issues
   → reject"; it also needs to prove "exactly 1000 issues → reject", since
   that's the case the bug missed).

## Out of scope

- Everything already deferred: #266 (concurrency race), #267 (per-candidate
  dedup), #258 (cross-repo token), the declined secret-masking finding.
- Any other change to `audit-triage.sh` or `line-audit.yml` beyond these
  two targeted fixes.

## Acceptance criteria

- [ ] `scripts/check-candidate-size.sh` exists, is called from
      `line-audit.yml`, and has its own test proving the 60,000/60,001-byte
      boundary
- [ ] `audit-triage.sh`'s open-issue-count check rejects exactly 1000, not
      just counts above 1000 (existing fixture updated or a new case added
      to prove it)
- [ ] All existing `test-audit-triage.sh` and `test-sub-issues-all-closed.sh`
      cases still pass
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` stays clean
- [ ] `CHANGELOG.md` gets a line for this round

## Constraints

- `.github/workflows/line-audit.yml` is a protected path (AGENTS.md §5).
- Don't touch anything already deferred to #266, #267, or #258.

## Report back

Show both new/updated test cases failing against the pre-fix code and
passing after.
