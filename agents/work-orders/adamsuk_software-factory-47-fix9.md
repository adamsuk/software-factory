---
repo: adamsuk/software-factory
issue: 47
issue_repo: adamsuk/software-factory
title: "fix: count the open-PR cap by unique (Target repo, issue), not by matching artifact"
branch: factory/47-review-station-cap
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-foreman-pick-cap.sh"
setup_command: ""
changelog: false
merge_allowed: false
review_bot: coderabbit
attempt: 9
created: 2026-10-30
---

## Goal

CodeRabbit's full-review round on PR #188 found one real wording gap. The
other findings this round are already-fixed historical-doc metadata
(`changelog: false` → `true` on four earlier fix-round work orders, already
corrected directly) or a low-value edge case being declined (see below) —
don't touch either of those here.

**The gap:** the cap's in-flight definition counts "an open PR, a
`factory/<issue>-*` branch, or an issue labelled `factory:building`" for
the candidate's target repo — but during the branch-only phase, a single
issue can have *both* the `factory:building` label *and* a matching
branch at once. As written, that one issue could be counted twice,
consuming two cap slots instead of one.

## What to change

In `agents/roles/foreman.md`'s Pick step, state that the cap counts
**unique `(Target repo, issue)` pairs** — not one count per matching
artifact. An issue with both `factory:building` and a matching branch
still counts once.

## New/updated tests needed

In `scripts/test-foreman-pick-cap.sh`: assert the Pick step states the
cap counts unique issues, not per-artifact (non-vacuous: fails if that
wording is removed).

## Out of scope

- The `--should-fix ""` edge case from this round (explicit empty string
  vs. omitted flag treated the same) — **declining this one.** Nothing
  in this codebase ever calls `station-post.sh verdict` with an
  explicitly empty `--should-fix` value; the reviewer brief only ever
  says to pass a real integer or omit the flag. Tracking "was this flag
  seen at all" separately from "what value does it hold" for a case no
  caller produces is disproportionate to the risk. State this reasoning
  in the PR body rather than silently dropping it.
- Everything else already fixed in rounds 1-8.

## Acceptance criteria

- [ ] The cap is stated to count unique `(Target repo, issue)` pairs, not
      once per matching artifact
- [ ] All existing cases in `scripts/test-foreman-pick-cap.sh` still pass
- [ ] `shellcheck` stays clean

## Report back

No changelog entry needed. State explicitly, for the PR body, why the
`--should-fix ""` finding is being declined (reasoning above). Show the
non-vacuity check for the new assertion.
