---
repo: adamsuk/software-factory
issue: 214
issue_repo: adamsuk/software-factory
title: "test: add a test for the Harden-Runner audit step on software-factory's workflows"
branch: factory/214-harden-runner-audit
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-harden-runner.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-11-03
---

## Goal

PR adamsuk/software-factory#255's independent review (FIX verdict) found
two gaps:

1. No test proves the Harden-Runner step landed. AGENTS.md §3 requires
   tests for every behaviour change.
2. The PR body doesn't name the test command run, and doesn't flag the
   three edited workflow files as protected paths for Scott.

## What to change

1. Add `scripts/test-harden-runner.sh`: a read-only, offline test (follow
   the style of `scripts/test-brief-drift-check.sh` or similar — text
   extraction from the real workflow files, no `gh`, no network) asserting
   that `lint.yml`'s three jobs (`shellcheck`, `test-assertions`, `tests`),
   `line-audit.yml`'s job, and `ruleset-drift.yml`'s job each have the
   `step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43`
   step (with `egress-policy: audit`) as their first step. It must **fail
   on `main`** (before this PR) and **pass on this branch**. Also assert
   `changelog.yml`'s job still has no such step (it's a bare
   reusable-workflow caller with no steps — confirm it stays that way).
2. Add `bash scripts/test-harden-runner.sh` to this PR's own
   `test_command` usage going forward (already reflected above) — no
   change needed to `.github/factory.yml`'s `test_command` itself unless
   you judge it belongs there permanently; if you do add it there, say so
   explicitly in the report (that file is protected, same as the rest of
   this PR).
3. Update the PR body (via `scripts/station-post.sh verdict`'s normal
   fix-round flow — the next review will read the live PR body) to state
   the exact test command run, and name `.github/workflows/lint.yml`,
   `.github/workflows/line-audit.yml` and `.github/workflows/ruleset-drift.yml`
   as protected paths needing Scott's review.

## Out of scope

- Everything already correct in round 1 (the actual Harden-Runner step
  additions) — don't touch those lines, only add the test and complete the
  PR body/report.

## Acceptance criteria

- [ ] `scripts/test-harden-runner.sh` exists, is read-only/offline, fails
      against `main` and passes against this branch
- [ ] It also confirms `changelog.yml` is unchanged (still no steps)
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` stays clean
- [ ] `CHANGELOG.md` gains a line for the new test
- [ ] The PR body names the test command and the three protected workflow
      files

## Constraints

- `.github/workflows/**` is protected (AGENTS.md §5) — unchanged from
  round 1, already true of this PR.

## Report back

State the exact test command, and confirm the new test genuinely fails
against unmodified `main` (show the failure) before passing here.
