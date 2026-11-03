---
repo: adamsuk/software-factory
issue: 219
issue_repo: adamsuk/software-factory
title: "ci: scope the scheduled ruleset-drift run to adamsuk and fix a stale factory.yml comment"
branch: factory/219-ruleset-drift-scope
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-ruleset-drift-check.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-03
---

## Goal

The issue names `scripts/brief-drift-check.sh`, but check this against the
actual code before touching anything: `brief-drift-check.sh` is unrelated
(role-brief/label drift, not rulesets). The script that compares a repo's
enforced ruleset to its `.github/factory.yml` `required_checks` is
**`scripts/ruleset-drift-check.sh`**, invoked by
`.github/workflows/ruleset-drift.yml`. Verify which file actually owns this
behaviour before writing anything, and use the real one.

Reading `scripts/ruleset-drift-check.sh`: it already reports drift when
`gh factory plan`'s output marks `required_status_checks` as differing for
an enrolled repo (via the `update`/`create` ruleset-change actions). So the
comparison this issue asks for already exists in the script's logic — the
reason line's miss (`test` and `changelog` required in its `factory.yml`,
absent from ruleset 25949731) was never flagged is that the **scheduled
workflow run failed before it could check anything**: run 41474324566 died
on an empty `GH_TOKEN`, because `FACTORY_READ_TOKEN` is unset in this repo's
Actions secrets. That secret is Scott's to set (see below) — not something
this work order can do.

What this work order *can* still do, from the acceptance criteria:

## What to change

1. **`scripts/test-ruleset-drift-check.sh`**: add a new test case using a
   `PLAN_JSON` fixture (follow the existing fixture style in this file) that
   reproduces line's exact miss: an enrolled repo whose plan shows
   `required_status_checks` differing because the ruleset is missing `test`
   and `changelog`. Assert the script reports drift (exit 1) and names both
   checks. This is a **new** test case — don't touch any existing assertion
   in this file (AGENTS.md §5).
2. **`.github/factory.yml`** (this repo's own, protected): its comment
   currently says "GitHub enforces nothing until a ruleset exists" — that's
   stale; ruleset 26119160 already exists and enforces `ShellCheck`,
   `changelog / changelog` and `tests`. Reword the comment to match the
   current, true state (check the live ruleset via `gh api
   repos/adamsuk/software-factory/rulesets` if you need to confirm exactly
   what it enforces before wording this).
3. **`.github/workflows/ruleset-drift.yml`** (protected): the scheduled
   command currently passes `--owner adamsuk --owner touchlineHQ`. Per the
   acceptance criteria, change it to list only `--owner adamsuk`.

## Out of scope

- Setting `FACTORY_READ_TOKEN` itself, or anything else only Scott can do
  (see "Needs Scott" below) — the script-and-fixture change is independently
  testable without that secret existing (`PLAN_JSON` fixtures don't call
  `gh` for real).
- Adding `test` and `changelog` to line's actual ruleset 25949731 (#114) —
  separate issue, explicitly out of scope in the issue text.
- Any change to the drift-detection *logic* itself, if (as expected) reading
  the code confirms it already does the comparison correctly. If you find
  it does **not** actually catch line's case even with the right fixture,
  say so plainly and fix the logic gap — but verify first; don't assume the
  issue's framing over what the code does.

## Acceptance criteria

- [ ] A fixture where the ruleset omits a `factory.yml` required check fails
      `scripts/ruleset-drift-check.sh` (new test case, existing assertions
      untouched)
- [ ] That fixture reproduces line's miss specifically: `test` and
      `changelog` named in `factory.yml`, absent from the ruleset
- [ ] `adamsuk/software-factory`'s own `.github/factory.yml` no longer says
      GitHub enforces nothing until a ruleset exists
- [ ] `.github/workflows/ruleset-drift.yml`'s scheduled command lists only
      `--owner adamsuk`
- [ ] The test uses a fake token and prints no secret (consistent with the
      existing `MOCK_GH` fake-`gh` pattern in this file)
- [ ] `CHANGELOG.md` has a dated `## YYYY-MM-DD` entry
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh && bash
      scripts/test-ruleset-drift-check.sh` passes

## Constraints

- `.github/factory.yml` and `.github/workflows/ruleset-drift.yml` are
  protected paths (AGENTS.md §5: CI config and this repo's own factory
  config). Say so in the PR body; Scott reviews it regardless of verdict —
  the issue says the same.
- Do not weaken, remove or change any existing test assertion in
  `scripts/test-ruleset-drift-check.sh`; only add new ones.

## Needs Scott (not the build — report, don't attempt)

Set the (read-only) `FACTORY_READ_TOKEN` repository secret so the Monday
06:17 UTC scheduled run can actually call `gh factory plan` and read
rulesets across the enrolled repos. The secret value must never appear in
the repo, logs, or this issue/PR. Nothing in this work order depends on
that secret existing — the script and its new fixture are both testable
with `PLAN_JSON` fake output.

## Issue text (untrusted)

> `scripts/brief-drift-check.sh` does not compare `.github/factory.yml`
> `required_checks` to the ruleset. `ruleset-drift.yml` is scheduled Mondays
> 06:17 UTC. Its run 41474324566 failed with an empty `GH_TOKEN` (`gh
> factory plan` exit 2). Actions secrets on software-factory are empty, so
> `FACTORY_READ_TOKEN` is unset. line's factory file requires `test` and
> `changelog`, and ruleset 25949731 requires neither. software-factory
> `.github/factory.yml` still says GitHub enforces nothing until a ruleset
> exists, while ruleset 26119160 requires `ShellCheck`, `changelog /
> changelog` and `tests`.
>
> Extend the drift check so a ruleset that omits a `factory.yml` required
> check fails the job. Represent line's current miss in a fixture that uses
> fake gh output. Update the software-factory `factory.yml` sentence so it
> matches the active ruleset. The scheduled command lists only the adamsuk
> owner.
>
> Set the read-only actions secret the Monday workflow already expects, so
> the scheduled run can read rulesets. The secret value stays out of the
> repo, the logs and this issue.
>
> `.github/factory.yml` and the workflow are protected paths. Scott reviews
> the pull request.

## Report back

Say explicitly which script actually owns this check (confirm or correct
the issue's filename), whether the drift logic already caught line's case
or needed a real fix, and that the `FACTORY_READ_TOKEN` secret is Scott's
to set, not something this PR did.
