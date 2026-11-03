---
repo: adamsuk/software-factory
issue: 217
issue_repo: adamsuk/software-factory
title: "docs: run review-bot-metrics.sh in the weekly monitor procedure"
branch: factory/217-monitor-review-bot-metrics
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-review-bot-metrics.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-03
---

## Goal

`scripts/review-bot-metrics.sh` (read-only, already tested in
`scripts/test-review-bot-metrics.sh`) computes CodeRabbit comment
acceptance, but `agents/roles/monitor.md`'s weekly procedure never runs it,
so `metrics/<date>.md` carries no acceptance figure. Wire it in.

## What to change

`agents/roles/monitor.md` (protected path) steps 2 and 3:

- **Step 2 (Measure):** add a fourth read-only script to run,
  `scripts/review-bot-metrics.sh --repo adamsuk/software-factory` (no
  `--since`/`--until` — that script doesn't take them; it takes `--repo` and
  an optional `--limit`, read from `$REF` the same way as the other three).
  If it's missing on `$REF` or exits non-zero, same rule as the other three:
  commit nothing, report to Scott.
- **Step 3 (Record):** append this script's stdout to `metrics/<last-day>.md`
  after the three existing sections, separated the same way (one blank
  line).
- Keep auto-approve off; this issue does not touch any approval setting, and
  say so explicitly if a review of this PR questions it.

Do not change `scripts/review-bot-metrics.sh` itself or its existing test —
it's already correct and tested.

## New/updated tests needed

`scripts/test-run-work-order.sh` and `scripts/test-foreman-pick-cap.sh`
already prove role-brief wording with text-extraction assertions (`awk` +
`grep` against the real file, non-vacuous against a mutated copy). Follow
that same pattern for a new case (in one of those files, or a new
`scripts/test-monitor-brief.sh` if neither existing file's scope fits):
assert step 2 of `monitor.md` names
`scripts/review-bot-metrics.sh --repo adamsuk/software-factory`, and step 3
says its stdout is appended to the write-up. Prove it fails against a copy
with that line removed, passes against the real file.

Also run `scripts/review-bot-metrics.sh --repo adamsuk/software-factory`
once by hand (it's read-only) to confirm its stdout format actually
contains an "acceptance" line — that's the dry run the acceptance
criteria ask for, not a new script.

## Out of scope

- Publishing the delivery-metrics snapshot — separate issue, per the issue
  text.
- Reading the CodeRabbit dashboard or the autopilot checkbox — both
  explicitly out of git, per the issue's Problem section.
- Changing `scripts/review-bot-metrics.sh` itself.

## Acceptance criteria

- [ ] `agents/roles/monitor.md` names running
      `scripts/review-bot-metrics.sh --repo adamsuk/software-factory` as
      part of the weekly Measure step, and appending its stdout as part of
      Record
- [ ] A dry run of `scripts/review-bot-metrics.sh --repo adamsuk/software-factory`
      shows output containing an acceptance line
- [ ] The script stays read-only (no change to it) and prints no secret
- [ ] `CHANGELOG.md` has a dated entry
- [ ] Auto-approve stays off (no setting touched)

## Constraints

- `agents/roles/monitor.md` is a protected path (AGENTS.md §5, `agents/**`).
  Say so in the PR body; Scott reviews it regardless of verdict.

## Issue text (untrusted)

> `scripts/review-bot-metrics.sh` computes acceptance from a resolved
> thread whose comment author is not the bot. `agents/roles/monitor.md`
> does not run it. `metrics/` has no acceptance figure. Auto-approve is
> off. The CodeRabbit dashboard and the autopilot checkbox are outside
> git.
>
> Have the weekly monitor procedure run `scripts/review-bot-metrics.sh`
> for `adamsuk/software-factory` and include its stdout in
> `metrics/<date>.md`. Keep the script read-only. Keep auto-approve off.
>
> `agents/roles/monitor.md` is a protected path. Scott reviews the pull
> request.

## Report back

Quote the exact command line added to monitor.md, and paste a few lines of
the dry-run's acceptance output to confirm the format.
