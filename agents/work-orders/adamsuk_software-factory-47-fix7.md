---
repo: adamsuk/software-factory
issue: 47
issue_repo: adamsuk/software-factory
title: "fix: count factory:building in the cap, scan past a capped candidate, record real should-fix counts"
branch: factory/47-review-station-cap
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-foreman-pick-cap.sh && bash scripts/test-station-post.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 7
created: 2026-10-30
---

## Goal

Round 7 of CodeRabbit's review on PR #188 found three issues. Four earlier
findings this round are already fixed and confirmed addressed — don't
touch those.

1. **(Major, partially in scope)** The cap's in-flight definition counts an
   open PR or a `factory/<issue>-*` branch, but not an issue that's merely
   labelled `factory:building` with neither yet (the window right after
   `station-post.sh pickup`, before a branch exists). Fix the wording gap:
   add `factory:building` to what counts as in-flight.

   CodeRabbit also asked for **atomic reservation / serializing concurrent
   Pick runs** so two simultaneous foreman runs can't both undercount and
   both pick. **Decline this part, with reason stated in the PR**: the cap
   is deliberately brief-only (same as every other Pick-step rule — see
   rounds 1-6), and true atomicity needs a real reservation mechanism
   (a lock, or a GitHub-side atomic check-and-set), which is a separate,
   larger engineering ticket, not a wording fix. There's also no evidence
   multiple foreman processes run concurrently today. Note this honestly
   as a known gap rather than pretending the wording fix solves it.

2. **(Major, Quick win)** When the oldest `factory:ready` issue targets a
   repo that's already at the cap, the Pick step currently just leaves it
   `factory:ready` and stops — it doesn't say to keep scanning for the
   next-oldest eligible candidate (which might target an uncapped repo).
   Fix: continue scanning in age order past a capped candidate; only
   report "review capacity is full" if *no* later candidate passes the
   cap.

3. **(Minor, Quick win, but real code)** `scripts/station-post.sh`'s
   `cmd_verdict` hardcodes `should-fix: 1` for FIX and `should-fix: 0` for
   every other verdict, including ESCALATE — so an ESCALATE verdict can
   never record the concrete should-fix findings round 6 said belong in
   it ("name its concrete findings as should-fix items within the
   ESCALATE verdict"). Add an optional `--should-fix N` argument to the
   `verdict` command; when given, use it instead of the hardcoded
   default. When omitted, keep today's behavior exactly (1 for FIX, 0
   otherwise) so existing callers don't break. Update
   `stations/github-writes.md`'s example invocation and
   `agents/roles/reviewer.md` to say the reviewer should pass the real
   count via `--should-fix` for FIX and ESCALATE verdicts.

## What to change

- `agents/roles/foreman.md`: items 1 (wording only) and 2 above, in the
  Pick step.
- `scripts/station-post.sh`: add `--should-fix N` to `cmd_verdict`'s
  argument parsing (validate it's a non-negative integer), use it when
  provided, keep the default fallback otherwise.
- `stations/github-writes.md`: update the example `verdict` invocation to
  show `--should-fix`.
- `agents/roles/reviewer.md`: say the verdict should pass the actual
  should-fix count via `--should-fix` for FIX and ESCALATE.

## New/updated tests needed

- `scripts/test-foreman-pick-cap.sh`: assert `factory:building` is named
  in the in-flight definition; assert the Pick step says to continue
  scanning past a capped candidate (non-vacuous: fails if that sentence is
  removed).
- `scripts/test-station-post.sh`: a case proving `--should-fix N` is
  accepted and reflected in the posted `should-fix: N` line; a case
  proving the old default behavior (no flag given) is unchanged for both
  FIX and a non-FIX verdict.

## Out of scope

- Real serialization/atomic reservation for concurrent Pick runs (see
  above — declined, documented, not attempted).
- Everything already fixed in rounds 1-6.

## Acceptance criteria

- [ ] `factory:building` counts as in-flight for the cap
- [ ] The decision to decline atomic reservation is stated explicitly in
      the PR body, with reasoning
- [ ] The Pick step scans past a capped candidate to the next eligible one
- [ ] `station-post.sh verdict` accepts `--should-fix N` and uses it when
      given, defaulting to today's behavior otherwise
- [ ] `agents/roles/reviewer.md` and `stations/github-writes.md` document
      passing the real count
- [ ] All existing cases in both test files still pass
- [ ] `shellcheck` stays clean

## Report back

In the PR body, state explicitly: what was fixed, and what was declined
(the concurrency/atomicity ask) and why. Show non-vacuity checks for the
new/changed test assertions.
