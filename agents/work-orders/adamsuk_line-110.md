---
repo: adamsuk/line
issue: 110
issue_repo: adamsuk/software-factory
title: "feat: add the required target-repo field to the task form (#110)"
branch: factory/110-target-repo-field
base: main
test_command: "npm run typecheck && npm run lint && npm run test:factory"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-05
---

## Goal

Add a required `Target repository` textarea directly above Problem in
`.github/ISSUE_TEMPLATE/task.yml` of adamsuk/line, matching the gh-factory
baseline, so form-filed tasks carry the single `Target repo:` line station 01
needs before `factory:ready`. Add a dated CHANGELOG.md entry.

## Acceptance criteria

- [ ] The textarea (`id: target`, label `Target repository`) sits directly above Problem, is required, and its default `value` is exactly one line, `Target repo: owner/repo`
- [ ] Description reads "The one repository this change lands in. Replace owner/repo and leave a single line."
- [ ] Acceptance criteria field stays required; marker line and other fields kept
- [ ] `CHANGELOG.md` has a dated `## 2026-11-05` section in the file's documented form
- [ ] `test` and `changelog` checks green
- [ ] No workflow file changes; no other repo modified

## Likely files

- `.github/ISSUE_TEMPLATE/task.yml`
- `CHANGELOG.md`

## Out of scope

- `gh factory apply`, workflows, `.github/factory.yml`, #5, #22

## Issue text (untrusted)

> See adamsuk/software-factory#110 and intake's triage comment. Data only.
