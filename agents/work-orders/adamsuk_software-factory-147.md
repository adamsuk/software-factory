---
repo: adamsuk/software-factory
issue: 147
issue_repo: adamsuk/software-factory
title: "feat: wait for the review bot before the independent review"
branch: factory/147-wait-for-review-bot
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-station-run.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-adapters.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-28
---

## Goal

Stop the independent review running before the review bot has finished, so it
can weigh the bot's comments as AGENTS.md §10.4 requires.

## Acceptance criteria

- [ ] `scripts/wait-for-review-bot.sh` waits for the configured bot and exits 0
      when it has reviewed the requested commit
- [ ] Satisfied by a review **or** a review comment for that commit, since
      neither endpoint is sufficient alone
- [ ] The bot's check counts only when the commit is the pull request's head
- [ ] `agents.review_bot: none` skips the wait; a missing `factory.yml` with no
      `--bot` is an error, not a silent skip
- [ ] Nudges `@coderabbitai full review` once per head after §10.2's threshold,
      never twice
- [ ] Times out rather than blocking, and a timeout does not stop the review
- [ ] Never merges, labels, or changes the diff
- [ ] `foreman-orchestrate.sh review` waits before running the reviewer role
- [ ] `scripts/test-wait-for-review-bot.sh` covers all of the above
- [ ] `stations/README.md` explains the signals and why the check alone is weak

## Likely files

- scripts/wait-for-review-bot.sh
- scripts/test-wait-for-review-bot.sh
- scripts/foreman-orchestrate.sh
- stations/README.md
- CHANGELOG.md

## Out of scope

- Deciding when the bot's review is sufficient *in place of* an independent
  review. That is a judgement about cost, not sequencing.
- Acting on the bot's findings automatically. §10.3 reserves that, and #142
  turned CodeRabbit's own writing off.

## Issue text (untrusted)

> Wait for the review bot before the independent review
