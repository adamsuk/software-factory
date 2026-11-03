---
repo: adamsuk/gh-factory
issue: 222
issue_repo: adamsuk/software-factory
title: "ci: pin Harden-Runner audit mode on the remaining gh-factory workflows"
branch: factory/222-harden-runner-audit
base: main
test_command: "ruff check . && ruff format --check . && pytest -q"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-03
---

## Goal

`step-security/harden-runner` with `egress-policy: audit` is already the
first step of every job in `ci.yml`, `codeql.yml`, `drift-check.yml` and
`mutation.yml`. It's missing from `auto-release.yml`, `changelog.yml`,
`pr-title.yml`, `release.yml` and `size-label.yml`.

## What to change

Copy the exact Harden-Runner step from `ci.yml` (same pinned commit SHA,
`egress-policy: audit`) onto every job in the five workflows above that
lacks it, as the first step of that job:

```yaml
      - uses: step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43 # v2.22.3
        with:
          egress-policy: audit
```

Leave the four workflows that already have it untouched.

**`auto-release.yml`'s `release` job has no steps of its own** — it is a
bare `uses: ./.github/workflows/release.yml` caller with no `runs-on`. There
is nothing to pin there; the runner that actually executes the work is
`release.yml`'s own `release` job, which this work order already covers.
Say this explicitly in the PR body rather than silently skipping the file.

## Out of scope

- Switching `egress-policy` to a blocking allowlist, a box allowlist, or
  `baseline/` changes — audit mode only, per the issue. A blocking
  allowlist comes after the audit log has named the hosts.
- Other enrolled repos — each has (or will have) its own issue.

## Acceptance criteria

- [ ] `changelog.yml`, `pr-title.yml`, `release.yml` and `size-label.yml`
      each pin Harden-Runner at the same commit as `ci.yml`, as the first
      step of their job
- [ ] `auto-release.yml` is left as-is, with the PR body explaining why (its
      job has no steps of its own)
- [ ] The four workflows that already have the step (`ci.yml`, `codeql.yml`,
      `drift-check.yml`, `mutation.yml`) are unchanged
- [ ] `actionlint` stays clean on `.github/workflows/*.yml`
- [ ] `CHANGELOG.md` has a dated entry
- [ ] No secret value appears in the diff

## Constraints

- `.github/workflows/**` is CI config, protected under AGENTS.md §5. Say so
  in the PR body; Scott reviews it regardless of verdict (the issue itself
  says the same).

## Issue text (untrusted)

> `step-security/harden-runner` with `egress-policy: audit` is the first
> step of `ci.yml`, `codeql.yml`, `drift-check.yml` and `mutation.yml`. It
> does not block. It is absent from `auto-release.yml`, `changelog.yml`,
> `pr-title.yml`, `release.yml` and `size-label.yml`.
>
> Copy the Harden-Runner `uses:` line from `ci.yml`, including the full
> commit SHA, onto every job in the five workflows that lack it. Keep
> `egress-policy: audit`. Leave the four workflows that already have it on
> audit. A blocking allowlist comes after the audit log has named the
> hosts.
>
> Workflow files are a protected path. Scott reviews the pull request.

## Report back

In the PR body: confirm `auto-release.yml` was deliberately left alone and
why, and state the test command run.
