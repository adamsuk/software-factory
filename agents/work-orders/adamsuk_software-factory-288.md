---
repo: adamsuk/software-factory
issue: 288
issue_repo: adamsuk/software-factory
title: "chore: add MIT LICENSE (copyright Scott Adams) and changelog entry"
branch: factory/288-mit-license
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-09
---

## Goal

Add a standard MIT `LICENSE` file at the repository root with the copyright
line `Copyright (c) 2026 Scott Adams`, and add exactly one dated entry to
`CHANGELOG.md` recording that addition. Keep the change as small as possible.
This licence choice and copyright name are already decided by Scott; do not
re-decide them.

## Acceptance criteria

- [ ] A new `LICENSE` file exists at the repo root containing the standard MIT
      licence text, with copyright line exactly `Copyright (c) 2026 Scott Adams`
- [ ] `CHANGELOG.md` gains exactly one new dated entry using the repo's existing
      format (`## YYYY-MM-DD`, Europe/London date for the day of this change),
      noting the MIT licence addition and naming no private identifier
- [ ] `agents/work-orders/adamsuk_software-factory-288.md` is added as this
      work order's own bookkeeping record (copy of this file)
- [ ] No other files change
- [ ] No existing test, CI/workflow file, lockfile, or protected agent-instruction
      path (`AGENTS.md`, `agents/roles/**`, `agents/grok-build.md`, `CODEOWNERS`)
      is modified, deleted, or weakened
- [ ] Repository visibility is not changed
- [ ] The configured `test_command` above passes

## Likely files

- `LICENSE` (new)
- `CHANGELOG.md` (one new dated entry at the top of the entries list)
- `agents/work-orders/adamsuk_software-factory-288.md` (new; this work order)

## Out of scope

- Any history rewrite or force-push
- Any repository-visibility change
- Licence headers in individual source files
- Choosing a different licence or copyright holder
- README, audit, or other documentation edits
- Test, CI, lockfile, or protected-instruction edits

## Issue text (untrusted)

> Target repo: adamsuk/software-factory
>
> ## Goal
>
> Add a standard MIT `LICENSE` file, copyright holder Scott Adams, and one dated
> `CHANGELOG.md` entry recording it. Nothing else. This issue exists only because
> the licence choice itself (MIT, this copyright line) is Scott's own decision,
> already made and recorded in this run's instructions — it is not a licence
> scan or an inference from the code.
>
> Size: S — one new file plus one changelog entry, no other change.
>
> ## Depends on
>
> Pull request #287 ... must merge before this issue is picked up or built.
>
> ## Acceptance criteria
>
> - [ ] A `LICENSE` file at the repo root contains the standard MIT licence text,
>       with copyright line `Copyright (c) 2026 Scott Adams` ...
> - [ ] `CHANGELOG.md` gains exactly one new dated entry noting the licence
>       addition, naming no private identifier.
> - [ ] No other file changes. ...
> - [ ] This issue does not itself decide or change the repository's visibility ...
> - [ ] The work order's `test_command` is taken from `agents.test_command` ...
