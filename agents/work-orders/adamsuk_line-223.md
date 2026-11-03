---
repo: adamsuk/line
issue: 223
issue_repo: adamsuk/software-factory
title: "ci: pin Harden-Runner audit mode across line's workflows"
branch: factory/223-harden-runner-audit
base: main
test_command: "npm run typecheck && npm run lint && npm run test:factory"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-03
---

## Goal

`test.yml`, `pages.yml`, `codeql.yml` and `changelog.yml` have no
Harden-Runner step. Unlike some other repos in this audit, every job in all
four files here actually has its own `runs-on` and steps — there is no bare
reusable-workflow caller to work around.

## What to change

Add this exact step (the pinned SHA `ci.yml` in `adamsuk/gh-factory` uses)
as the **first** step of **every job** in all four workflows:

```yaml
      - uses: step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43 # v2.22.3
        with:
          egress-policy: audit
```

That's: `changelog.yml`'s `changelog` job; `codeql.yml`'s `analyze` job;
`pages.yml`'s **both** `build` and `deploy` jobs; `test.yml`'s `test` job.

## Out of scope

- Pinning the unpinned `actions/checkout@v4` / `actions/setup-node@v7`
  refs in `pages.yml` to full commit SHAs, or any other action-pinning
  cleanup — not what this issue asks for.
- Ruleset 25949731 (#114) — unchanged, out of scope per the issue.
- Switching `egress-policy` to a blocking allowlist.

## Acceptance criteria

- [ ] `test.yml`, `pages.yml` (both jobs), `codeql.yml` and `changelog.yml`
      each pin Harden-Runner at the same commit as gh-factory's `ci.yml`,
      first step of every job
- [ ] The ruleset is unchanged
- [ ] `npm run typecheck && npm run lint && npm run test:factory` passes
- [ ] `CHANGELOG.md` gains a dated `## YYYY-MM-DD` entry
- [ ] No secret value appears in the diff

## Constraints

- `.github/workflows/**` is a protected path (AGENTS.md §5). Say so in the
  PR body; Scott reviews it regardless of verdict (the issue says the
  same).

## Issue text (untrusted)

> `test.yml`, `pages.yml`, `codeql.yml` and `changelog.yml` have no
> Harden-Runner step. A failing test can already merge until the ruleset
> lists `test` and `changelog` (#114). This issue is the egress step only.
>
> Add the SHA-pinned Harden-Runner step from `adamsuk/gh-factory`
> `.github/workflows/ci.yml`, with `egress-policy: audit`, as the first
> step of every job in those four workflows.
>
> Workflow files are a protected path. Scott reviews the pull request.

## Report back

State the test command run and confirm all jobs across all four files were
covered, including both jobs in `pages.yml`.
