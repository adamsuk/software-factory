---
repo: adamsuk/software-factory
issue: 358
issue_repo: adamsuk/software-factory
title: "fix: fence the watcher's untrusted prompt text with fence-untrusted.sh"
branch: factory/358-watcher-fence
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-12
---

## Goal
Move the watcher's prompt composers off the fixed `<<<UNTRUSTED_DATA` markers
and onto the shared `scripts/fence-untrusted.sh` helper, in both
`scripts/watcher/watch.sh` and `scripts/watcher/watch.new.sh`. Keep the #320
triage fence interior behaviour unchanged. The maintainer confirmed on the
issue that the helper and its test are on `origin/main`; intake's block was a
stale-checkout false positive.

## Acceptance criteria
- [ ] New `scripts/test-watcher-fence.sh` checks that `write_untrusted_block`
      and `step_triage` in both watcher scripts emit no fixed
      `<<<UNTRUSTED_DATA` opener, and that a forged closer in the body does
      not end the fence. It fails against the pre-change composers.
- [ ] `write_untrusted_block` and `step_triage` in both watcher scripts use
      `scripts/fence-untrusted.sh` for their untrusted text.
- [ ] `step_triage` finds the helper in the fresh home-repo clone when the lane
      runs from a flat `FACTORY_WATCH_ROOT`, and fails closed (no prompt) if it
      is truly absent.
- [ ] `scripts/test-watcher-fence.sh` covers the checkout and flat layouts.
- [ ] `scripts/test-triage-fence-writes.sh` still passes on its current
      assertions, including the #281/#320 interior behaviour.
- [ ] `scripts/test-fence-untrusted.sh` still passes unchanged.
- [ ] All existing `scripts/test-*.sh` suites still pass. One exception is
      recorded below: `scripts/test-triage-ask.sh` asserts the fixed fence
      markers, so its marker checks are adapted to the random delimiter. No
      assertion is removed or weakened (see "Protected change").
- [ ] `CHANGELOG.md` gains a dated `## YYYY-MM-DD` (Europe/London) entry.

## Protected change (needs maintainer review)
`scripts/test-triage-ask.sh` is an existing test that asserts the fixed
`<<<UNTRUSTED_DATA` / `UNTRUSTED_DATA>>>` lines the watcher used to write
("approver comment was not untrusted data", "issue text cannot close the outer
untrusted block"). Moving the composer onto the random-delimiter helper makes
those exact-marker assertions fail by design. The change adapts them to accept
exactly one `<<<UNTRUSTED_DATA:<24 hex>` opener and its matching
`UNTRUSTED_DATA:<id>>>>` closer, and asserts the fixed markers are absent. It
does not delete a case or relax the containment checks: every needle must still
sit under the untrusted heading, inside the outer fence and inside a #281
fence. Per AGENTS.md section 5 this needs the maintainer's review (and the
`approved-test-change` label) before merge.

## Likely files
- `scripts/watcher/watch.sh`
- `scripts/watcher/watch.new.sh`
- `scripts/test-watcher-fence.sh` (new)
- `scripts/test-triage-ask.sh` (protected: marker assertions only)
- `scripts/watcher/README.md`
- `CHANGELOG.md`

## Out of scope
- Any change to `.github/workflows/**`, `agents/**`, lockfiles, or existing
  test assertions beyond the marker adaptation described above.
- The Grok Bot teammate configs and any boundary in front of the model.
- Unrelated watcher refactors.

## Issue text (untrusted)
> Target repo: adamsuk/software-factory
>
> ### Problem
>
> The 12 Nov 2026 line audit still scores `untrusted-issues` partial. `scripts/fence-untrusted.sh` (#346) uses a random per-call delimiter, and station bundles use it. The watcher does not. `scripts/watcher/watch.sh` `write_untrusted_block` (about line 1584) and the `step_triage` wrapper (about line 5215) still wrap untrusted text in the fixed `<<<UNTRUSTED_DATA` / `UNTRUSTED_DATA>>>` markers, defended only by `escape_untrusted` text substitution. The same fixed markers exist in `scripts/watcher/watch.new.sh`. The fixed form is the one the random delimiter replaced.
>
> ### Proposal
>
> Have the watcher's prompt composers pass untrusted text through `scripts/fence-untrusted.sh` instead of the fixed markers, in both `watch.sh` and `watch.new.sh`. Keep the #320 triage fence interior behaviour unchanged. Leave the choice of how to wire it to the implementer.
>
> ### Acceptance criteria
>
> - [ ] `scripts/test-watcher-fence.sh` fails on current main: it checks that `write_untrusted_block` and `step_triage` output contain no fixed `<<<UNTRUSTED_DATA` opener and that a forged closer inside the body does not end the fence.
> - [ ] `scripts/test-watcher-fence.sh` passes with the change and runs in the `tests` job in `.github/workflows/lint.yml` (it is picked up as a `scripts/test-*.sh`).
> - [ ] `scripts/test-triage-fence-writes.sh` still passes on its current assertions.
> - [ ] `scripts/test-fence-untrusted.sh` still passes unchanged.
> - [ ] `CHANGELOG.md` has a dated `## YYYY-MM-DD` entry.
>
> ### Context
>
> Size S to M. Part of #302 (`untrusted-issues`, Best practice). Out of scope: the Grok Bot teammate configs (not visible from this repo), a boundary in front of the model, and any change to `.github/workflows/**`, `agents/**` or existing assertions. Related: #304 (done, #320).
