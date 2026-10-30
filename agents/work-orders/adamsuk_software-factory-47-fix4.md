---
repo: adamsuk/software-factory
issue: 47
issue_repo: adamsuk/software-factory
title: "fix: protected PASS also routes to factory:blocked, not only ESCALATE"
branch: factory/47-review-station-cap
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-foreman-pick-cap.sh"
setup_command: ""
changelog: false
merge_allowed: false
review_bot: coderabbit
attempt: 4
created: 2026-10-30
---

## Goal

CodeRabbit found an imprecise claim introduced in round 3: both
`agents/roles/reviewer.md` (live, line ~41) and the round-3 work order
(`agents/work-orders/adamsuk_software-factory-47-fix3.md`, a historical
record) say "only ESCALATE routes to `factory:blocked`". Checked against
`scripts/station-post.sh`'s `cmd_verdict`: that's not quite right —
`PASS --protected yes` *also* routes to `factory:blocked`. Only
`PASS --protected no` routes to `factory:merge`. The L/XL point from round
3 is still correct (an L/XL verdict must be ESCALATE, since there's no
L/XL input to PASS/--protected) — only the "only ESCALATE" framing is too
absolute.

## What to change

- `agents/roles/reviewer.md`, the Independent verdict step: reword the
  parenthetical so it no longer claims ESCALATE is the *only* route to
  `factory:blocked`. State precisely: a protected `PASS` also routes to
  `factory:blocked`; only a non-protected `PASS` routes to `factory:merge`;
  for an L/XL change (which carries no protected/non-protected signal of
  its own), ESCALATE is the route that reaches `factory:blocked`.
- `agents/work-orders/adamsuk_software-factory-47-fix3.md`: same correction
  to its Goal section's framing, for an accurate historical record.
- `scripts/test-foreman-pick-cap.sh`: check whether the existing assertion
  text (added in round 3) asserts the "only ESCALATE" framing specifically,
  or just that ESCALATE is mentioned for L/XL — if it asserts the former,
  loosen it to match the corrected wording without losing what it actually
  needs to prove (that an L/XL change does not stay merge-able via PASS).

## Out of scope

- Anything else about the PASS/ESCALATE/protected routing — this is a
  wording-precision fix only, not a new rule.

## Acceptance criteria

- [ ] `agents/roles/reviewer.md` states the routing precisely: protected
      `PASS` and ESCALATE both route to `factory:blocked`; only
      non-protected `PASS` routes to `factory:merge`; L/XL requires
      ESCALATE
- [ ] The round-3 work order's framing is corrected to match
- [ ] `scripts/test-foreman-pick-cap.sh` still passes and still proves an
      L/XL change can't stay on the PASS/merge path
- [ ] `shellcheck` stays clean

## Report back

No changelog entry needed. Confirm the test still proves what it's meant
to prove after the wording loosens.
