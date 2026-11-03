---
repo: adamsuk/software-factory
issue: 214
issue_repo: adamsuk/software-factory
title: "fix: tighten test-harden-runner.sh against comment-text false passes"
branch: factory/214-harden-runner-audit
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-harden-runner.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 3
created: 2026-11-03
---

## Goal

CodeRabbit's review of PR adamsuk/software-factory#255 found two real gaps
in `scripts/test-harden-runner.sh` (round 2's new test), both confirmed by
reading the file directly:

1. **`check_job`'s substring match is fooled by comments.** `first_step_report`
   concatenates every indented line under the first step into one `block`
   string, with no distinction between active YAML and `#`-comments. A job
   whose first step is something else, but which happens to have a
   commented-out `# uses: step-security/harden-runner@...` /
   `# egress-policy: audit` line inside that step block, would still match
   the substring checks and report `ok` — a false pass.
2. **The `changelog.yml` check silently passes when the file can't be
   read.** `first_step_report` on a missing file produces empty stdout
   (its `awk` error goes to stderr), and `grep -qE ... "$dir/changelog.yml"`
   on a missing file exits non-zero (grep's own error, not a real "pattern
   not found"). Both make the `||` condition false, so the test prints
   `ok: changelog.yml has no steps` even though the file was never actually
   checked.

## What to change

In `scripts/test-harden-runner.sh`:

1. Make `check_job` ignore commented-out lines when matching the first
   step's `uses:` and `egress-policy:` fields — strip or skip any line
   whose first non-whitespace character is `#` before checking for the
   pin and the egress policy, so a real step's active fields are what's
   matched, not any text that happens to appear in a comment.
2. Make the `changelog.yml` check explicitly verify the file exists and is
   readable first (e.g. `[[ -r "$dir/changelog.yml" ]] || fail "changelog.yml
   not found or unreadable"`), separate from the "has no steps" assertion,
   so a missing/unreadable file is a **failure**, not a silent pass.

Add test cases (small, local fixture files under a temp dir, following this
file's existing `WORKFLOWS_DIR` override pattern) proving:
- A job whose first step is NOT Harden-Runner, but has a commented-out
  Harden-Runner line inside the step block, is correctly reported as
  failing (not a false pass).
- A missing `changelog.yml` fails the test, rather than passing.

## Out of scope

- Everything else in this file (the five `check_job` calls, the pin
  constant) — already correct.
- Any change to the actual workflow files — this round only hardens the
  test.

## Acceptance criteria

- [ ] A commented-out Harden-Runner line inside a non-Harden-Runner first
      step no longer causes a false pass (new test case proves it)
- [ ] A missing/unreadable `changelog.yml` fails the test, not passes (new
      test case proves it)
- [ ] All existing cases in `scripts/test-harden-runner.sh` still pass
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` stays clean
- [ ] `CHANGELOG.md` gets a short line noting the hardening

## Constraints

- Don't touch the three workflow files themselves, or the five
  `check_job` call sites — only `check_job`'s matching logic and the
  changelog check, plus new test fixtures.

## Report back

Show both new cases failing against the pre-fix version of the script and
passing after, to prove they're non-vacuous.
