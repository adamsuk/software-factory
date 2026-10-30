---
repo: adamsuk/software-factory
issue: 47
issue_repo: adamsuk/software-factory
title: "fix: L/XL PASS is operationally impossible to route to Scott; use ESCALATE"
branch: factory/47-review-station-cap
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-foreman-pick-cap.sh"
setup_command: ""
changelog: false
merge_allowed: false
review_bot: coderabbit
attempt: 3
created: 2026-10-30
---

## Goal

CodeRabbit's full-review round on PR #188 found a real bug in round 2's own
fix: `agents/roles/reviewer.md` says "PASS on a protected PR, or an L/XL
one, goes to Scott" — but `scripts/station-post.sh verdict` has no L/XL
input at all. A `PASS --protected no` call always sets `factory:merge`
regardless of size. So an L/XL, non-protected PR with a PASS verdict would
actually merge under standing permission, contradicting the stated rule.
The only verdict value that routes to `factory:blocked` is **ESCALATE**.

One other round-2 finding is already fixed and confirmed addressed
(`agents/work-orders/adamsuk_software-factory-47.md:78`) — don't touch it.

## What to change

1. **`agents/roles/reviewer.md`**, the Independent verdict step: change the
   rule from "PASS on a protected PR, or an L/XL one, goes to Scott" to use
   **ESCALATE** for an L/XL change, the same way protected paths already
   use ESCALATE's listed triggers. Keep the non-protected, non-L/XL PASS
   path and the size-judgment guidance (no CI size-label workflow wired up
   yet, judge from the diff) unchanged in substance.

2. **`agents/work-orders/adamsuk_software-factory-47-fix2.md`**: this
   historical work-order file has an illustrative `awk` example for
   extracting the `## Station` block that has a real bug (both the enable
   and disable patterns match `## Station`, so the block resets to empty on
   the same line it's enabled, same mistake the real test file avoided by
   adding `next`). Fix the example to match what
   `scripts/test-foreman-pick-cap.sh` actually does (add `next` after the
   enable match), since this file is a record of what was asked and should
   be accurate. This is a small doc-accuracy fix to a historical record,
   not a behavior change — low priority, but quick.

3. **`scripts/test-foreman-pick-cap.sh`**: the two L/XL assertions
   (Station-header block, lines ~27-28, and the Independent-verdict block,
   line ~40) currently just check that the substring `L/XL` appears
   somewhere in each extracted block. That would still pass even if the
   routing language were wrong or removed — e.g. the actual bug this round
   fixes (PASS instead of ESCALATE) wouldn't have been caught by the
   existing test. Strengthen both assertions to check that the block
   states the correct route: the Station block should say L/XL goes to
   Scott via ESCALATE (not PASS), and the Independent-verdict block should
   say the same.

## Out of scope

- Anything else in `reviewer.md`, `foreman.md`, or the cap logic — this
  round is the ESCALATE/PASS correctness bug and its two small follow-ons
  only.

## Acceptance criteria

- [ ] `agents/roles/reviewer.md` routes an L/XL change to Scott via
      **ESCALATE**, not PASS — consistent with how `station-post.sh
      verdict` actually routes (no PASS path reaches `factory:blocked`)
- [ ] The illustrative `awk` example in
      `agents/work-orders/adamsuk_software-factory-47-fix2.md` matches the
      real, working extraction (includes `next`)
- [ ] Both L/XL test assertions in `scripts/test-foreman-pick-cap.sh`
      verify the correct routing language, not just the presence of the
      token "L/XL" — proven non-vacuous (the assertion must fail against a
      version that mentions L/XL but routes it to PASS/merge instead of
      ESCALATE/blocked)
- [ ] All existing cases in `scripts/test-foreman-pick-cap.sh` still pass
- [ ] `shellcheck` stays clean

## Report back

No changelog entry needed (the existing dated entry for #47 already covers
this ticket; this is a correctness fix on a PR not yet merged). Show the
non-vacuity check for the strengthened test assertions.
