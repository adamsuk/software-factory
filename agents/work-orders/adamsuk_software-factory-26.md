---
repo: adamsuk/software-factory
issue: 26
issue_repo: adamsuk/software-factory
title: "feat: track CodeRabbit comment acceptance per repo"
branch: factory/26-review-bot-measurement
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-factory-label-metrics.sh && bash scripts/test-factory-pr-metrics.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-29
---

## Goal

CodeRabbit is active across all five enrolled repos (`.coderabbit.yaml` is
in place, that part of this issue is already done per gh-factory#16).
Nothing tracks whether its comments actually get acted on. The Line audit
found 22 of 52 CodeRabbit threads resolved across a sample (software-factory
14/35, gh-factory 6/6, activity-feed 0/5, line 1/5, adamsuk 1/1).

Build a script, `scripts/review-bot-metrics.sh`, that for a given repo (or
all enrolled repos) reports: total CodeRabbit review threads on recently
merged/closed PRs, how many were resolved vs left open, and the
acceptance rate. This is a **read-only** reporting tool, not a dashboard —
print a table a person can read, the way `scripts/factory-pr-metrics.sh`
and `scripts/factory-label-metrics.sh` already do for their own metrics
(follow their existing conventions: flags, output shape, error handling).

## Acceptance criteria

- [ ] `scripts/review-bot-metrics.sh --repo OWNER/REPO [--limit N]` prints:
      total CodeRabbit threads, resolved count, open count, acceptance
      rate, over the last N closed/merged PRs (default a sensible number,
      follow `factory-pr-metrics.sh`'s own default convention)
- [ ] Works across the five enrolled repos — don't hardcode one repo's
      name or shape
- [ ] Never writes anything — no comments, no labels, no file changes to
      the target repo
- [ ] A short note in the script's own header (or `stations/README.md`)
      says this exists so "re-test when the model changes" (the Line
      recommendation) has something to compare against later
- [ ] Tests follow the existing pattern in `scripts/test-factory-pr-metrics.sh`
      — stub `gh`, don't hit the network
- [ ] `CHANGELOG.md` gains a dated entry

## Out of scope

- Automating the "re-test on known bugs when the model changes" step —
  that's a manual process per the issue, not this ticket
- Any change to `.coderabbit.yaml` itself
- A persisted history/database of past runs — this prints current state
  each time it's run, same as the other `factory-*-metrics.sh` scripts

## Report back

In the PR body: a sample of the script's actual output against one real
enrolled repo (read-only, no side effects from running it).
