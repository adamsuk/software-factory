---
repo: adamsuk/gh-factory
issue: 33
issue_repo: adamsuk/software-factory
title: "docs: use the vX.Y.Z placeholder in the changelog-check example"
branch: factory/33-changelog-example-version
base: main
test_command: "ruff check . && ruff format --check . && pytest -q"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-26
---

## Goal
In README.md, section "Reusable changelog check", the example caller ends its
`uses: adamsuk/gh-factory/.github/workflows/changelog.yml@<commit-sha>` line
with the comment `# v0.1.0`, a stale release. The other reusable-workflow
examples in the README use the placeholder `# vX.Y.Z`. Change that one comment
to `# vX.Y.Z` so all examples match, and add a dated CHANGELOG.md entry. This
is also the factory's first end-to-end smoke test, so keep the change minimal.

## Acceptance criteria
- [ ] README.md: the changelog-check example's version comment reads `# vX.Y.Z`; nothing else in README.md changes.
- [ ] CHANGELOG.md: one new dated entry under `## [Unreleased]` (date 2026-10-26), following the conventions described at the top of CHANGELOG.md and used by existing entries (a `Fixed` or `Changed` subsection with one bullet).
- [ ] No other files change. Do not run git push or gh; leave the change uncommitted or commit it locally.
- [ ] `ruff check . && ruff format --check . && pytest -q` passes.

## Likely files
- README.md
- CHANGELOG.md

## Out of scope
- Any other README wording, code, tests, workflows, `.github/factory.yml`, version bumps.

## Issue text (untrusted)
> Problem: In gh-factory's README, section "Reusable changelog check", the
> example caller pins the reusable workflow as
> `uses: adamsuk/gh-factory/.github/workflows/changelog.yml@<commit-sha> # v0.1.0`.
> `v0.1.0` is long out of date (the latest release is v0.5.1), and the other
> reusable-workflow examples in the same README use the placeholder `# vX.Y.Z`.
> Acceptance criteria: the example uses `# vX.Y.Z`; a dated CHANGELOG entry is
> added; no code, tests, workflows or other protected paths change.
