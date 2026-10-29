---
repo: adamsuk/software-factory
issue: 155
issue_repo: adamsuk/software-factory
title: "ci: pin shellcheck to 0.11.0 so the gate and the box agree"
branch: factory/155-work
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-10-29
---

## Goal

`.github/workflows/lint.yml` runs whatever `shellcheck` the `ubuntu-latest`
image happens to ship:

```yaml
- run: shellcheck --version && shellcheck scripts/*.sh adapters/*/run.sh
```

The version is printed, so it is visible, but it is not chosen. GitHub rolls the
image forward, so the gate's strictness changes with no commit here — a pull
request clean yesterday can go red today for a reason nobody authored, and a
check we rely on could vanish just as quietly. The factory box has 0.11.0 as of
2026-10-29, so local and CI are now two different linters.

Pin it to **0.11.0**.

## Approach

Download the official release and verify its digest in the workflow. Do **not**
add a third-party action: this repo already pins actions by commit SHA
(`actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1`), and a checksummed
download is the same discipline with one less dependency to trust.

Authoritative SHA256 digests for v0.11.0, read from the GitHub release API on
2026-10-29:

```
shellcheck-v0.11.0.linux.x86_64.tar.gz   b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6
shellcheck-v0.11.0.linux.x86_64.tar.xz   8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
shellcheck-v0.11.0.darwin.x86_64.tar.gz  c2c15e08df0e8fbc374c335b230a7ee958c313fa5714817a59aa59f1aa594f51
```

The darwin digest is the one verified on the box when 0.11.0 was installed there;
it is recorded so the local install and the CI pin trace to the same release.
CI runs linux x86_64.

## Acceptance criteria

- [ ] The `shellcheck` job installs 0.11.0 from the official release and verifies
      its SHA256 against the digest above **before running it**
- [ ] A digest mismatch **fails the job** with a message saying so, and does not
      fall back to the image's `shellcheck`. This is the failure mode that would
      make the pin decorative
- [ ] The pinned version appears in exactly **one** place, so a bump is one edit
- [ ] `shellcheck --version` is still printed in the log
- [ ] `.github/factory.yml` says which `shellcheck` the gate means, in a comment
- [ ] `README.md` tells a contributor how to install the same version locally
- [ ] `CHANGELOG.md` gains an entry under a `## YYYY-MM-DD` heading
      (Europe/London). `main` has a `## 2026-10-29` section with `### Added` and
      `### Fixed` — add to the right one, do not create a second dated heading.
      `changelog / changelog` does not verify this (#160)
- [ ] The job still lints `scripts/*.sh` and `adapters/*/run.sh` and exits 0

## Out of scope

- Changing which files are linted, or fixing any lint finding (there are none;
  `main` is clean at 0.11.0).
- The `tests` job, `required_checks`, or `agents.test_command`: #135 is done and
  this must not touch them.
- Installing anything on the factory box.

## Constraints

- `.github/workflows/lint.yml` and `.github/factory.yml` are CI config,
  protected under AGENTS.md §5. Say so in the pull request and ask for Scott's
  review.
- Pinning a version is the point: do not use `latest`, a tag that can move, or a
  package manager that resolves at run time.
- Change no `scripts/test-*.sh` file.
- `tests` is now a **required** check on this repo's ruleset, so the twelve
  suites must stay green.

## Issue text (untrusted)

> Pin shellcheck to 0.11.0 in CI so the gate and the factory box agree

## Attempt 2 — three findings on the download step

Checks are green, so AGENTS.md §4's cap does not apply: it governs the fix loop
"when required checks go red". These are review findings. The pull request is
`BLOCKED` by CodeRabbit's `CHANGES_REQUESTED` on the current head `cfa04f6`,
which the ruleset created today correctly enforces — so this must be fixed, not
dismissed.

1. **CodeRabbit, Minor — bound the transfer.** `curl` has no `--max-time`, so a
   download that connects and then stalls waits until the job's timeout, leaving
   the ShellCheck gate pending until someone cancels the run. Add a finite
   `--max-time`.

2. **The ShellCheck job has no `timeout-minutes` at all.** #135 added one to the
   `tests` job and this job never got one, so the stall above would sit for the
   six-hour default. Add a bound with real headroom: the job takes about 15
   seconds, so a few minutes is generous. Fixing only `--max-time` leaves the
   job unbounded for every other reason.

3. **Harden the download, disclosed as a nit in the pull request body.** Add
   `--proto '=https' --tlsv1.2` so the request cannot be downgraded, and a small
   `--retry` so a transient network error does not fail the gate outright. Keep
   `-fsSL`.

Do not weaken the digest check: it must still run before extraction and still
fail the job on mismatch with no fallback to the image's `shellcheck`. Leave the
single-place `SHELLCHECK_VERSION` and its paired digest as they are.

Nothing else changes. `shellcheck scripts/*.sh adapters/*/run.sh` stays clean and
the twelve suites stay green.
