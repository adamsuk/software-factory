---
repo: adamsuk/gh-factory
issue: 160
issue_repo: adamsuk/software-factory
title: "fix: make the changelog check verify a dated-entry form and window"
branch: factory/160-dated-changelog
base: main
test_command: "ruff check . && ruff format --check . && pytest -q"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-10-29
---

## Goal

`adamsuk/gh-factory`'s `.github/workflows/changelog.yml` is the **reusable**
workflow every enrolled repo (including this one, software-factory) calls as
a caller. It fails a pull request that does not update `CHANGELOG.md`, but
it does **not** check the form of the entry — the fix belongs in
`adamsuk/gh-factory`, not in any caller's `.github/workflows/changelog.yml`.

AGENTS.md in software-factory requires a **dated** entry:

> **Changelog:** if the repo keeps a `CHANGELOG.md`, add a dated entry
> (`## YYYY-MM-DD`, Europe/London date) in the same PR.

Twice on 2026-10-29 a pull request put its entry under `## [Unreleased]` and
the `changelog / changelog` check **passed** — software-factory#159 and
#161. Both were caught by review, not by the check.

So the check named after the changelog verifies that a file was touched,
not that the entry is usable. Make it verify the form, **in
`adamsuk/gh-factory`**.

## Acceptance criteria

- [ ] A pull request whose `CHANGELOG.md` diff adds **no** line matching
      `^## \d{4}-\d{2}-\d{2}( \(.*\))?$` **fails** the check. The optional
      `(topic)` suffix matters: software-factory's own `CHANGELOG.md` uses
      headings like `## 2026-10-27 (triage retry)`, and the regex must
      accept that form, not just a bare date
- [ ] A pull request that adds a correct dated heading (with or without a
      `(topic)` suffix) passes
- [ ] A pull request that adds only entries **under an existing** dated
      heading — the common case, and correct — also passes: accept an
      entry whose nearest preceding `##` heading in the PR's version of the
      file is a dated heading that already existed before this PR.
      Requiring the dated heading itself to be present in the diff is
      **wrong on its own**: adding a bullet to today's existing section is
      legitimate and must not be forced to duplicate the heading
- [ ] **Mixed entries, decided:** the check requires **at least one** added
      line to satisfy the rule above. It does not require every added
      heading in the diff to be valid — a PR that adds one valid dated
      entry and, say, an unrelated `## [Unreleased]` heading elsewhere
      still passes. The check's job is "did this PR add an acceptable
      changelog entry", not "is every heading in this diff well-formed".
      State this explicitly in a comment in the workflow, and cover it with
      a test
- [ ] The existing `skip-changelog` label still skips the whole check
- [ ] The failure message names the expected form, the way
      software-factory's `scripts/check-test-assertions.sh` does — not just
      "changelog check failed"
- [ ] **Date window:** a dated heading the PR itself *adds* must fall
      within 3 days before today through 1 day after today (Europe/London,
      inclusive) — enough tolerance for a PR that takes longer to land, not
      enough to let a stale heading copied from an old entry satisfy the
      check. The window does **not** apply to content added under a
      heading that already existed before this PR; that heading's age
      doesn't matter. Name the window in the failure message
- [ ] Tests cover: no entry, an entry with no dated heading, a new dated
      heading inside the window, a new dated heading outside the window (in
      both directions), an addition under an existing (old) dated heading,
      a `(topic)`-suffixed heading, the mixed-entry case above, and the
      skip label
- [ ] `ruff check . && ruff format --check . && pytest -q` all pass. **All
      three**: CI runs the formatter check too, and a work order that ran
      only `pytest` and `ruff check` cost a run on gh-factory#35
- [ ] `CHANGELOG.md` in `adamsuk/gh-factory` gains a dated entry in the form
      the top of that file describes

## Out of scope

- Bumping the pinned SHA in each enrolled repo's caller workflow. Those
  callers pin `adamsuk/gh-factory/.github/workflows/changelog.yml@<sha>`,
  so they keep the old behaviour until bumped. Note it in the pull request;
  it is a separate change across five repos
- Enforcing anything else about `CHANGELOG.md` content
- The dated-entry rule itself, which lives in software-factory's AGENTS.md

## Constraints

- `.github/workflows/**` is CI config, protected under AGENTS.md §5 — in
  `adamsuk/gh-factory`, same as any enrolled repo. Say so in the pull
  request and ask for Scott's review
- This is a reusable workflow consumed by five repos. A false failure
  blocks every one of them, so the "addition under an existing dated
  heading" case must work
- Do not change or remove an existing test assertion that predates this
  work order. A test added by an earlier attempt of this same ticket may be
  adjusted if the new acceptance criteria require it (say so in the PR) —
  that is not the same as touching an inherited assertion

## History

- **Attempt 1** (`892e09e`, adamsuk/gh-factory#37) implemented the form
  check. The independent reviewer escalated it: the original issue asked
  for a date window, and the first draft of this work order dropped it.
- **Attempt 2** (`d822f88`, same PR) adds the window, per Scott: "a couple
  of days... no more than that" — implemented as 3 days before through 1
  day after.
- This version of the work order folds in three findings CodeRabbit raised
  against the first draft of this document itself (not the code): name the
  target repo explicitly, account for the `(topic)` suffix format used
  elsewhere (including by software-factory's own `CHANGELOG.md`), and
  define the mixed-entry case. The first two are reflected in the
  acceptance criteria above, and the shipped code in adamsuk/gh-factory#37
  already satisfies them (the suffix form has its own passing test). The
  mixed-entry decision above is also already true of the shipped logic — it
  accepts the PR on the first added line that satisfies the rule, so one
  valid entry is sufficient regardless of other lines in the diff — but no
  test exercises that combination yet. Not reopening gh-factory#37 for it:
  low risk, and out of scope for what was asked. Worth a one-line test if
  this file is touched again.

## Issue text (untrusted)

> The changelog check passes entries that break the dated-entry rule
