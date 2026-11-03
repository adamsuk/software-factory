---
repo: adamsuk/software-factory
issue: 214
issue_repo: adamsuk/software-factory
title: "ci: pin Harden-Runner audit mode on software-factory's own workflows"
branch: factory/214-harden-runner-audit
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-run-work-order.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-03
---

## Goal

No workflow in this repo runs Harden-Runner. Add the same SHA-pinned step
gh-factory's `ci.yml` uses, as the first step of every job, in `lint.yml`
(3 jobs: `shellcheck`, `test-assertions`, `tests`), `line-audit.yml` (1
job) and `ruleset-drift.yml` (1 job).

**Check `changelog.yml` first.** Like gh-factory's own `changelog.yml` and
every caller repo in this same audit (#222, #224, #225), this repo's
`changelog.yml` job is a bare
`uses: adamsuk/gh-factory/.github/workflows/changelog.yml@<sha>` caller
with no `runs-on` and no steps of its own — nothing to pin there. Say so in
the PR body rather than silently skipping it.

## What to change

Add this exact step, first step of every job, in `lint.yml`,
`line-audit.yml` and `ruleset-drift.yml`:

```yaml
      - uses: step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43 # v2.22.3
        with:
          egress-policy: audit
```

## Out of scope

- `changelog.yml` (see above — no-op, same as the sibling issues).
- Switching `egress-policy` to a blocking allowlist.
- Any other repo (#222, #223, #224, #225 are separate issues, already
  built).

## Acceptance criteria

- [ ] `lint.yml`, `line-audit.yml` and `ruleset-drift.yml` each pin
      Harden-Runner at the same commit as gh-factory's `ci.yml`, first
      step of every job
- [ ] `changelog.yml` is left alone, with the PR body explaining why
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh && bash
      scripts/test-run-work-order.sh` passes
- [ ] `CHANGELOG.md` gains a dated entry
- [ ] No secret value appears in the diff

## Constraints

- `.github/workflows/**` is a protected path (AGENTS.md §5). Say so in the
  PR body; Scott reviews it regardless of verdict.

## Issue text (untrusted)

> No workflow in this repo runs Harden-Runner. `lint.yml`, `changelog.yml`,
> `line-audit.yml` and `ruleset-drift.yml` have no egress audit step.
> gh-factory already pins the action on `ci.yml`.
>
> Add that same SHA-pinned step, with `egress-policy: audit`, as the first
> step of every job in the four workflows. Copy the `uses:` line from
> `adamsuk/gh-factory` `.github/workflows/ci.yml`.
>
> Workflow files are a protected path. Scott reviews the pull request.

## Report back

State plainly whether `changelog.yml` needed a change (it shouldn't) and
the test command run.
