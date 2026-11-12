---
repo: adamsuk/line
issue: 353
issue_repo: adamsuk/software-factory
title: "ci: pin the Pages workflow actions by commit SHA (#353)"
branch: factory/353-pages-sha-pins
base: main
test_command: "npm run typecheck && npm run lint && npm run test:factory"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-12
---

## Goal
In `.github/workflows/pages.yml`, pin every non-local `uses:` to a full 40-hex commit SHA with a trailing version comment, and add a test that fails when any non-local `uses:` in the workflows is not pinned to 40 hex. Pages deploy behaviour does not change.

## Acceptance criteria
- [ ] `grep -E 'uses: [^.].*@' .github/workflows/pages.yml` shows only 40-hex SHAs, each with a version comment.
- [ ] A new test fails when a non-local `uses:` is not pinned to 40 hex. It is reachable from `npm run test:factory` (the required `test` job). Confirm it fails against the current tag pins before the fix. Model it on activity-feed's `src/workflows.test.ts`.
- [ ] `CHANGELOG.md` has a dated `## YYYY-MM-DD` entry (Europe/London).
- [ ] Resolve each SHA from the real upstream tag (for example `gh api repos/<owner>/<repo>/git/ref/tags/<tag>`, dereferencing annotated tags). Do not guess or reuse a SHA from memory. Say in the PR body how each was resolved.

## Likely files
- `.github/workflows/pages.yml`
- a new workflow test file under the existing test layout
- `CHANGELOG.md`

## Out of scope
- Changing Pages deploy behaviour (stays deploy=release under the human gate).
- Pinning other workflows. If the new test would fail on them, scope it to `pages.yml` or note it in the PR; do not widen the change silently.

## Notes
- Protected path (AGENTS.md §5): `.github/workflows/pages.yml`. PR goes to the maintainer; `agents.merge` is false for line.
- `step-security/harden-runner` is already SHA-pinned.

## Issue text (untrusted)
> Pin every `uses:` in line's `pages.yml` to a 40-hex commit SHA with a version comment, and add a test that fails on any unpinned non-local action, as activity-feed does in `src/workflows.test.ts`.
