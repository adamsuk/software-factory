---
repo: adamsuk/software-factory
issue: 211
issue_repo: adamsuk/software-factory
title: "fix: run the triage job and close the parent even with zero candidates"
branch: factory/211-research-audit-cycle
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-audit-triage.sh && bash scripts/test-sub-issues-all-closed.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 3
created: 2026-11-03
---

## Goal

CodeRabbit's review of PR adamsuk/software-factory#254 found a real bug in
`.github/workflows/line-audit.yml`: the `triage` job's `if` condition is

```yaml
if: needs.audit.result == 'success' && needs.gate.outputs.parent_issue != '' && needs.audit.outputs.candidates != ''
```

When a research-cycle audit genuinely finds nothing to flag (a clean
scorecard), `needs.audit.outputs.candidates` is empty, so this condition
is false and the whole `triage` job is skipped — including the part of
`scripts/audit-triage.sh` that posts the summary comment and **closes the
parent issue**. `scripts/audit-triage.sh` already handles an empty
candidate list correctly (see its existing test, "no candidates still
summarises and closes") — the workflow's `if` condition is what's wrong,
not the script.

## What to change

In `.github/workflows/line-audit.yml`, drop the
`needs.audit.outputs.candidates != ''` clause from the `triage` job's
`if:` condition, so it reads:

```yaml
if: needs.audit.result == 'success' && needs.gate.outputs.parent_issue != ''
```

The job still only runs after a successful audit and only when a
research-cycle parent is known (unchanged); it no longer additionally
requires non-empty candidates. `scripts/audit-triage.sh` is unchanged —
it already summarises and closes the parent when given an empty
candidates file.

## Out of scope

- Anything else in `line-audit.yml` or `scripts/audit-triage.sh` — both
  already correct otherwise.
- The cross-repo scoping from round 2 (#258 follow-up) — untouched.

## Acceptance criteria

- [ ] The `triage` job runs whenever the audit succeeded and a parent
      issue is known, even when the audit produced zero candidates
- [ ] A research-cycle parent with a clean (zero-candidate) audit result
      still gets its summary comment and gets closed
- [ ] `scripts/test-audit-triage.sh` and
      `scripts/test-sub-issues-all-closed.sh` still pass
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` stays clean
- [ ] `CHANGELOG.md` gets a short line noting the fix

## Constraints

- `.github/workflows/line-audit.yml` is a protected path (AGENTS.md §5),
  already true of this PR.
- This is a one-line YAML condition change — don't restructure the job.

## Report back

Confirm the exact new `if:` line, and that the YAML still parses (e.g. via
Ruby's `YAML.load_file` or equivalent, since `actionlint`/full CI aren't
available locally).
