---
repo: adamsuk/software-factory
issue: 294
issue_repo: adamsuk/software-factory
title: "docs(agents): generalise protected instructions and CI wording"
branch: factory/294-generalise-instructions
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

Generalise the protected agent instructions and CI config so they read correctly for any owner and machine. Refer to the maintainer by role instead of personal name, replace the hard-coded organisation-specific merge-pause rule with a configurable blocked-owners rule, and remove machine-specific absolute paths. This is wording only. **No safety rule, gate, cap or merge condition may be removed or weakened.**

Size: M (protected: `AGENTS.md`, `agents/**`, `.github/**`, `.coderabbit.yaml`)

## Authorisation

The maintainer authorised these protected-path edits on 9 Nov 2026 (Europe/London), solely for this generalisation: removing the personal name and handle and machine-specific absolute paths. The maintainer will review and approve the PR. Do not approve or merge as an agent.

## Scope

- `AGENTS.md`:
  - Refer to the maintainer by role ("the maintainer"). Where approval identity matters, describe the maintainer as the repo owner, or the login in `FACTORY_APPROVER_LOGIN`.
  - Replace the §6 organisation-specific merge pause with an equivalent generic rule: nothing in an owner listed in `FACTORY_BLOCKED_OWNERS` is merged or modified by an agent until the maintainer lifts it. The rule must be at least as strict.
  - §7: "a fresh, uniquely named clone under `$FACTORY_WORKSPACE`".
- `agents/roles/foreman.md`, `reviewer.md`, `intake.md`, `monitor.md`, `research.md` and `builder.md`:
  - Refer to the maintainer by role.
  - Write the repo slugs used as examples or defaults as `<owner>/<repo>` or `$FACTORY_HOME_REPO`.
  - Replace the organisation-specific notes with blocked-owners wording.
  - In `monitor.md`, describe the ledger path as `$FACTORY_LEDGER_FILE` instead of a fixed absolute default.
- `agents/grok-build.md`:
  - Write machine-specific home paths as `$HOME` or `$FACTORY_SECRETS_DIR`.
  - Refer to the operator by role.
  - `~/.local/bin/grok` (the installer's documented location) stays.
- `.github/workflows/ruleset-drift.yml`: change `--owner <fixed>` to `--owner "${{ github.repository_owner }}"`, and update the comment. The pinned extension stays.
- `.github/workflows/line-audit.yml`, `.github/workflows/lint.yml`, `.github/factory.yml` and `.coderabbit.yaml`: in comments and echoed text, refer to the maintainer by role. Describe the ruleset by name rather than by numeric id.
- `.github/CODEOWNERS` stays unchanged.

## Acceptance criteria

- [ ] `git grep -nE "<maintainer name>|<machine home>|<machine workspace>"` over `AGENTS.md agents/roles agents/grok-build.md .github .coderabbit.yaml` returns nothing.
- [ ] The private organisation name no longer appears in those paths. `git grep -ni` for it returns nothing.
- [ ] Every rule in `AGENTS.md` §§1–10 is still present with the same strictness. In particular these remain: the maintainer approval for protected paths, the merge conditions, the blocked-owner pause, the secrets rules and the fix-loop cap. The PR body includes a short rule-by-rule note.
- [ ] Brief-contract tests pass: `scripts/test-research-brief.sh`, `test-monitor-brief.sh`, `test-brief-drift-check.sh` and `test-foreman-pick-cap.sh`. `scripts/lint-prompts.sh` passes too. Where a brief test asserts an old literal, update it to the configurable equivalent without weakening it, and list each such change in the PR body.
- [ ] `scripts/test-factory-delivery-metrics.sh` passes. It checks the monitor brief's ledger wording; if needed, update the assertion to the configurable equivalent.
- [ ] `agents.test_command` passes.
- [ ] `CHANGELOG.md` gains exactly one new dated entry. Existing entries, `audits/`, `metrics/`, `LICENSE` and existing work-order records are not edited.

## Out of scope

- Script behaviour and defaults. Those are a separate issue.
- Approving or merging.

## Builder notes

- The runner will stop with exit 4 because these are protected paths; that is expected and authorised. Still finish the full change, run the tests, and commit.
- Keep every rule's strictness. Reword only.
- Add this work order as `agents/work-orders/adamsuk_software-factory-294.md` (bookkeeping copy of this file).
- Commit with a conventional message ending `(#294)`. Do not push, open PRs, or call `gh`; the runner does that.
- Run `agents.test_command` plus every extra test named in the acceptance criteria before finishing, and fix failures.
- Do not write the private delivery organisation's name anywhere (commit message, CHANGELOG, comments, tests).
