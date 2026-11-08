---
repo: adamsuk/software-factory
issue: 282
issue_repo: adamsuk/software-factory
title: "chore: remove private delivery-project attribution and retire obsolete work orders"
branch: factory/282-publication-cleanup
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-11-08
---

## Goal

Remove the private delivery-project attribution still present in this
repo's own documentation, and retire the generated work-order files whose
backing pull request is merged and whose filename is not referenced
anywhere else in the repo. The backing *source issue*'s own open/closed
state is not a gate: a station-umbrella issue such as #47 or #51 can stay
open by design while every scoped work order filed against it is complete
and retirement-safe. Both parts are owner-authorised, reference-removal /
bookkeeping-cleanup only: no test assertion, CI, dependency, lockfile,
licence, visibility, or history-rewrite change; no approval or merge; and
no closing of any source issue as a side effect.

## Acceptance criteria

- [ ] `README.md` and the three audits dated 24/25/26 October 2026 no longer
      contain the private delivery-project attribution named in those files
      before this change, with no placeholder that re-encodes a removed
      identifier
- [ ] Dates, scores, sample limits, security findings and stated uncertainty
      in the three audits are preserved exactly; no audit file is deleted
- [ ] Every file listed under "Likely files — retire" below, and only those
      files, is deleted from `agents/work-orders/`; no source issue is
      closed by this work order
- [ ] `agents/work-orders/adamsuk_software-factory-282.md` is added as this
      work order's own record; it is the only file added under
      `agents/work-orders/`
- [ ] `scripts/test-watcher-tree.sh` is byte-for-byte unchanged; its
      forbidden-string check is not touched
- [ ] `scripts/fixtures/replay-work-order.md` and
      `agents/work-orders/adamsuk_gh-factory-33.md` remain byte-for-byte
      identical to each other
- [ ] `CHANGELOG.md` gains exactly one new dated entry describing this
      cleanup, containing no private delivery-project identifier
- [ ] A diff review confirms only the listed reference-removal and
      retirement edits were made, with no incidental scope creep
- [ ] The configured `test_command` above passes

## Likely files — anonymise in place (do not delete)

- `README.md`
- `audits/2026-10-24.md`
- `audits/2026-10-25.md`
- `audits/2026-10-26.md`
- `CHANGELOG.md` (new dated entry only; existing entries unchanged)

## Likely files — add (new file)

- `agents/work-orders/adamsuk_software-factory-282.md` — this work order's
  own mandatory record (agents/roles/foreman.md: the foreman writes the work
  order to `agents/work-orders/<owner>_<repo>-<issue>.md`). This is the one
  addition under `agents/work-orders/` besides the deletions below.

## Likely files — retire (delete; exact allowlist)

- `agents/work-orders/adamsuk_gh-factory-160.md`
- `agents/work-orders/adamsuk_gh-factory-8.md`
- `agents/work-orders/adamsuk_line-110.md`
- `agents/work-orders/adamsuk_software-factory-157.md`
- `agents/work-orders/adamsuk_software-factory-124.md`
- `agents/work-orders/adamsuk_software-factory-136.md`
- `agents/work-orders/adamsuk_software-factory-140.md`
- `agents/work-orders/adamsuk_software-factory-142.md`
- `agents/work-orders/adamsuk_software-factory-145.md`
- `agents/work-orders/adamsuk_software-factory-147.md`
- `agents/work-orders/adamsuk_software-factory-148.md`
- `agents/work-orders/adamsuk_software-factory-154.md`
- `agents/work-orders/adamsuk_software-factory-155.md`
- `agents/work-orders/adamsuk_software-factory-162.md`
- `agents/work-orders/adamsuk_software-factory-165.md`
- `agents/work-orders/adamsuk_software-factory-171.md`
- `agents/work-orders/adamsuk_software-factory-172.md`
- `agents/work-orders/adamsuk_software-factory-174.md`
- `agents/work-orders/adamsuk_software-factory-177.md`
- `agents/work-orders/adamsuk_software-factory-21.md`
- `agents/work-orders/adamsuk_software-factory-212.md`
- `agents/work-orders/adamsuk_software-factory-217.md`
- `agents/work-orders/adamsuk_software-factory-26.md`
- `agents/work-orders/adamsuk_software-factory-275.md`
- `agents/work-orders/adamsuk_software-factory-44.md`
- `agents/work-orders/adamsuk_software-factory-106.md`
- `agents/work-orders/adamsuk_software-factory-106-fix2.md`
- `agents/work-orders/adamsuk_software-factory-106-fix3.md`
- `agents/work-orders/adamsuk_software-factory-106-fix4.md`
- `agents/work-orders/adamsuk_software-factory-135.md`
- `agents/work-orders/adamsuk_software-factory-135-step4.md`
- `agents/work-orders/adamsuk_software-factory-211.md`
- `agents/work-orders/adamsuk_software-factory-211-fix2.md`
- `agents/work-orders/adamsuk_software-factory-211-fix3.md`
- `agents/work-orders/adamsuk_software-factory-211-fix4.md`
- `agents/work-orders/adamsuk_software-factory-211-fix5.md`
- `agents/work-orders/adamsuk_software-factory-211-fix6.md`
- `agents/work-orders/adamsuk_software-factory-214.md`
- `agents/work-orders/adamsuk_software-factory-214-fix2.md`
- `agents/work-orders/adamsuk_software-factory-214-fix3.md`
- `agents/work-orders/adamsuk_software-factory-219.md`
- `agents/work-orders/adamsuk_software-factory-219-fix2.md`
- `agents/work-orders/adamsuk_software-factory-232.md`
- `agents/work-orders/adamsuk_software-factory-232-fix2.md`
- `agents/work-orders/adamsuk_software-factory-232-fix3.md`
- `agents/work-orders/adamsuk_software-factory-232-fix4.md`
- `agents/work-orders/adamsuk_software-factory-47.md`
- `agents/work-orders/adamsuk_software-factory-47-fix2.md`
- `agents/work-orders/adamsuk_software-factory-47-fix3.md`
- `agents/work-orders/adamsuk_software-factory-47-fix4.md`
- `agents/work-orders/adamsuk_software-factory-47-fix5.md`
- `agents/work-orders/adamsuk_software-factory-47-fix6.md`
- `agents/work-orders/adamsuk_software-factory-47-fix7.md`
- `agents/work-orders/adamsuk_software-factory-47-fix8.md`
- `agents/work-orders/adamsuk_software-factory-47-fix9.md`
- `agents/work-orders/adamsuk_software-factory-51.md`
- `agents/work-orders/adamsuk_software-factory-51-fix2.md`
- `agents/work-orders/adamsuk_software-factory-51-fix3.md`
- `agents/work-orders/adamsuk_software-factory-51-fix4.md`

