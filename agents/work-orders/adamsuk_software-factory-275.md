---
repo: adamsuk/software-factory
issue: 275
issue_repo: adamsuk/software-factory
title: "feat: read-only pr-status script; foreman reports status from the gate view and addresses every review comment (#275)"
branch: factory/275-pr-status-gate-view
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh && bash scripts/test-pr-status.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-05
---

## Goal

Give the foreman a read-only view of a PR's true gate status instead of
trusting labels and `reviewDecision` alone, and require every review comment
(bot, independent review, human, or agent) to be fixed or explicitly skipped
and its thread resolved before another review is requested or a PR is
reported ready. Extend `agents/roles/foreman.md` to cover non-factory PRs
(for example Dependabot) the same way.

## Acceptance criteria

- [ ] Every review comment on a PR — from any reviewer (a review bot such as
      CodeRabbit, the independent review, a human, or another agent) — gets
      either a fix or a short written reason for skipping it, and the thread
      is resolved, before another review is requested or the PR is reported
      ready
- [ ] Any PR status the foreman reports comes from the required checks'
      state, the latest reviews on the head commit, and the count of
      unresolved review threads; one reviewer's PASS never overrides another
      reviewer's open comments
- [ ] A read-only status script (`scripts/pr-status.sh`) prints that view for
      every open PR in the factory repos, with its own test suite
      (`scripts/test-pr-status.sh`)
- [ ] Non-factory PRs (Dependabot and similar) are covered: green checks list
      it for Scott; failing checks get a diagnosis and a fix round, keeping
      dependency and lockfile changes protected so they go to Scott
- [ ] No tool-specific labels or rules (tool-agnostic)
- [ ] `CHANGELOG.md` has a dated entry

## Likely files

- `scripts/pr-status.sh` (new)
- `scripts/test-pr-status.sh` (new)
- `agents/roles/foreman.md`
- `CHANGELOG.md`

## Out of scope

- Changing the repo's `required_checks` list
- Any other repository
- Re-architecting `scripts/gate-issue.sh` itself (this adds a separate
  read-only script rather than a new gate-issue.sh mode)

## Protected paths (AGENTS.md section 5)

`agents/roles/foreman.md` is a protected agent-instruction file. This PR
touches it, so a PASS verdict goes to Scott, not an automatic merge, and any
further fix here (including a merge-conflict rebase) needs Scott, not an
agent fix-loop.

## Issue text (untrusted)

> ## Problem
> On 4 Nov 2026 the foreman made two status-report mistakes:
> 1. It reported software-factory #274 as needing only Scott's approval,
>    because the independent review had passed. But the review bot had left
>    two unresolved Major review threads on the head commit.
> 2. It listed line #55 and #58 (Dependabot) as "waiting on Scott" when both
>    were failing CI.
>
> ## Causes
> - When the foreman reports PR status, it reads labels and `reviewDecision`
>   instead of the gate's view, so it misses failing checks and unresolved
>   review comments.
> - `agents/roles/foreman.md` doesn't cover PRs the factory didn't open, such
>   as Dependabot ones.
>
> ## Acceptance
> - **Every review comment gets addressed.** This covers comments from any
>   reviewer: a review bot (for example CodeRabbit), the independent review,
>   a human, or another agent. Each one gets either a fix or a short written
>   reason for skipping it, and the thread is resolved, before anyone asks
>   for another review (a bot re-review, the independent review, or Scott)
>   and before the PR is reported as ready. Nothing in the rules is tied to
>   one review tool.
> - **Status comes from the gate's view.** Any PR status the foreman
>   reports, in a run or when Scott asks, comes from the required checks'
>   state, the latest reviews on the head commit and the count of unresolved
>   review threads. One reviewer's PASS never overrides another reviewer's
>   open comments.
> - **A read-only status script.** A read-only `gate-issue.sh` mode, or a
>   small `pr-status` script, prints that view for every open PR in the
>   factory repos, with tests.
> - **Non-factory PRs are covered.** For Dependabot and similar PRs:
>   - If all checks are green, list it for Scott.
>   - If checks fail, diagnose it and offer a fix round, keeping dependency
>     and lockfile changes protected so they go to Scott.
> - **Tool-agnostic.** No tool-specific labels or rules.
