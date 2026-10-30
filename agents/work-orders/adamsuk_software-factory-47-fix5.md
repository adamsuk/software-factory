---
repo: adamsuk/software-factory
issue: 47
issue_repo: adamsuk/software-factory
title: "fix: apply the open-PR cap against the candidate's Target repo, including branch-only entries"
branch: factory/47-review-station-cap
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-foreman-pick-cap.sh"
setup_command: ""
changelog: false
merge_allowed: false
review_bot: coderabbit
attempt: 5
created: 2026-10-30
---

## Goal

CodeRabbit's full-review round on PR #188 found a real logic bug in the cap
itself (Major), plus two smaller precision issues. Two earlier findings on
this PR are already fixed and confirmed addressed — don't touch those.

**The logic bug:** the cap as written counts against "the PR's own repo
(the repo the branch and PR live in)" — but at the point the foreman is
deciding whether to **pick a new issue**, that candidate issue has no PR or
branch yet. There's nothing to read "the PR's own repo" from. The cap has
to be evaluated against the **candidate issue's `Target repo:` line**
(resolved in step 2, which happens right after Pick) — not a repo that
doesn't exist yet for this candidate. The counting must also explicitly
include branch-only in-flight entries (an issue that's been picked up and
has a branch but no PR yet), since the existing "in flight" definition
already covers that case and the cap must too.

## What to change

1. **`agents/roles/foreman.md`**, the Pick step's cap: reword so the cap is
   evaluated against the **candidate issue's `Target repo:`** (the repo
   resolved by step 2's logic — reference it rather than duplicating it),
   counting every in-flight factory entry in *that* repo: an open PR or a
   `factory/<issue>-*` branch, open-PR or branch-only. At 2 or more,
   don't pick this candidate; leave it `factory:ready`.
2. **`agents/roles/reviewer.md`**, the Station header: `factory:review` is
   a label on the **linked issue**, not on the PR itself (confirm this
   against how `scripts/station-post.sh` actually reads/transitions the
   label before wording it, rather than assuming) — reword "Takes in PRs
   labelled factory:review" to describe the PR whose **linked issue**
   carries that label.
3. **`scripts/test-foreman-pick-cap.sh`**: the two L/XL-escalation
   assertions (station block and verdict block) check for the right
   verdict/trigger wording but not that it actually routes to
   `factory:blocked` — swapping the destination to `factory:merge` in a
   mutated copy would still pass today. Strengthen both to also assert the
   `factory:blocked` destination is present for that escalation.

## New/updated tests needed

- A test proving the cap wording is evaluated against the candidate's
  `Target repo:`, not the PR's repo (since there's no PR yet for a fresh
  pick) — likely another `declare -f`/text-extraction style assertion on
  `foreman.md`'s Pick step, consistent with how this file already tests
  brief wording rather than running the foreman end-to-end.
- Strengthen the two existing L/XL destination assertions as described
  above, proven non-vacuous (fail if `factory:blocked` is swapped to
  `factory:merge` in a mutated copy, pass against the real file).

## Out of scope

- Any change to `foreman-orchestrate.sh` or other scripts — the cap stays
  brief-only, as already decided and documented; this round only fixes the
  wording's own internal logic error, not the enforcement mechanism.
- Anything else already fixed in earlier rounds.

## Acceptance criteria

- [ ] The cap is evaluated against the candidate issue's `Target repo:`,
      not "the PR's own repo" (which doesn't exist yet at Pick time)
- [ ] The cap counts branch-only in-flight entries explicitly, not just
      open PRs
- [ ] The reviewer Station header correctly attributes `factory:review` to
      the linked issue, not the PR itself
- [ ] Both L/XL test assertions also verify the `factory:blocked`
      destination, proven non-vacuous
- [ ] All existing cases in `scripts/test-foreman-pick-cap.sh` still pass
- [ ] `shellcheck` stays clean

## Report back

No changelog entry needed. Show the non-vacuity checks for both
strengthened/new assertions.
