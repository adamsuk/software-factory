---
repo: adamsuk/software-factory
issue: 47
issue_repo: adamsuk/software-factory
title: "docs: describe station 05 Review and cap open agent PRs per repo in the foreman brief"
branch: factory/47-review-station-cap
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-foreman-pick-cap.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-30
---

## Goal

Station 05 Review (#47) is substantially built already this session:
gh-factory#15 (size labels) is merged, #26 (CodeRabbit acceptance
measurement) is merged and has a first baseline recorded (see #47's
comments), and reviewer verdicts already carry the four-field-ish record
this session's independent reviews have been posting. Two concrete pieces
are still missing:

1. `agents/roles/reviewer.md` doesn't say what station this is, what it
   takes in, or what it hands on — it's a list of steps with no framing.
2. There's no cap on how many open agent PRs a repo can carry before the
   foreman stops picking new work ("review capacity", scored missing in
   the Line audit). Right now the foreman will keep opening PRs on a repo
   indefinitely even if review hasn't caught up.

## What to change

- `agents/roles/reviewer.md`: add a short header section (a few sentences,
  not a rewrite of the existing steps) saying this is Line's station 05
  Review: it takes in PRs with `factory:review` and required checks green,
  and hands on `factory:merge` (PASS, no protected path, no open should-fix)
  or back to `factory:building` (FIX) or `factory:blocked` (ESCALATE, or
  PASS on a protected path). Mirror the "Takes in / Hands on" framing issue
  #47 itself uses, so a reader can place this brief in the pipeline without
  reading the issue.
- `agents/roles/foreman.md`, in the "Pick" step: add a cap of **2** open
  agent PRs per repo (counting open PRs whose branch matches
  `factory/<N>-*` or whose body closes/refs a factory issue — however the
  brief already identifies an "in flight" issue's PR elsewhere in this
  file, reuse that same definition rather than inventing a second one). At
  the cap, the foreman does not pick a **new** issue for that repo (issues
  already in flight still proceed through their existing steps, per the
  file's current wording on that point). Say which repo the cap counts
  against: the PR's own repo, not the issue's `Target repo:`.
- `scripts/test-foreman-pick-cap.sh` (new): since `foreman-orchestrate.sh
  pick` isn't easily run end-to-end in a test (it calls real `gh`/providers),
  follow the pattern already used in `scripts/test-run-work-order.sh` for
  brief-shaped assertions: read `agents/roles/foreman.md`'s actual text and
  assert the cap is stated as a number (2), and that it's placed under the
  "Pick" step, not buried in "Later" or a comment. If `foreman-orchestrate.sh`
  itself is where "pick" is actually implemented (check before assuming the
  brief alone is enough), prefer testing the real enforcement there instead
  of just the brief's wording — whichever actually decides what the foreman
  does.

## Out of scope

- Any change to `review_bot` acceptance measurement itself (#26 is done).
- Changing the cap number later, or making it configurable per repo — start
  with a fixed 2, as the issue's MVP proposal says.
- Required approval / bot identity (#44, #9) — explicitly "later" in #47.

## Acceptance criteria

- [ ] `agents/roles/reviewer.md` states the station's inputs and outputs in
      a short header
- [ ] The open-PR cap (2 per repo) is stated in the foreman brief under the
      "Pick" step, and — if the foreman's picking logic lives in a script
      rather than just the brief — actually enforced there, with a test
      proving a repo at the cap is skipped and a repo under it is not
- [ ] `CHANGELOG.md` gains a dated entry in this repo's changelog style
- [ ] One real issue reaches `factory:merge` from `factory:review` through a
      recorded PR Reviewer PASS verdict (no named human approver required —
      that's #44/#9, explicitly out of scope here)

## Report back

In the PR body: whether the cap needed a code change (and where) or is
brief-only for now, and why. This PR touches `agents/roles/reviewer.md` and
`agents/roles/foreman.md` (protected, §5) — say so explicitly and expect
Scott's review regardless of verdict.
