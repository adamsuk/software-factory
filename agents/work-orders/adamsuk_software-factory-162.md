---
repo: adamsuk/software-factory
issue: 162
issue_repo: adamsuk/software-factory
title: "docs: exclude agents/work-orders/** from the AGENTS.md section 5 protected paths"
branch: factory/162-work-orders-not-protected
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-station-post.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-30
---

## Decision (Scott, 29 Oct)

Option 1 from the issue, chosen by Scott: **exclude `agents/work-orders/**` from
§5.** It is generated bookkeeping, not instruction, and should stop being
protected. `AGENTS.md`, `agents/roles/**`, `agents/grok-build.md` and
`CODEOWNERS` stay protected. Not chosen: moving work orders out of `agents/`
(option 2), or leaving it (option 3).

## Goal

Every factory pull request writes a work order to
`agents/work-orders/<owner>_<repo>-<issue>.md` on its branch. Because
`AGENTS.md` §5 currently protects all of `agents/**`, every factory PR touches
a protected path by construction, which routes it to `factory:blocked` +
`needs-scott` for a reason that carries no risk — and buries the genuine cases
(a PR that actually edits `AGENTS.md`, `agents/roles/**` or
`agents/grok-build.md`) inside routine noise. Read the full problem statement
and history in issue #162 before starting.

## What to change

- `AGENTS.md` §5: state explicitly that `agents/work-orders/**` is **not**
  protected, while `AGENTS.md`, `agents/roles/**`, `agents/grok-build.md` and
  `CODEOWNERS` remain protected.
- Whatever currently decides the reviewer's `--protected yes|no` call (today
  this is the reviewer role reading §5 against the diff, not a deterministic
  script — check `agents/roles/reviewer.md` and `scripts/station-post.sh`)
  needs to reflect the new rule so a PR that touches only
  `agents/work-orders/**` is not reported `--protected yes` for that reason
  alone, while a PR touching `agents/roles/**`, `agents/grok-build.md`,
  `AGENTS.md` or `CODEOWNERS` still is. If there is no deterministic check
  today, decide whether to add one (a small script/function given a diff's
  changed paths) or to update the reviewer brief's instructions precisely
  enough to be testable — your call, but it must be verifiable by a test, not
  just worded better.
- Update `agents/roles/reviewer.md` and any other doc that states the §5 path
  list, so they agree with `AGENTS.md`.

## Out of scope (do not do these in this attempt)

- Moving work orders out of `agents/work-orders/` (option 2) — rejected.
- Changing anything about how work orders are generated or named.
- Any change to merge policy (`agents.merge`) or §6.

## Acceptance criteria

- [ ] `AGENTS.md` §5 states whether `agents/work-orders/**` is protected
      (it is not)
- [ ] A factory pull request that touches only a work order under
      `agents/work-orders/**` and no other protected path does not report
      `--protected yes` for that reason
- [ ] A pull request touching `agents/roles/**`, `agents/grok-build.md`,
      `AGENTS.md` or `CODEOWNERS` still reports `--protected yes`
- [ ] `scripts/test-station-post.sh` or an equivalent new test covers both
      cases above, and is proven non-vacuous (fails without the fix, passes
      with it)
- [ ] `CHANGELOG.md` gains a dated entry in the form the top of that file
      describes

## Report back

In the PR body: exactly how `--protected` gets decided now (deterministic
check vs. brief wording) and why, plus confirmation both test cases pass. This
PR itself touches `AGENTS.md` (protected), so say so explicitly and expect
Scott's review regardless of verdict.