(59 files deleted, plus the 1 new file added above. #47's 9 files and #51's
4 files retire even though issues #47 and #51 themselves stay open by
design — see Goal above.)

## Out of scope

- Any existing test assertion: no change, weakening, skip or removal.
- `scripts/test-watcher-tree.sh`'s forbidden-string list: read-only, stays
  byte-for-byte. The private-delivery-project string it guards against
  remains a publication blocker both before and after this work order: that
  check keeps the literal string it screens for by design, so landing the
  docs anonymisation does not, and is not meant to, resolve this point.
- CI config, dependency files, and lockfiles: no changes.
- History rewrite: no rebase, squash, or force-push of any existing commit.
- Licence selection and repository visibility: no changes.
- Approval or merge as part of this work order.
- Closing #47, #51, or any other source issue as a side effect of retiring
  its scoped work-order files.
- Any work-order file under `agents/work-orders/` not on the retire list
  above — `agents/work-orders/adamsuk_gh-factory-33.md` and
  `agents/work-orders/adamsuk_software-factory-138.md` only, each kept
  because it has a real dependency elsewhere in the repo (fixture source for
  `scripts/test-harness-eval.sh`; a path reference in `CHANGELOG.md`), not
  because its completion is in doubt.
- Deeper anonymisation of `audits/2026-10-28.md` or `audits/2026-11-03.md`
  (which carry only scoping mentions of the organisation's own name, not the
  private delivery-project attribution targeted above), org-level
  (`admin:org`-scoped) audit coverage, or any operational identifier
  (ruleset IDs, PostHog project ID, installation IDs) — explicitly deferred
  to a later, separately scoped security-disclosure review.
- Any change to the organisation-level merge pause, safety rules, protected
  paths, auth identities, merge permissions, or review requirements — all
  preserved verbatim.

## Issue text (untrusted)

> Target repo: adamsuk/software-factory
>
> **Goal**
> Remove all private-project identifiers currently present in docs,
> examples, work orders, and protected instructions. This is a
> reference-removal task only — no private project names are to appear
> anywhere in this issue, in commit messages, in the CHANGELOG entry, or in
> any associated discussion. Do not substitute placeholders that re-encode
> the identifier; simply remove the reference.
>
> **Explicitly out of scope**
> - No existing test assertion changes
> - No CI, dependency, or lockfile changes
> - No history rewrite (no rebase/squash/force-push of existing commits)
> - No licence selection
> - No repository visibility changes
> - No metadata cleanup beyond the reference removal itself
> - No approval or merge as part of this work order
>
> **Must be preserved exactly**
> - The existing organisation-level merge pause, verbatim, including its
>   organisation selector — do not edit, narrow, or re-word it
> - All safety rules
> - All protected paths
> - All auth identities
> - All merge permissions
> - All review requirements
>
> **Required for completion**
> - A dated CHANGELOG entry describing the reference-removal work (no
>   private-project names in the entry)
> - Configured test suite run under a fake `HOME` with no access to any
>   credential store
> - A diff verification step confirming only reference-removal edits were
>   made (no incidental scope creep)
> - Processed through normal intake → ready → work order → build → gates
>   flow
> - Independent review
> - Final approval by Scott
>
> **Sizing**
> Size: M, subject to confirmation at intake.
>
> **Deferred (not part of this work order)**
> - History rewrite/cleanup
> - Discussions cleanup
> - Build/release artifacts cleanup
> - Licensing decisions
> - Decision on whether the organisation name may be published
