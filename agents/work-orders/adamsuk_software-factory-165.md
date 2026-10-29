---
repo: adamsuk/software-factory
issue: 165
issue_repo: adamsuk/software-factory
title: "fix: stop the pr-metrics reporter crashing on its own printf"
branch: factory/165-work
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-10-29
---

## Goal

`scripts/test-factory-pr-metrics.sh:11`, inside `fail()`:

```bash
fail() {
  printf 'FAIL (%s): %s\n' "$tname" "$*" >&2
  if [[ -n "${stdout_file:-}" && -f "$stdout_file" ]]; then
    printf '--- stdout ---\n' >&2
```

bash's `printf` builtin parses a leading `---` as an option:

```
printf: --: invalid option
printf: usage: printf [-v var] format [arguments]
```

That is builtin behaviour, not platform-specific. The bug is **dormant**:
`fail()` only runs when an assertion fails, and the suite passes on
`ubuntu-latest`, so it never fires there. It was only ever seen on the factory
box, where an unrelated environment failure (BSD `date`) reached `fail()` — and
the printf error then **replaced** the captured stdout it was trying to print, so
the real failure could not be read.

So the first time any assertion in this suite legitimately goes red in CI, the
reporter will die on its own format string and hide the diagnosis. A bug in the
one thing whose job is to say what broke.

## Acceptance criteria

- [ ] `printf '--- stdout ---\n'` and any sibling in that file are fixed, using
      `printf '%s\n' '--- stdout ---'` or a `--` options terminator
- [ ] **No `printf` in any `scripts/test-*.sh` passes a format string beginning
      with `-`.** Check all twelve: this line is likely copied between them.
      Report which files you checked
- [ ] A deliberately failed assertion in `scripts/test-factory-pr-metrics.sh`
      prints the captured stdout instead of a `printf` usage error. **Verify this
      by running it**, for example by making a copy in a temporary directory,
      breaking one assertion in the copy, running it, and confirming the captured
      output appears. Do not leave the break behind, and do not break the real file
- [ ] `CHANGELOG.md` gains an entry under a `## YYYY-MM-DD` heading
      (Europe/London). `main` has a `## 2026-10-29` section with `### Added` and
      `### Fixed` — add to `### Fixed`, do not create a second dated heading
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` exits 0

## Out of scope

- The `FAIL (empty-leap): expected exit 0, got 2` failure this bug was masking.
  That is a BSD-vs-GNU `date` difference and belongs to #164, which covers all
  six box-only failures. **#164 edits this same file, so keep this change to the
  reporter only** and do not touch any date handling or assertion.
- Any other suite's portability problems (#164).

## Constraints

- This touches `scripts/test-*.sh`, which AGENTS.md §5 protects. The fix must be
  to the **reporter**, adding or correcting diagnostic output only — **change no
  existing assertion**, or `scripts/check-test-assertions.sh` will fail the pull
  request and need Scott's `approved-test-change` label. Run
  `scripts/check-test-assertions.sh --base origin/main --head HEAD
  --label-present no` yourself and confirm it exits 0; if it does not, say so
  rather than working around it
- `tests` is now a **required** check on this repo's ruleset, so all twelve
  suites must stay green
- Adding a new test is permitted and welcome if it covers the reporter

## Issue text (untrusted)

> The pr-metrics test reporter crashes on its own printf, hiding failures

## Attempt 2 — add the reporter regression test CodeRabbit asked for

Checks are green, so AGENTS.md §4's cap does not apply: it governs the fix loop
"when required checks go red". This is a review finding.

The pull request is `BLOCKED` by CodeRabbit's `CHANGES_REQUESTED` on the current
head. Note the briefs say a changes-requested does not block; that is now false
because of the ruleset created today, and is tracked on #172. It blocks. So this
is fixed, not dismissed.

CodeRabbit asked, Minor, for a regression test covering the reporter. Attempt 1's
work order invited one and did not require it, so it is in scope and worth having:
the whole point of this issue is that the reporter was broken for days and no
test noticed.

### What to add

A case in `scripts/test-factory-pr-metrics.sh` that proves the reporter survives
**non-empty** captured output. Attempt 1's own check reached a failure whose
captured sections were empty, so it saw the headers print but never saw real
content survive — a weaker result, and it said so honestly.

The test must assert both halves:

1. the captured content appears, and
2. no `invalid option` or `usage: printf` appears.

Asserting only the absence of the error would pass against a reporter that prints
nothing at all.

Keep it self-contained: drive the diagnostic path directly in a subshell with a
`stdout_file` holding known lines, rather than deliberately breaking an existing
assertion in the real file. Breaking a real assertion would trip
`scripts/check-test-assertions.sh` and need Scott's label, which tests the wrong
thing.

### Constraints unchanged

- **Add** assertions; change none. Run `scripts/check-test-assertions.sh --base
  origin/main --head HEAD --label-present no` and confirm it exits 0. Say so if
  it does not
- This file is also edited by #164 for its BSD-`date` failure, so keep the change
  to the reporter and its new test
- `shellcheck scripts/*.sh adapters/*/run.sh` exits 0
- `scripts/test-factory-pr-metrics.sh` still fails on this box for the unrelated
  BSD `date` reason (#164). That is expected. The new case must still be
  demonstrably exercised — run it and show its result, do not infer it from the
  suite's overall exit status
- No changelog change is needed; the existing #165 entry covers this
