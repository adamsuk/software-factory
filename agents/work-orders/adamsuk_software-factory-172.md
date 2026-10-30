---
repo: adamsuk/software-factory
issue: 172
issue_repo: adamsuk/software-factory
title: "docs: AGENTS.md and the reviewer brief must say changes-requested blocks where a ruleset enforces it"
branch: factory/172-changes-requested-blocks
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

Fix the wording and require the observed merge status:

1. Correct `AGENTS.md` §10.4 and `agents/roles/reviewer.md`: a bot's
   `CHANGES_REQUESTED` on the current head blocks a merge where a ruleset
   enforces the `pull_request` rule. Remedy is fix the finding or have Scott
   dismiss it.
2. Name the condition (which repos have a `factory-main` ruleset enforcing
   this), or point at a single place that lists them.
3. Keep §10.4's substance: a bot review is not sufficient and an independent
   review is still required.
4. The reviewer verdict must state the PR's observed `mergeStateStatus` for
   the head under review.

Keep the blocking wording **conditional**. Whether the owner's bypass lets
Scott merge over a standing review is unproven (see #152, decided to test
first) — do not claim either way in this PR. Fold the observed status into
the #119 four-field review record rather than adding a parallel mechanism (if
#119's record format already exists in this repo; otherwise just have the
verdict comment state it).

## Goal

The `factory-main` ruleset created on 2026-10-29 (#112) made a review bot's
`CHANGES_REQUESTED` on the current head **block a merge** on enrolled repos.
`AGENTS.md:168` and `agents/roles/reviewer.md:26` still say changes-requested
"alone doesn't block" — stale since the ruleset landed. Two station runs
(PR #169, PR #170) already repeated the stale rule and returned PASS verdicts
that were wrong about mergeability. Read the full history in issue #172
before starting.

## What to change

- `AGENTS.md` §10 (around the `CHANGES_REQUESTED` line, ~line 168): replace
  the unconditional "doesn't block" claim with the conditional rule from the
  decision above — it blocks a merge where a ruleset enforces the
  `pull_request` rule on that repo; the remedy is to fix the finding or have
  Scott dismiss it. An independent review is still required regardless (keep
  §10.4's existing substance on that point).
- Name which enrolled repos currently have such a ruleset (as of this PR:
  software-factory, activity-feed, gh-factory, line, adamsuk — verify this
  list rather than copying it blindly), or point at one single place that
  already lists them (e.g. wherever `gh factory plan`'s enrolled-repo list or
  the ruleset baseline is documented) so there's one home for the list, not a
  copy that goes stale again.
- `agents/roles/reviewer.md:26`: same correction, and add a requirement that
  the verdict comment state the PR's **observed** `mergeStateStatus` (read via
  `gh pr view --json mergeStateStatus` or equivalent) for the head under
  review — not an inference from reading the rules.
- Do not make any claim about whether the ruleset's `bypass_actors` lets the
  owner merge over a standing stale review — that's #152's open question,
  being tested separately. Word this conditionally.

## Out of scope (do not do these in this attempt)

- Actually testing or changing `bypass_actors` behaviour — #152's job, not
  this one.
- #119's four-field review record format itself, if it doesn't already exist
  as a concrete template in this repo — just make sure the verdict states
  `mergeStateStatus` somewhere, worded so #119 can absorb it later without
  contradiction.
- Any change to the ruleset itself, or to which repos are enrolled.

## Acceptance criteria

- [ ] `AGENTS.md` §10 and `agents/roles/reviewer.md` state the blocking rule
      correctly, conditional on a ruleset enforcing it
- [ ] Both name which enrolled repos currently have such a ruleset, or point
      at a single place that does
- [ ] The reviewer brief requires the verdict to report the observed
      `mergeStateStatus` for the head under review
- [ ] `CHANGELOG.md` gains a dated entry in the form the top of that file
      describes
- [ ] A post-change verdict on a real pull request reports the observed
      `mergeStateStatus` and the head SHA used for the observation

## Report back

In the PR body: which repos you verified have the `factory-main` ruleset
right now (show the check, don't just assert it), and confirm you did not make
any claim about `bypass_actors`/#152. This PR touches `AGENTS.md` and
`agents/roles/reviewer.md`, both protected under §5 — say so explicitly and
expect Scott's review regardless of verdict.
