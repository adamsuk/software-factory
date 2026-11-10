---
repo: adamsuk/software-factory
issue: 303
issue_repo: adamsuk/software-factory
title: "feat: verify ISSUE_TEMPLATE acceptance criteria are executable"
branch: factory/303-issue-template-checks
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-10
---

## Goal

Add a gate verifier so an acceptance-criterion checkbox in `.github/ISSUE_TEMPLATE/` cannot stay unexecuted prose. Each checkbox must name a `scripts/` path or a workflow job. A new test fails while the verifier is missing, and fails if the verifier accepts a fixture checkbox that names no command. The existing `tests` job in `.github/workflows/lint.yml` already runs every `scripts/test-*.sh`, so this lands without a workflow diff. Scott approved protected-path edits for this ticket on 9 Nov 2026 and will review the PR; still leave workflows, `agents/**`, and `AGENTS.md` unchanged unless the criteria cannot be met otherwise.

## Acceptance criteria

- [ ] New `scripts/test-issue-template-checks.sh` exits non-zero when the verifier is missing, and when the verifier exits zero on a fixture checkbox that names no command. It exits zero when that checkbox names a path under `scripts/`.
- [ ] New verifier under `scripts/` (path named in the PR; follow `scripts/check-test-assertions.sh` naming) exits non-zero when a markdown checkbox in `.github/ISSUE_TEMPLATE/` names neither a script path nor a workflow job.
- [ ] `.github/ISSUE_TEMPLATE/task.yml` is updated so every checkbox in that tree names a script path or workflow job (placeholder and description included). Remove the `factory-managed` marker so this repo owns the form; do not clone or edit `adamsuk/gh-factory`.
- [ ] No edit to `.github/workflows/**`. The existing `tests` job already runs `scripts/test-*.sh`, including the new test, and fails the job when that command exits non-zero.
- [ ] `CHANGELOG.md` gains one new dated `## YYYY-MM-DD` entry (Europe/London date of the change) for this verifier. Existing entries are not edited.
- [ ] `agents/work-orders/adamsuk_software-factory-303.md` is added as this work order's bookkeeping copy.
- [ ] `agents.test_command` (the `test_command` above) passes, and so does `bash scripts/test-issue-template-checks.sh`. New `scripts/*.sh` files must pass the shellcheck in that command.

## Likely files

- `scripts/check-issue-template-checks.sh` (new verifier; name it in the PR if you pick a different `scripts/` path)
- `scripts/test-issue-template-checks.sh` (new)
- `.github/ISSUE_TEMPLATE/task.yml` (checkbox text and drop `factory-managed`)
- `CHANGELOG.md` (one new dated entry)
- `agents/work-orders/adamsuk_software-factory-303.md` (new; this work order)

## Out of scope

- `.github/workflows/**`, `.github/factory.yml`, `.github/actions/**`, `.coderabbit.yaml`, lockfiles, `AGENTS.md`, `agents/roles/**`, `agents/grok-build.md`, and `CODEOWNERS`. Scott approved a workflow edit if it is required; it is not required here.
- Any other repository, including `adamsuk/gh-factory` and every touchlineHQ repo.
- Changing, removing, or weakening an existing test assertion. New tests and fixture data are allowed.
- Merging. `merge_allowed` is false. Parent #302 stays the epic.

## Issue text (untrusted)

> Target repo: adamsuk/software-factory
>
> ### Problem
>
> Audit 9 Nov 2026 scores done-as-checks partial. ISSUE_TEMPLATE acceptance criteria are prose. Nothing executes them, so a work order can be marked done with no check.
>
> ### Proposal
>
> Add a gate verifier that fails while any acceptance criterion stays unexecuted prose. Each criterion names a command the verifier runs. The change may edit scripts/ and agents/. Factory can build it.
>
> ### Acceptance criteria
>
> - [ ] A command under scripts/ (path named in the PR) exits non-zero when a checkbox in .github/ISSUE_TEMPLATE/ has no executable check.
> - [ ] Each acceptance criterion in .github/ISSUE_TEMPLATE/ names the script path or workflow job that verifies it.
> - [ ] A workflow file under .github/workflows/ runs that command on pull requests and fails the job when the command exits non-zero.
>
> ### Context
>
> Station 01 Backlog. Size M. Partial on guide.json v2026-11-03. Protected paths scripts/ and agents/ may change.
>
> Size: M.
>
> Scott must do: nothing (factory can build)
>
> Factory can build: Add the verifier and point every ISSUE_TEMPLATE acceptance criterion at a command it runs. May edit scripts/ and agents/.
>
> Protected paths: yes.
>
> Parent: #302 (MVP v1.0.0 Best practice).
