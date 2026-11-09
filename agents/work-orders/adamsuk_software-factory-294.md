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
attempt: 2
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

## Fix round (attempt 2): independent review findings on head 352934a

The branch already contains the attempt-1 change. Make only these fixes, in this PR's own files. Do not delete files, change lockfiles or weaken tests.

- SF1 `agents/grok-build.md`: the Claude backend snippet must not claim that the secrets Read deny follows `$FACTORY_SECRETS_DIR` today. Show the guard with a neutral placeholder such as `Read(//<absolute secrets dir>/**)`, and say the wrapper writes the absolute secrets directory with the leading `//` anchor. Keep the `Bash(*factory-secrets*)` guard text.
- SF2 `agents/roles/monitor.md`: align the ledger default with the scripts in sibling PR #300: the ledger is `$FACTORY_LEDGER_FILE`, defaulting to `$FACTORY_HOME/factory-ledger.csv`, where `$FACTORY_HOME` defaults to `${XDG_DATA_HOME:-$HOME/.local/share}/software-factory` (see `scripts/watcher/README.md`). No machine path. Update the matching assertion in `scripts/test-factory-delivery-metrics.sh` to the new wording, and keep its negative check against a hard-coded ledger path. Neither check may get weaker.
- SF3 and the blocked-owner design (one approach for both PRs, matching #300's scripts): in `AGENTS.md` §6, the foreman/intake briefs and the CHANGELOG entry, `FACTORY_BLOCKED_OWNERS` is a space-separated list of owners that agents never clone, modify or merge until the maintainer lifts the pause (one named PR at a time may be approved). It has no default list: **unset or empty blocks no owner**; the operator sets it in the factory host's environment. The owner of the factory's home repo (`$FACTORY_HOME_REPO`) is never implied as blocked or unblocked by this rule beyond what the list says. Remove the "unset blocks every owner other than this repo's own owner" fail-closed sentence and the ambiguous "this repo's own owner" phrase. Keep every other §6 merge condition unchanged.
- Update this PR's CHANGELOG entry text if needed. Keep exactly one new entry.
- Copy this work order over `agents/work-orders/adamsuk_software-factory-294.md`, keeping the placeholders for literal search terms.
- Commit as `fix: address review findings (#294)`.
