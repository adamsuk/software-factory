---
repo: adamsuk/software-factory
issue: 51
issue_repo: adamsuk/software-factory
title: "feat: fail CI when a role brief drifts from the script or label it describes"
branch: factory/51-brief-drift-check
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-brief-drift-check.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-30
---

## Goal

Station 09 Return (#51) is mostly done: the monthly Line audit is scheduled
(#21, merged) and runs read-only. The one piece the 27 Oct Line audit
specifically called out as still missing: **a deterministic check that fails
when a role brief drifts from the code or labels it describes** — not
another audit, a CI check with a real pass/fail.

Two concrete, checkable claims exist today:

1. `agents/grok-build.md` ("What the wrapper does") describes
   `scripts/run-work-order.sh`'s flags and exit codes (`--push`, and exit
   codes 2, 3, 4, 5, 6, 7, 8, each with a stated meaning). If someone changes
   an exit code or a flag in the script without updating the brief, nothing
   catches it today.
2. Every `agents/roles/*.md` file names `factory:*` labels. The canonical set
   is defined in `stations/README.md` / AGENTS.md §9:
   `factory:triage`, `factory:ready`, `factory:building`, `factory:gate`,
   `factory:review`, `factory:merge`, `factory:release`, `factory:done`,
   `factory:blocked`. A brief that names a label outside that set (a typo, or
   a renamed label nobody updated everywhere) goes unnoticed today.

## What to build

- `scripts/brief-drift-check.sh`: a read-only, deterministic script that:
  - Extracts the exit codes `agents/grok-build.md` documents for
    `run-work-order.sh` (the `Stops (exit N)` / "exits with code N" style
    lines) and confirms each one corresponds to an actual `die N` (or
    equivalent) call in `scripts/run-work-order.sh`. Fails (prints what's
    wrong, non-zero exit) if the brief claims a code the script doesn't use,
    or uses a flag (`--push`) the script doesn't parse.
  - Extracts every `factory:[a-z]+` label mentioned across
    `agents/roles/*.md` (and `AGENTS.md` itself) and fails if any isn't in
    the canonical nine-label set above. Keep the canonical set as a single
    named list in the script (or a small data file next to it) so
    `stations/README.md` and this check share one source rather than two
    copies that can drift from each other.
  - Prints a clear, one-line summary per mismatch (which file, which claim,
    what's wrong), exits 0 when everything matches.
- Wire it into CI (the existing `tests` job, or a small step next to it) so
  a real mismatch fails the build, not just a monthly audit comment.
- `scripts/test-brief-drift-check.sh`: cover at least one deliberately
  broken fixture for each of the two checks (a brief claiming a nonexistent
  exit code; a brief naming a label outside the canonical set) and confirm
  the check fails on each, and passes on the real files as they stand today.
- `postmortems/TEMPLATE.md`: a short one-page template for a production
  incident (what happened, impact, timeline, root cause, what prevents a
  repeat). Follow the style of `audits/` for consistency if useful, but it's
  a different document — keep it short.
- Once the check passes clean on `main` at your head, bump `AGENTS.md`'s
  "Last reviewed: 2026-10-27" line to today's date (Europe/London) — the
  point of this check existing is that the reviewed date now means
  something checkable.

## Out of scope

- Doc drift for touchlineHQ/clubsPlatform (`docs/`, `openapi.yaml`) — that's
  #28, already merged, different repo and different kind of drift.
- The ruleset-vs-`factory.yml` drift check — that's #157, already merged,
  a different kind of drift entirely.
- Any change to the labels themselves, or to `run-work-order.sh`'s actual
  behaviour.
- A live `gh label list` call — keep this deterministic and offline so it
  runs the same in CI every time; the canonical label set is a fixed list,
  not something to query GitHub for.

## Acceptance criteria

- [ ] `scripts/brief-drift-check.sh` fails on a known mismatch (proven by a
      test fixture), passes clean against the real repo today
- [ ] It runs in CI and would fail the build on a real mismatch, not just
      report one
- [ ] `postmortems/TEMPLATE.md` exists
- [ ] `AGENTS.md`'s "Last reviewed" date is refreshed to today, since the
      check now backs that claim
- [ ] `CHANGELOG.md` gains a dated entry in this repo's changelog style

## Report back

In the PR body: which exit codes and flags the check verifies, and confirm
it fails against each of your two broken fixtures and passes against the
real `agents/grok-build.md` / `agents/roles/*.md` as they stand. This PR
touches `AGENTS.md` (protected, §5) — say so explicitly and expect Scott's
review regardless of verdict.
