---
repo: adamsuk/software-factory
issue: 355
issue_repo: adamsuk/software-factory
title: "feat: open the metrics PR with the factory App token (#355)"
branch: factory/355-metrics-app-token
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-12
---

## Goal
Open the weekly `factory/metrics-<date>` PR from `.github/workflows/metrics.yml` with a short-lived GitHub App installation token (Actions secrets `FACTORY_GH_APP_ID` and `FACTORY_GH_APP_PRIVATE_KEY`) so required checks run on it, and make the missing cost ledger explicit in each snapshot instead of inventing numbers.

## Acceptance criteria
- [ ] `metrics.yml` mints a token with a SHA-pinned `actions/create-github-app-token` from the two secrets and uses it for the checkout, push and `gh pr create`; secret names only in the header.
- [ ] Each generated `metrics/<date>.md` states in a `## Ledger` note why rework rounds and cost per change are n/a.
- [ ] `scripts/test-metrics-workflow.sh` asserts the token step, the secret names and the ledger note, and fails on the old workflow.
- [ ] `CHANGELOG.md` has a dated entry.

## Notes
- Protected path (AGENTS.md §5): `.github/workflows/metrics.yml`. Goes to the maintainer.
- Not checkable before merge: whether the App token triggers checks on a real PR (first scheduled run 16 Nov, or workflow_dispatch).
