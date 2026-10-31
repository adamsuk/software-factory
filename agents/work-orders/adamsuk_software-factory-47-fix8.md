---
repo: adamsuk/software-factory
issue: 47
issue_repo: adamsuk/software-factory
title: "fix: validate --should-fix against the downstream marker format and verdict"
branch: factory/47-review-station-cap
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-foreman-pick-cap.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 8
created: 2026-10-30
---

## Goal

CodeRabbit's full-review round on PR #188 found two real validation gaps
in round 7's `--should-fix` addition to `scripts/station-post.sh`. Both
are confirmed against the actual downstream reader,
`scripts/review-issue.sh`:

1. **Leading zeros break the downstream parser.** `review-issue.sh`
   parses the posted marker with
   `should_re = re.compile(r"^should-fix: (0|[1-9][0-9]*)\Z")` — it
   accepts `0` or a count with no leading zero. `station-post.sh`'s
   current validation (`^[0-9]+$`) accepts `01`, which doesn't match that
   pattern. A marker with `should-fix: 01` would make `review-issue.sh`'s
   `parse_marker` fail to match, and the issue would sit in `wait`
   indefinitely.
2. **A verdict/count contradiction can be posted.** `review-issue.sh`
   itself does: `FIX` with `should_fix == "0"` → `wait` forever;
   `PASS`/`ready` with `should_fix != "0"` → `wait` forever. `ESCALATE`
   has no such check there (any count is fine). `station-post.sh` lets
   `--should-fix` be combined with *any* verdict today, so a direct CLI
   call like `--verdict PASS --should-fix 2` would post a marker that
   `review-issue.sh` can never resolve.

## What to change

In `scripts/station-post.sh`'s `cmd_verdict`:

- Tighten the `--should-fix` format validation to match
  `review-issue.sh`'s accepted pattern exactly: `0` or `[1-9][0-9]*` (no
  leading zeros), not the looser `^[0-9]+$`.
- Reject verdict/count combinations that `review-issue.sh` can never
  resolve: `--verdict PASS` with an explicit non-zero `--should-fix`, and
  `--verdict FIX` with an explicit `--should-fix 0`. (`ESCALATE` has no
  such constraint downstream — any explicit value is fine there.) Reject
  with `die 2` and a clear message, the same way other bad-input cases in
  this function already do.

## New/updated tests needed

In `scripts/test-station-post.sh`:
- A case proving `--should-fix 01` is rejected (exit 2), not silently
  accepted and posted.
- A case proving `--verdict PASS --should-fix 2` is rejected.
- A case proving `--verdict FIX --should-fix 0` is rejected.
- Confirm the existing valid cases from round 7 (`ESCALATE` with
  `--should-fix 3`, FIX/non-FIX defaults) still pass.
- Non-vacuous: each new rejection case must actually fail (wrong exit
  code or no rejection) against the round-7 code, and pass against this
  fix.

Note: `scripts/test-station-post.sh` fails on this box on a pre-existing
`jq` 1.6 issue unrelated to this change (#164, already excluded from
`.github/factory.yml`'s local `test_command`). Verify your changes by
reading the test logic and tracing the validation regex/branches by hand
if the suite won't run cleanly here, and say so plainly in the report
rather than claiming a local pass that didn't happen. CI's `tests` job
will run it for real.

## Out of scope

- Anything else in `station-post.sh` or `review-issue.sh`.
- Everything already fixed in rounds 1-7.

## Acceptance criteria

- [ ] `--should-fix` rejects a leading-zero count (e.g. `01`)
- [ ] `--should-fix` rejects `PASS` with a non-zero count and `FIX` with
      a zero count; `ESCALATE` is unconstrained
- [ ] All existing `test-station-post.sh` and `test-foreman-pick-cap.sh`
      cases still pass (or are traced by hand if the suite won't run on
      this box, with that stated honestly)
- [ ] `shellcheck` stays clean

## Report back

State plainly whether `scripts/test-station-post.sh` actually ran on this
box or was verified by hand due to the jq gap. Show non-vacuity for the
three new rejection cases either way.
