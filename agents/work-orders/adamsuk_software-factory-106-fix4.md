---
repo: adamsuk/software-factory
issue: 106
issue_repo: adamsuk/software-factory
title: "fix: run test-research-brief.sh from factory.yml; generalize the work-order file-list wording"
branch: factory/106-research-files-issues
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-research-brief.sh"
setup_command: ""
changelog: false
merge_allowed: false
review_bot: coderabbit
attempt: 4
created: 2026-10-30
---

## Goal

Two findings from CodeRabbit's latest full-review round on PR #192. One
earlier finding this round is already fixed and confirmed addressed.

1. **Real gap:** `.github/factory.yml`'s `test_command` (the repo's local
   box check) doesn't run `scripts/test-research-brief.sh` at all — only
   ShellCheck covers it there. The CI `tests` job picks it up separately
   via its own glob, but the local `test_command` is a curated explicit
   list (it deliberately excludes six suites that fail on the box for
   environment reasons — see the comment above it in `factory.yml`), and
   this new test was simply never added to that list.
2. **Recurring cosmetic issue, fix it so it stops recurring:** round 3's
   fix to `agents/work-orders/adamsuk_software-factory-106.md` named a
   specific work-order filename to exclude from its own "only these files
   changed" acceptance criterion. Round 4 (this one, or round 3's
   companion `-fix2.md` / `-fix3.md`) adds yet another work-order file,
   which immediately makes that named exclusion stale again — CodeRabbit
   caught this exact regress. Instead of naming filenames (which will
   keep multiplying every round), generalize the wording so it never goes
   stale again: exclude *any* file under `agents/work-orders/`, not named
   files.

## What to change

1. **`.github/factory.yml`**: add `&& bash scripts/test-research-brief.sh`
   to the end of `test_command`, matching the existing style (the test
   doesn't hit any of the six known box/CI environment gaps — confirm
   that's actually true by running it locally before adding it; if it
   does hit one of those gaps, say so instead and leave it out with a
   one-line reason next to the existing excluded-suites comment).
2. **`agents/work-orders/adamsuk_software-factory-106.md`**: reword the
   file-list acceptance criterion from naming specific work-order
   filenames to a general exclusion: something like "Apart from any file
   under `agents/work-orders/`, the only implementation files changed are
   `agents/roles/research.md` and `CHANGELOG.md`." Apply the same
   generalization to any other #106 work-order file that repeats this
   specific-filename pattern (check `-fix2.md` and `-fix3.md`).

## Out of scope

- Anything else already fixed in earlier rounds.
- Don't rename or consolidate the existing work-order files.

## Acceptance criteria

- [ ] `test-research-brief.sh` runs as part of `.github/factory.yml`'s
      `test_command` (confirmed it doesn't hit a known box/CI gap, or
      documented why it's excluded if it does)
- [ ] The file-list acceptance criterion in the #106 work orders no longer
      names specific filenames that go stale each round — generalized to
      exclude the whole `agents/work-orders/` directory
- [ ] `shellcheck` stays clean

## Report back

No changelog entry needed. Confirm whether `test-research-brief.sh` runs
clean on this box (not just in CI).
