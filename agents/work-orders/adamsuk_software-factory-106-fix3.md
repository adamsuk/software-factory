---
repo: adamsuk/software-factory
issue: 106
issue_repo: adamsuk/software-factory
title: "test: add focused assertions for the research.md issue-filing contract"
branch: factory/106-research-files-issues
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-research-brief.sh"
setup_command: ""
changelog: false
merge_allowed: false
review_bot: coderabbit
attempt: 3
created: 2026-10-30
---

## Goal

Two findings from CodeRabbit's full-review round on PR #192:

1. **Small mismatch:** the work order's acceptance criterion checks
   `shellcheck scripts/*.sh` but the front matter's `test_command` is
   `shellcheck scripts/*.sh adapters/*/run.sh`. Align them.
2. **Real gap:** `AGENTS.md` §3 requires a test that fails without the
   behavior change. `agents/roles/research.md` changes Research Scout's
   issue-filing contract (what each filed issue must contain, the 3-per-run
   cap, no-PRs-opened), and this PR shipped it with no test at all — "no
   new test file is required" was asserted but not actually true for a
   *contract* change like this one. Every other role-brief PR this session
   (`agents/roles/reviewer.md`, `agents/roles/foreman.md` in #47) added a
   `declare -f`/grep-based assertion proving specific brief wording. This
   one should too.

## What to change

- Fix the acceptance-criterion wording in
  `agents/work-orders/adamsuk_software-factory-106.md` (and `-fix2.md` if
  it repeats the mismatch) to match the real `test_command`.
- Add `scripts/test-research-brief.sh` (new), following the same pattern
  as `scripts/test-foreman-pick-cap.sh`: extract the relevant step(s) from
  `agents/roles/research.md` and assert, at minimum:
  - Each filed issue is required to carry a `Target repo: owner/repo` line
  - The `factory` and `factory:triage` labels are required
  - The cap of 3 issues per repo per run is stated
  - "no duplicate" / don't-duplicate-an-open-issue wording is present
  - Outputs say Research Scout opens no PRs and merges nothing
  - The removed "don't merge unless §6 allows it" line is genuinely gone
    (not just moved)
- Wire the new test into the `tests` CI job the same way other
  `scripts/test-*.sh` files already are (check how; likely just needs to
  exist, since the job probably globs `scripts/test-*.sh` — confirm rather
  than assume).

## Out of scope

- Anything else in `research.md`'s content — this is a test-coverage
  addition for what's already there, not a new behavior change.

## Acceptance criteria

- [ ] The work order's acceptance criterion matches the real
      `test_command` (`shellcheck scripts/*.sh adapters/*/run.sh`)
- [ ] `scripts/test-research-brief.sh` exists and asserts the contract
      points listed above, proven non-vacuous against at least two of them
      (fails if that requirement is removed from the brief, passes against
      the real file)
- [ ] The new test runs as part of the normal `scripts/test-*.sh` suite
- [ ] `shellcheck` stays clean

## Report back

No changelog entry needed. Confirm the new test file is picked up by
whatever already runs `scripts/test-*.sh` in CI (name the mechanism), and
show the non-vacuity checks.
