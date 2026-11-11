---
repo: adamsuk/software-factory
issue: 296
issue_repo: adamsuk/software-factory
title: "test: use a generic sample owner in fixtures"
branch: factory/296-generic-test-fixtures
base: factory/295-portable-defaults
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-09
---

## Goal

Make the test fixtures generic. Test data uses the maintainer's GitHub handle as the sample owner in repo slugs and logins, in roughly 350 lines across about 12 test files and one fixture. Replace it with the neutral sample owner `acme`, which `scripts/test-station-run.sh` already uses.

Size: M (protected: edits existing tests, fixture data only)

## Authorisation

The maintainer authorised these protected test edits on 9 Nov 2026 (Europe/London), solely for this generalisation. No assertion may be removed or weakened. An expected value may change only in step with its fixture owner. The maintainer will review and approve the PR.

## Scope

- Replace the sample owner in fixture repo slugs, logins and expected values in `scripts/test-*.sh` and `scripts/fixtures/replay-work-order.md` with `acme`. For example, `acme/software-factory`, `acme/gh-factory` and login `acme`.
- Where a script under test still requires its owner or approver to match, set the relevant env var (`FACTORY_HOME_REPO`, `FACTORY_REPOS`, `FACTORY_APPROVER_LOGIN`) in the fixture env rather than changing the script.
- Leave the deny-list needles and every safety check unchanged.

## Acceptance criteria

- [ ] `git grep -n adamsuk -- 'scripts/test-*.sh' scripts/fixtures` returns nothing.
- [ ] No assertion is removed or weakened. The PR body states "Existing tests: fixture owner changed only; expected values changed in step; no assertion removed or weakened".
- [ ] The full suite passes in CI and locally with `/workspace` and `/home/box` masked and a fake `HOME`.
- [ ] Non-test scripts, `AGENTS.md`, `agents/**` and `.github/**` are not changed.
- [ ] `CHANGELOG.md` gains exactly one new dated entry. Existing entries are not edited.

## Out of scope

- Script defaults (a separate issue), approving and merging.

## Builder notes

- This branch is cut from `factory/295-portable-defaults` (open PR #300), which adds `FACTORY_HOME_REPO`, `FACTORY_REPOS` and `FACTORY_APPROVER_LOGIN`. Use them in fixture env so scripts accept the `acme` owner. Do not change non-test scripts.
- Also run every `scripts/test-*.sh` you changed, where the box tooling allows (note any that cannot run locally).
- Add this work order as `agents/work-orders/adamsuk_software-factory-296.md` (bookkeeping copy of this file).
- Commit with a conventional message ending `(#296)`. Do not push, open PRs, or call `gh`; the runner does that.
- Run `agents.test_command` plus every extra test named in the acceptance criteria before finishing, and fix failures.
- Do not write the private delivery organisation's name anywhere (commit message, CHANGELOG, comments, tests).
