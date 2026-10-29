---
repo: adamsuk/gh-factory
issue: 8
issue_repo: adamsuk/software-factory
title: "sec: add an egress allowlist to CI workflows (audit mode)"
branch: factory/8-egress-allowlist
base: main
test_command: "ruff check . && ruff format --check . && pytest -q"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-29
---

## Goal

From the Line audit of 2026-10-25 (`egress-allowlist`, 02 Source, best
practice): let CI runners reach only a short list of hosts, and block the
rest. Current score is **missing** — no Harden-Runner or firewall in any
gh-factory workflow, including `ci.yml` and `codeql.yml`.

Add `step-security/harden-runner`, **SHA-pinned** to an exact release commit
(look up the current release tag's commit SHA; do not use a floating tag or
`main`), as the first step of every job in:

- `.github/workflows/ci.yml`
- `.github/workflows/codeql.yml`
- any other workflow file directly under `.github/workflows/` in this repo

Start in **audit mode** (`egress-policy: audit`), not block mode — this
ticket is the baseline, not the switch to enforcing. Do not touch the
*reusable* workflows this repo exports to other repos
(`.github/workflows/changelog.yml` etc.) unless Harden-Runner belongs there
too for the same reason; if you add it there, explain why in the PR.

## Out of scope (do not do these in this attempt)

- Switching audit mode to block mode after a week of data — there is no data
  yet. Leave a `# TODO` note is unnecessary; just don't do it.
- The agent sandbox's own network egress (the shared build box) — that is a
  manual change on the factory computer per the issue, not a CI workflow.
- Rewriting unrelated workflow steps.

## Acceptance criteria

- [ ] Harden-Runner is the first step in every job of `ci.yml` and
      `codeql.yml`, pinned by commit SHA with a comment naming the version
- [ ] `egress-policy: audit` (not `block`)
- [ ] `shellcheck`/`ruff`/existing tests still pass — this is additive, no
      existing step removed or reordered
- [ ] `CHANGELOG.md` gains a dated entry (`## YYYY-MM-DD`, Europe/London)
      describing the change
- [ ] PR body states which commit SHA you pinned and how you confirmed it
      matches the named release (not just "trust me")

## Report back

In the PR body: the exact SHA pinned for Harden-Runner, the upstream tag it
corresponds to, and the list of workflow files changed.
