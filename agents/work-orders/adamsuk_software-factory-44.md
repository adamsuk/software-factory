---
repo: adamsuk/software-factory
issue: 44
issue_repo: adamsuk/software-factory
title: "docs: document grok-build's run environment and prove it scrubs tokens from Grok Build's environment"
branch: factory/44-run-environment
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-run-work-order.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-30
---

## Scope: this is a slice of #44, not all of it

Station 02 Source (#44) is a big ticket, and most of it is correctly blocked
on #7 (a written identity decision from Scott) and later sandboxing work —
**do not attempt those parts.** This work order is only the two pieces of
#44's MVP that don't depend on #7:

1. `agents/grok-build.md` gets a dedicated **Run environment** section.
2. A test proves `scripts/run-work-order.sh` already does what it claims:
   it strips `GH_TOKEN`/`GITHUB_TOKEN` from Grok Build's environment before
   running it.

#8 (Harden-Runner audit mode) is already merged — nothing to do there.

## What to change

- `scripts/run-work-order.sh:554` already runs
  `env -u GH_TOKEN -u GITHUB_TOKEN grok --no-auto-update ...` — read the
  surrounding code to confirm nothing re-exports either variable into that
  same command afterward (for example via `setup_env`, which is a separate
  array used elsewhere for the *test* environment, not Grok's). Add a test
  to `scripts/test-run-work-order.sh` that proves this: run (or inspect) the
  actual command Grok Build is invoked with and confirm `GH_TOKEN` and
  `GITHUB_TOKEN` are both absent from it, even when both are set in the
  calling shell's environment before the script runs. Follow this test
  file's existing style — it mostly asserts against mocked commands or
  `declare -f` source text rather than running `main()` end-to-end with a
  real `grok`/`gh`; pick whichever already-established approach actually
  proves the claim, and say in the PR body which you used and why.
- Add a **Run environment** section to `agents/grok-build.md` (near "What
  the wrapper does" is a reasonable place, but use your judgement). It
  should say, plainly:
  - What box this runs on today: a shared machine, no per-agent sandbox,
    no network egress allowlist yet (that's #44's later/unblocked-by-#7
    work, not this one).
  - Which credentials exist on that box (the owner's `gh` token, the Grok
    CLI signed in to the owner's grok.com account) and which of those
    Grok Build itself is actually handed: none of them, by the `env -u`
    scrub this ticket just tested. Say this is a guardrail, not an
    isolation boundary — an agent with shell access on the box could still
    reach those credentials by other means; real isolation is tracked
    separately (reference #44 for the sandboxing half, and #7 for the
    identity decision, without attempting either here).
  - That `scripts/run-work-order.sh`'s `--deny 'Bash(git push*)' --deny
    'Bash(gh *)'` rules are the other half of today's guardrail (Grok
    can't push or call `gh` directly even if it had credentials to).

## Out of scope (do not do these in this attempt)

- #7 (bot identity: GitHub App vs machine user) — a decision for Scott,
  not a build task.
- Any actual sandboxing (container, E2B, Daytona, egress allowlist).
- `adapters/claudecode/run.sh` or `adapters/opencode/run.sh` — this ticket
  is about the grok path (`run-work-order.sh`) specifically, since that's
  what `agents/grok-build.md` documents. If the other adapters have the
  same gap, note it in the PR body as a finding, don't fix it here.

## Acceptance criteria

- [ ] `agents/grok-build.md` has a "Run environment" section covering the
      three points above
- [ ] A new test in `scripts/test-run-work-order.sh` proves `GH_TOKEN` and
      `GITHUB_TOKEN` are absent from the command Grok Build actually runs
      with, even when both are set in the environment beforehand
- [ ] `CHANGELOG.md` gains a dated entry in this repo's changelog style

## Report back

In the PR body: which testing approach you used for the token-scrub proof
(real environment inspection vs. source-text assertion) and why, and
whether you found the same gap (no test) in the opencode/claudecode
adapters as a side note (not fixed here). This PR touches
`agents/grok-build.md`, protected under §5 — say so explicitly and expect
Scott's review regardless of verdict.
