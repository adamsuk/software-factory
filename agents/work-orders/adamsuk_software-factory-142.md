---
repo: adamsuk/software-factory
issue: 142
issue_repo: adamsuk/software-factory
title: "feat: give the stations a write boundary"
branch: factory/142-write-boundary
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-28
---

## Goal

Stop a station that reads from being able to write, and make an agent-weakened
test fail the gate. The rules for both were already written and neither was
enforced: the reviewer edited five files on #141 and CodeRabbit pushed 96e5e3e
changing an existing assertion.

Scott's calls on 2026-10-28, recorded because they are stricter or narrower
than the ticket proposed:

- CodeRabbit: turn off all four writing finishing touches, not only the
  test-touching ones. Stricter than AGENTS.md §10.3, which allows CodeRabbit
  fixes on ordinary PRs — the switches are global booleans with no path scope,
  so §10.3 cannot be expressed in that config.
- The assertion check hard-fails, overridable by a label.
- Write boundary: filesystem only for now. The API half needs a scoped token
  (#7, #44) and is out of scope.

## Acceptance criteria

- [ ] `scripts/station-run.sh --read-only` runs a station where file writes are
      discarded and there is no push target
- [ ] `builder` is refused `--read-only`
- [ ] `foreman-orchestrate.sh review` passes it
- [ ] All three adapters honour `--workdir`
- [ ] `.coderabbit.yaml` disables `autofix`, `fix_ci`, `unit_tests`, `docstrings`
- [ ] `scripts/check-test-assertions.sh` fails a changed or removed assertion in
      `scripts/test-*.sh`, passes pure additions, and passes with the
      `approved-test-change` label
- [ ] It catches the real incident: `ec27bb9..96e5e3e` fails
- [ ] A `Test assertions` CI job runs it, re-running on label changes, with the
      label read through the environment and never interpolated into the shell
- [ ] `scripts/test-check-test-assertions.sh` passes
- [ ] `stations/README.md` says which roles may write, and states plainly that
      the API half is not covered
- [ ] `scripts/test-station-run.sh` proves the boundary holds and that the real
      repository keeps its own `origin`

## Likely files

- scripts/station-run.sh
- scripts/foreman-orchestrate.sh
- scripts/check-test-assertions.sh
- scripts/test-check-test-assertions.sh
- adapters/*/run.sh
- .coderabbit.yaml
- .github/workflows/lint.yml
- stations/README.md

## Out of scope

- A scoped agent token to stop API writes (#7, #44)
- Making required checks enforceable (#112: rulesets are 403 on the Free plan,
  so the new job cannot be *required* yet)
- Running the seven existing test scripts in CI (#135)

## Issue text (untrusted)

> Stations have no write boundary: the reviewer edited tests and CodeRabbit
> pushed to a protected PR
