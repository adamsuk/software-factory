---
repo: adamsuk/activity-feed
issue: 224
issue_repo: adamsuk/software-factory
title: "ci: pin Harden-Runner audit mode on deploy and CodeQL workflows"
branch: factory/224-harden-runner-audit
base: main
test_command: "npm test"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-03
---

## Goal

`deploy.yml` and `codeql.yml` have no Harden-Runner step. `changelog.yml`
is also named in the issue, but check it before assuming it needs a change
(see below).

## What to change

Add this exact step (the same pinned SHA `ci.yml` in `adamsuk/gh-factory`
uses) as the **first** step of **every job** in `deploy.yml` and
`codeql.yml`:

```yaml
      - uses: step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43 # v2.22.3
        with:
          egress-policy: audit
```

**Check `changelog.yml` first.** If, like in `adamsuk/gh-factory` and
`adamsuk/adamsuk`, its `changelog` job is a bare
`uses: adamsuk/gh-factory/.github/workflows/changelog.yml@<sha>` caller with
no `runs-on` and no steps of its own, there is nothing to pin there — a job
that only has `uses:` cannot have another step added. Say so plainly in the
PR body instead of silently skipping it. (The runner that actually executes
for every caller of that reusable workflow is gh-factory's own job, already
covered by adamsuk/software-factory#222 / adamsuk/gh-factory#41.)

The `deploy` job in `deploy.yml` must stay the only job using
`secrets.CF_API_TOKEN` — don't touch which job has that secret, only add the
Harden-Runner step above its existing first step (`actions/checkout`).

## Out of scope

- Pinning the currently-unpinned `actions/checkout@v7` / `actions/setup-node@v7`
  / `cloudflare/wrangler-action@v4` refs in `deploy.yml` to full commit SHAs —
  not what this issue asks for, and a separate concern from egress auditing.
- The production environment / required reviewer on `deploy.yml` (#11/#233) —
  separate issue.
- Switching `egress-policy` to a blocking allowlist.

## Acceptance criteria

- [ ] `deploy.yml` and `codeql.yml` each pin Harden-Runner at the same
      commit as gh-factory's `ci.yml`, first step of every job
- [ ] `changelog.yml` is either fixed the same way, or left alone with the
      PR body explaining why (bare reusable-workflow caller, no steps)
- [ ] The `deploy` job is still the only job with `secrets.CF_API_TOKEN`
- [ ] `npm test` passes
- [ ] `CHANGELOG.md` gains a dated entry
- [ ] No secret value appears in the diff

## Constraints

- `.github/workflows/**` is a protected path (AGENTS.md §5). Say so in the
  PR body; Scott reviews it regardless of verdict (the issue says the same).

## Issue text (untrusted)

> `deploy.yml`, `codeql.yml` and `changelog.yml` have no Harden-Runner step.
> The deploy job uses the Cloudflare deploy secret and has no approval
> environment (#11). This issue is the egress step only.
>
> Add the SHA-pinned Harden-Runner step from `adamsuk/gh-factory`
> `.github/workflows/ci.yml`, with `egress-policy: audit`, as the first step
> of every job in those three workflows. The deploy job remains the only job
> that uses the Cloudflare deploy secret.
>
> Workflow files are a protected path. Scott reviews the pull request.

## Report back

State plainly whether `changelog.yml` needed a change or was a no-op (and
why), and the test command run.
