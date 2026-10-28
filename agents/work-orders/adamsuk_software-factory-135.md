---
repo: adamsuk/software-factory
issue: 135
issue_repo: adamsuk/software-factory
title: "ci: run the repo's own test scripts on every pull request"
branch: factory/135-tests-in-ci
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-28
---

## Goal

Make CI run the twelve `scripts/test-*.sh` suites, so the gate checks behaviour
instead of taking a station's word for it.

This work order is **step 1 of the four-step plan in the issue's triage comment**
and deliberately stops short of the issue's fourth acceptance criterion. Six of
the twelve suites fail on the factory box, and it is not yet known which of those
are real bugs and which are that box's toolchain (`bfs` instead of GNU `find`,
`jq` 1.6, `bash` 3.2). Adding a **red** job to `required_checks` would wedge
`main`: nothing could merge, including the fix for it.

So: add the job, let it report, and read what `ubuntu-latest` actually says.
Requiring the check and replacing `agents.test_command` comes after, once green.

**The pull request must not close #135.** Reference it; do not use a closing
keyword.

## Acceptance criteria

- [ ] A `tests` job in `.github/workflows/lint.yml` runs every
      `scripts/test-*.sh` on `pull_request` and on push to `main`
- [ ] The job discovers suites with a **glob**, never a hand-written list: the
      issue was filed naming seven scripts and there are already twelve
- [ ] Every suite runs even when an earlier one fails, and the job's exit status
      is non-zero if any failed — one red suite must not hide the other eleven
- [ ] Each suite's name and exit status appear in the log, and in the step
      summary if that is cheap
- [ ] The job installs what the suites need: `jq`, Python 3 with `venv`/`pip`,
      and PyYAML. `ubuntu-latest` already has GNU `find`, `jq` and `bash` 5
- [ ] The job's token permissions are `contents: read`, and no suite is given a
      GitHub token: they use a fake `gh` on `PATH` and must never reach the API
- [ ] `tests` is **not** added to `required_checks`, and `agents.test_command`
      is left alone, both with a comment in `.github/factory.yml` saying why and
      pointing at #135
- [ ] `CHANGELOG.md` gains a dated entry in the form the top of that file
      describes
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` exits 0

## Likely files

- `.github/workflows/lint.yml`
- `.github/factory.yml` (comment only)
- `CHANGELOG.md`

## Out of scope

- **Fixing the six failing suites.** Their real status is unknown until CI
  reports. That is step 3, scoped from CI output, and it splits into its own
  issue beneath #134 if it is large.
- Requiring the check on a ruleset: the Free-plan 403 is #112, Scott's decision.
- The `line` and `activity-feed` test gates (#114, #115, #117, #118).
- Changing any assertion in any `scripts/test-*.sh`. They are protected under
  AGENTS.md §5 and `scripts/check-test-assertions.sh` will fail the pull request.

## Notes

`.github/workflows/lint.yml` is CI config, a protected path under AGENTS.md §5.
Scott reviews the pull request.

Six suites measured red on the factory box on 2026-10-28, cause not yet
established:
`test-factory-label-metrics.sh` (exit 1, `FAIL (case1): exit 2, want 0`),
`test-factory-pr-metrics.sh` (exit 2, `printf: usage:`),
`test-gate-issue.sh` and `test-review-issue.sh` (exit 1, unstubbed `gh api`),
`test-station-post.sh` (exit 3, `jq: 1 compile error`),
`test-watcher-tree.sh` (exit 1, `find: -printf: unknown primary` — GNU-only flag,
so this one is a portability failure on the box, not necessarily in CI).

## Issue text (untrusted)

> Run software-factory's own test scripts in CI and require them
