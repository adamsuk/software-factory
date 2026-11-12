---
repo: adamsuk/gh-factory
issue: 321
issue_repo: adamsuk/software-factory
title: "ci: block runner egress on release.yml and mutation.yml (#321)"
branch: factory/321-harden-runner-block-rest
base: main
test_command: "ruff check . && ruff format --check . && pytest -q"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-12
---

## Goal
Switch Harden-Runner to `egress-policy: block` on gh-factory's `release.yml` and `mutation.yml`, using the allowlists the maintainer copied from the audited runs 43238355252 (publish path, v0.7.1) and 43237826346, and empty `AUDIT_UNTIL_LOGGED` in `tests/test_harden_runner_block.py`.

## Acceptance criteria
- [ ] `release.yml` blocks egress with exactly the five hosts from run 43238355252, and the PR links that run.
- [ ] `mutation.yml` blocks egress with exactly the three hosts from run 43237826346, and the PR links that run.
- [ ] `AUDIT_UNTIL_LOGGED` is empty and `ruff check . && ruff format --check . && pytest -q` passes.
- [ ] `CHANGELOG.md` has a dated entry.

## Notes
- Protected paths (AGENTS.md §5): `.github/workflows/**` and one existing test constant. Goes to the maintainer.
- Other repos calling `release.yml` at a pinned SHA are unaffected until they move the pin.
