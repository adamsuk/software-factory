---
repo: adamsuk/software-factory
issue: 47
issue_repo: adamsuk/software-factory
title: "fix: scope the L/XL header assertion to the Station block in test-foreman-pick-cap.sh"
branch: factory/47-review-station-cap
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-foreman-pick-cap.sh"
setup_command: ""
changelog: false
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-10-30
---

## Goal

CodeRabbit's second review round on PR #188 found one remaining real issue in
`scripts/test-foreman-pick-cap.sh`: the assertion
`grep -q 'L/XL' "$reviewer"` scans the **entire** `agents/roles/reviewer.md`
file, not just the `## Station` header block. So if someone later removed
the L/XL mention from the Station header but left it in step 6 (Independent
verdict), this assertion would still pass — it isn't actually testing what
its name claims ("reviewer header does not mention L/XL escalation").

(Its other finding this round, about `agents/work-orders/adamsuk_software-factory-47.md:78`,
is already fixed — the acceptance criterion it asked for is already in the
file at lines 79-81. That's a stale/carried-forward comment from the
previous round; do not change anything for it.)

## What to change

In `scripts/test-foreman-pick-cap.sh`, extract the `## Station` block from
`agents/roles/reviewer.md` the same way the existing code already extracts
the Pick step from `foreman.md` (`awk '/^## Station/{on=1} /^## /{on=0} on'`,
stopping at the next `## ` heading), and run the existing L/XL assertion
against that extracted block instead of the whole file.

## Out of scope

- The Independent verdict step's own L/XL assertion (already correctly
  scoped via the existing `verdict=$(awk ...)` extraction) — leave it alone.
- Anything else in this file or in `agents/roles/reviewer.md` or
  `agents/roles/foreman.md` — this is a one-assertion precision fix only.

## Acceptance criteria

- [ ] The Station-header L/XL assertion only passes when `## Station`
      itself (not some other part of the file) mentions L/XL
- [ ] All existing cases in `scripts/test-foreman-pick-cap.sh` still pass
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` stays clean

## Report back

Confirm the fix is non-vacuous: show that temporarily removing L/XL from
just the Station header (while leaving it in step 6) now fails the
Station-header assertion specifically, where it previously would have
passed. No changelog entry needed — this is a test-only precision fix on a
PR not yet merged.
