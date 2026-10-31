---
repo: adamsuk/software-factory
issue: 47
issue_repo: adamsuk/software-factory
title: "fix: ESCALATE takes precedence over FIX for L/XL; sync changelog and a test gap"
branch: factory/47-review-station-cap
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-foreman-pick-cap.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 6
created: 2026-10-30
---

## Goal

Round 6 of CodeRabbit's review on PR #188 found one real design gap and
two small sync issues. One other finding this round is already fixed and
confirmed addressed — don't touch it.

**The design gap (needs a decision, made here — don't re-litigate it):**
`agents/roles/reviewer.md` line 42 says an L/XL change is reported as
ESCALATE; line 43 says concrete fixable findings get FIX. For an L/XL PR
that *also* has fixable findings, the brief doesn't say which wins, and
the two verdicts have different effects (`FIX` loops back to
`factory:building`; `ESCALATE` goes straight to `factory:blocked`).

**Decision: ESCALATE wins for an L/XL change, regardless of whether its
findings are individually fixable.** The reason: the whole point of the
L/XL rule is that size alone needs a person's eyes, independent of
correctness — looping an L/XL PR through up to 3 rounds of FIX before a
human ever sees it defeats that purpose. If there are concrete findings on
an L/XL PR, name them in the ESCALATE verdict (as should-fix items for
Scott's context) rather than routing through FIX first.

**The two sync issues:**
- `CHANGELOG.md`'s existing entry for #47 still describes the cap as "open
  agent PRs... counted in the PR's own repo" — stale since round 5 changed
  the rule to the candidate's `Target repo:`, counting branch-only entries
  too.
- `scripts/test-foreman-pick-cap.sh`'s cap assertion (`pickflat`, around
  line 17) checks for the phrase "candidate issue's `Target repo:`"
  appearing anywhere, which would also pass if the brief said "Do **not**
  evaluate the cap against the candidate issue's `Target repo:`" — it
  checks a fragment, not the actual positive instruction.

## What to change

1. **`agents/roles/reviewer.md`**, Independent verdict step: add one
   sentence stating ESCALATE takes precedence over FIX for an L/XL change
   — concrete findings on it are named as should-fix items within the
   ESCALATE verdict rather than looping through FIX first.
2. **`CHANGELOG.md`**: update the #47 entry to describe the cap as
   implemented (in-flight factory entries, including branch-only, counted
   against the candidate's `Target repo:`), per CodeRabbit's suggested
   wording.
3. **`scripts/test-foreman-pick-cap.sh`**: strengthen the `pickflat`
   assertion so a negated version of the instruction ("do not evaluate...")
   fails it — check for the actual positive instruction, not just a
   matching fragment.

## New/updated tests needed

- A test proving reviewer.md states ESCALATE wins over FIX for L/XL,
  non-vacuous (fails if that sentence is removed or inverted).
- The strengthened `pickflat` assertion itself, proven non-vacuous against
  a negated-instruction mutation.

## Out of scope

- Everything else already fixed in rounds 1-5.

## Acceptance criteria

- [ ] `agents/roles/reviewer.md` states ESCALATE takes precedence over FIX
      for an L/XL change
- [ ] `CHANGELOG.md`'s #47 entry matches the implemented cap rule
- [ ] The cap assertion in `scripts/test-foreman-pick-cap.sh` fails
      against a negated instruction, not just a missing fragment
- [ ] All existing cases in `scripts/test-foreman-pick-cap.sh` still pass
- [ ] `shellcheck` stays clean

## Report back

Show the non-vacuity checks for both strengthened/new assertions.
