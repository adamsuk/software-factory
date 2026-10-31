---
repo: adamsuk/software-factory
issue: 51
issue_repo: adamsuk/software-factory
title: "fix: identify the actual run-work-order.sh invocation, not the first mention"
branch: factory/51-brief-drift-check
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-brief-drift-check.sh"
setup_command: ""
changelog: false
merge_allowed: false
review_bot: coderabbit
attempt: 5
created: 2026-10-30
---

## Goal

CodeRabbit's full-review round on PR #187 found one more real bug in
`scripts/brief-drift-check.sh`, plus two small doc-accuracy issues in a
historical work-order file. Several other findings this round are already
fixed and confirmed addressed ("✅ Addressed in commit...") — don't touch
those.

**The real bug:** the invocation extraction (round 4's fix) now stops
after the *first* match of `run-work-order.sh` — but if the section's
first mention of the wrapper is in an introductory sentence (e.g. "Run it
with `run-work-order.sh` as shown below:") rather than the actual command
block, that intro line is what gets captured, and the real invocation
(with its flags) lower down is never read. An unsupported flag in the real
command would then pass the check. The fix needs to find the actual
invocation — not just the first textual mention of the wrapper's name —
and should fail (report drift, or a clear error) if no real invocation
block can be found at all.

**The doc-accuracy issues**, both in
`agents/work-orders/adamsuk_software-factory-51-fix2.md` (a historical
record, already merged into this branch from round 4):
- Its illustrative suggested-diff still shows the *old* truncating flag
  pattern (`\-\-[a-z][a-z-]*`) even though the real fix (applied to the
  actual script in round 3) already used the correct
  `\-\-[a-z][a-z0-9_-]*`. The example doesn't match what was actually
  done.
- Its described test fixture only mentions `--push2` (digits); the
  acceptance criteria talk about digits *or* underscores, but no
  underscore example (e.g. `--push_suffix`) is described anywhere in that
  file.

## What to change

1. **`scripts/brief-drift-check.sh`**: change the invocation-detection
   logic so it identifies the actual command block (not just the first
   line mentioning the wrapper's name). One reasonable approach: look for
   a line that matches `run-work-order\.sh` *and* looks like an actual
   invocation (e.g. is inside a code span/fence, or is followed
   immediately by `[--flag]`-style bracketed options on the same or next
   line) rather than prose. Pick whatever's simplest and matches how
   `agents/grok-build.md` actually formats the real invocation today —
   read the file before designing this. Add a fixture with an
   introductory prose mention of `run-work-order.sh` *before* the real
   command, carrying an unsupported flag in the real command, and confirm
   it's still caught.
2. **`agents/work-orders/adamsuk_software-factory-51-fix2.md`**: fix the
   illustrative diff's flag pattern to match what was actually shipped,
   and add a one-line mention of the underscore case (`--push_suffix`) so
   the historical record matches the real acceptance criteria.

## Out of scope

- Everything already fixed in rounds 1-4 (label extraction, exit-code
  wording, section-9 scoping, flag truncation, separate-line flags,
  required `stations/README.md`, first-match stopping for later mentions)
  — confirmed addressed, don't touch.

## Acceptance criteria

- [ ] An introductory prose mention of `run-work-order.sh` before the real
      command no longer causes the real command's flags to be missed
- [ ] A new test fixture proves this (introductory mention + real command
      with an unsupported flag, still caught), non-vacuous
- [ ] The round-4 work order's illustrative example matches the real
      shipped pattern and mentions the underscore case
- [ ] All existing cases in `scripts/test-brief-drift-check.sh` still pass
- [ ] `shellcheck` stays clean

## Report back

No changelog entry needed. Show the non-vacuity check for the new fixture.
