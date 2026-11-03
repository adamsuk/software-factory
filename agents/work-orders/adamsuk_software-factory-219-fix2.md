---
repo: adamsuk/software-factory
issue: 219
issue_repo: adamsuk/software-factory
title: "fix: name the missing required checks in a ruleset drift report"
branch: factory/219-ruleset-drift-scope
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-ruleset-drift-check.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-11-03
---

## Goal

PR adamsuk/software-factory#240's independent review (FIX verdict) found
that `scripts/ruleset-drift-check.sh`'s drift report for a
`required_status_checks` mismatch names only the key, never which checks
are actually missing. A previous "fix" round (commit "Fix CodeRabbit review
on factory/219-ruleset-drift-scope") only **acknowledged** the gap — it
added a `GAP (...)` warning to stderr but left the test case calling `pass`
regardless, and rewrote the CHANGELOG line to say the criterion isn't met.
That's not a fix. Actually fix it.

**Ground truth on the real data available, checked against
`adamsuk/gh-factory`'s `src/factory/plan.py` (`plan_ruleset`,
`ruleset_diff`):** a `required_status_checks` drift's `detail` string never
names individual checks (it's literally `"rule required_status_checks"` or
`"add rule required_status_checks"` in `reasons`). The **desired** check
list does exist, in the same change entry's `payload.body.rules[]` — the
rule object with `type == "required_status_checks"` has
`parameters.required_status_checks[].context` naming every check the
ruleset should require. There is no "existing" check list in the plan
payload to diff against directly.

## What to change

In `scripts/ruleset-drift-check.sh`, where the script currently builds the
`required_status_checks differs` report line: when that key is the one
differing for an `update` action, also do one more **read-only** `gh api`
call (same pattern as the existing `bypass_hidden()` probe below it — a
plain GET, nothing written) to read the ruleset's **current**
`required_status_checks` rule parameters
(`gh api repos/<repo>/rulesets/<id>` — the same ruleset id already
available from `bypass_hidden`'s lookup, or re-derive it the same way). Then
report the actual missing names: the desired contexts (from the plan's own
`payload.body.rules[]`, already present — no extra `gh api` call needed for
those) minus the ones already present on the live ruleset. Append them to
the report line, for example:
`o/line: required_status_checks differs (ruleset factory-main; missing: test, changelog)`.
If, for some reason, the live read fails or the rule is entirely absent on
the live ruleset (a `create` action, or an `update` where the rule type
isn't present at all), report the full desired list instead of a diff —
still naming real checks, not nothing.

For a `create` action (the ruleset doesn't exist at all yet), there's no
"existing" to diff against either — report the full desired check list
there too, from the same `payload.body.rules[]` source.

In `scripts/test-ruleset-drift-check.sh`: fix the fixture introduced for
line's miss so it has a believable payload shape (a plan entry with
`payload.body.rules` naming `test` and `changelog`, following the real
`gh-factory` plan JSON shape above — a fake `gh api rulesets/<id>` response
the test's fake `gh` returns for the live-read call, representing the
*current* ruleset with neither check). **Remove the `GAP (...)` warning
block entirely.** The case must `fail` (not warn-and-pass) unless the
output names both `test` and `changelog`.

Rewrite the 2026-11-03 CHANGELOG bullet once the report actually includes
both checks: it should no longer say "that script's report names the key
only... the names criterion is not met."

## Out of scope

- Everything else already fixed in round 1 (owner scoping, the stale
  factory.yml comment, `FACTORY_READ_TOKEN`) — untouched here.
- The `bypass_actors` reporting path — unrelated, don't touch it.

## Acceptance criteria

- [ ] The `required_status_checks` drift report line names the actual
      missing check(s) (e.g. `test`, `changelog`), sourced from the plan's
      own `payload.body.rules[]` desired list, diffed against one
      additional read-only `gh api` read of the live ruleset where
      possible
- [ ] `scripts/test-ruleset-drift-check.sh`'s line-miss case `fail`s (not
      warn-and-pass) unless the output names both `test` and `changelog`;
      the `GAP (...)` warning is removed
- [ ] The CHANGELOG bullet accurately says the criterion is now met
- [ ] All existing `test-ruleset-drift-check.sh` cases still pass
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` stays clean
- [ ] No secret value appears in the diff or test output

## Constraints

- `scripts/ruleset-drift-check.sh` and its test are not protected paths
  (not CI config, not `agents/**`), but this PR as a whole still touches
  `.github/factory.yml` and `.github/workflows/ruleset-drift.yml` from
  round 1 — unrelated to this round's diff, already noted as protected in
  the PR body.
- Only read-only `gh api` GETs — never write anything.

## Report back

Show the exact new report-line format with a worked example, and confirm
the test genuinely fails without the fix (remove the fix locally, show the
failure, then restore it) before calling it done.
