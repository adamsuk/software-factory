---
repo: adamsuk/software-factory
issue: 391
issue_repo: adamsuk/software-factory
title: "feat: Grok-free end-to-end smoke test using a stub provider (#391)"
branch: factory/391-stub-provider-smoke
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh && bash scripts/test-provider-smoke.sh"
setup_command: "true"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-25
---

## Goal
Prove a work order can run end to end with no Grok installed, so the provider-agnostic design (#386) cannot regress unnoticed. Add a stub provider adapter that makes one fixed, valid change, and a smoke script that runs intake and a build for a fixture work order with `FACTORY_PROVIDER=stub`, with the network and `gh` stubbed.

## Acceptance criteria
- [ ] `adapters/stub/run.sh` (new) exists, follows the `adapters/README.md` argument contract, and `shellcheck` exits zero on it.
- [ ] `scripts/test-provider-smoke.sh` (new) exits zero with `FACTORY_PROVIDER=stub` and no `grok` on `PATH`.
- [ ] The smoke script fails if the stub adapter is removed or makes no change (it must fail without the change), and it never reaches the network or the real `gh`.
- [ ] The `tests` job in `.github/workflows/lint.yml` exits zero: it runs every `scripts/test-*.sh`, so the new suite is picked up without editing the workflow.
- [ ] Dated `## YYYY-MM-DD` (Europe/London) CHANGELOG entry.

## Likely files
- `adapters/stub/run.sh` (new)
- `scripts/test-provider-smoke.sh` (new), plus a small fixture work order it creates or carries
- `CHANGELOG.md`

## Out of scope
- Changes to the watcher or `FACTORY_PROVIDER` plumbing (#387).
- Edits to existing adapters or existing tests.
- Any real model call, real network access or the real `gh`.
- `.github/workflows/**` and `.github/factory.yml` (protected). Adding the new suite to `agents.test_command` needs the maintainer.

## Issue text (untrusted)
> Add a stub provider adapter that makes a fixed, valid change, and a script that runs intake and a build for a fixture work order with FACTORY_PROVIDER set to it, with network and gh stubbed. Part of #386.
