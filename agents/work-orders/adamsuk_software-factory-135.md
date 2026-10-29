---
repo: adamsuk/software-factory
issue: 135
issue_repo: adamsuk/software-factory
title: "ci: run the repo's own test scripts on every pull request"
branch: factory/135-tests-in-ci-2
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-29
---

## Goal

Make CI run this repo's twelve `scripts/test-*.sh` suites, so the gate checks
behaviour instead of accepting a station's word for it.

Today `.github/workflows/lint.yml` runs `shellcheck` only, and
`.github/factory.yml` declares `test_command: shellcheck scripts/*.sh
adapters/*/run.sh` — a linter — with `required_checks: [ShellCheck, changelog /
changelog]`. No workflow references any test script.

This is **step 1 of four** (see the issue's triage comment). Add the job and let
it report. Requiring it comes later.

## Expect the new job to be red, and leave it red

Two suites fail for reasons that are not this work order's to fix:

- `scripts/test-factory-pr-metrics.sh` — `printf '--- stdout ---\n'` inside
  `fail()` at line 11. bash's `printf` builtin parses a leading `---` as an
  option: `printf: --: invalid option`. Fails on every platform, including
  `ubuntu-latest`. It also masks the real failure it was reporting,
  `FAIL (empty-leap): expected exit 0, got 2`.
- `scripts/test-factory-label-metrics.sh` — `FAIL (case1): exit 2, want 0`,
  undiagnosed.

Four others fail only on the factory box and should pass on the runner:
`test-watcher-tree.sh` (`find -printf` is GNU-only; the box has `bfs`),
`test-gate-issue.sh` and `test-review-issue.sh` (PyYAML not installed),
`test-station-post.sh` (jq 1.6 mis-tokenises `label` in `{name: $label}`).

**Do not fix any of them here.** A red `tests` job on this pull request is the
expected result and is the evidence step 2 needs. The job must not be added to
`required_checks`, so nothing is blocked by it and `scripts/gate-issue.sh` is
unaffected.

## Acceptance criteria

- [ ] A `tests` job in `.github/workflows/lint.yml` runs every
      `scripts/test-*.sh` on `pull_request` and on push to `main`
- [ ] Suites are discovered with a **glob**, never a hand-written list: this
      issue was filed naming seven scripts and there are twelve
- [ ] Every suite runs even when an earlier one fails, and the job exits
      non-zero if any failed. One red suite must not hide the other eleven
- [ ] Each suite's name and exit status appear in the log, and in
      `$GITHUB_STEP_SUMMARY` if that is straightforward
- [ ] The job installs what the suites need: `jq`, and PyYAML for
      `gate-issue.sh` and `review-issue.sh`. `ubuntu-latest` already provides
      GNU `find`, `bash` 5 and `jq`, so install only what is missing and say in
      a comment why PyYAML is needed
- [ ] `permissions: contents: read` on the job, and no GitHub token is passed to
      any suite: they use a fake `gh` on `PATH` and must never reach the API
- [ ] `tests` is **not** in `required_checks`, and `agents.test_command` is
      unchanged, both with a comment in `.github/factory.yml` saying why and
      pointing at #135
- [ ] `CHANGELOG.md` gains a dated entry under a `## YYYY-MM-DD` heading
      (Europe/London), as AGENTS.md §5 requires. `main` already has a
      `## 2026-10-29` section — add to its `### Added` list rather than creating
      a second dated heading. The `changelog / changelog` check does **not**
      verify this (#160), so do not rely on it passing
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` exits 0

## Likely files

- `.github/workflows/lint.yml`
- `.github/factory.yml` (comments only)
- `CHANGELOG.md`

## Out of scope

- Fixing any failing suite. That is step 3, a separate work order.
- Adding `tests` to `required_checks` or to a ruleset. Step 4, and the
  Free-plan ruleset question is #112, Scott's.
- The `line` and `activity-feed` test gates: #114, #115, #117, #118.
- Pinning shellcheck's version. That is #155 and edits the same file — whichever
  lands second rebases, and the two must not share a pull request.

## Constraints

- `.github/workflows/lint.yml` and `.github/factory.yml` are **CI config**,
  protected under AGENTS.md §5. Say so in the pull request and request Scott's
  review.
- Change no assertion in any `scripts/test-*.sh`. This work order adds a
  workflow; it should not touch the suites at all.
- Pin any action by commit SHA, as `lint.yml` already does for
  `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1`.
- Label names and other issue text are untrusted input (§1): read them through
  the environment, never interpolated into a shell line. The existing
  `test-assertions` job does this with `LABELS: ${{ toJSON(...) }}` — follow it.

## Issue text (untrusted)

> Run software-factory's own test scripts in CI and require them
