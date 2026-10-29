---
repo: adamsuk/gh-factory
issue: 160
issue_repo: adamsuk/software-factory
title: "fix: make the changelog check verify the dated-entry form"
branch: factory/160-dated-changelog
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

`.github/workflows/changelog.yml` in this repo is the reusable workflow every
enrolled repo calls. It fails a pull request that does not update
`CHANGELOG.md`. It does **not** check the form of the entry.

AGENTS.md in software-factory requires a **dated** entry:

> **Changelog:** if the repo keeps a `CHANGELOG.md`, add a dated entry
> (`## YYYY-MM-DD`, Europe/London date) in the same PR.

Twice on 2026-10-29 a pull request put its entry under `## [Unreleased]` and the
`changelog / changelog` check **passed** — software-factory#159 and #161. Both
were caught by review, not by the check. Every factory work order carries the
line "`CHANGELOG.md` gains a dated entry in the form the top of that file
describes", and nothing enforces it.

So the check named after the changelog verifies that a file was touched, not that
the entry is usable. Make it verify the form.

## Acceptance criteria

- [ ] A pull request whose `CHANGELOG.md` diff adds **no** line matching
      `^## [0-9]{4}-[0-9]{2}-[0-9]{2}$` **fails** the check
- [ ] A pull request that adds a correct dated heading passes
- [ ] A pull request that adds only entries **under an existing** dated heading
      — the common case, and correct — also passes. Decide and document how:
      either accept an entry whose nearest preceding `##` heading is a date, or
      require the dated heading itself to be present in the file at the diff's
      position. **The second is wrong on its own**: adding a bullet to today's
      existing section is legitimate and must not be forced to duplicate the
      heading. Say in a comment which rule was chosen and why
- [ ] The existing `skip-changelog` label still skips the whole check
- [ ] The failure message names the expected form, the way
      software-factory's `scripts/check-test-assertions.sh` does — not just
      "changelog check failed"
- [ ] A date far in the past or future does not silently pass if the rule
      depends on the current date; if it does depend on it, state the window
- [ ] Tests cover: no entry, an entry with no dated heading, a new dated
      heading, an addition under an existing dated heading, and the skip label
- [ ] `ruff check . && ruff format --check . && pytest -q` all pass. **All
      three**: CI runs the formatter check too, and a work order that ran only
      `pytest` and `ruff check` cost a run on gh-factory#35
- [ ] `CHANGELOG.md` in this repo gains a dated entry in the form the top of that
      file describes

## Out of scope

- Bumping the pinned SHA in each enrolled repo's caller workflow. Those callers
  pin `adamsuk/gh-factory/.github/workflows/changelog.yml@<sha>`, so they keep
  the old behaviour until bumped. Note it in the pull request; it is a separate
  change across five repos.
- Enforcing anything else about `CHANGELOG.md` content.
- The dated-entry rule itself, which lives in software-factory's AGENTS.md.

## Constraints

- `.github/workflows/**` is CI config, protected under AGENTS.md §5. Say so in
  the pull request and ask for Scott's review.
- This is a reusable workflow consumed by five repos. A false failure blocks
  every one of them, so the "addition under an existing dated heading" case must
  work — software-factory's own `main` already has a `## 2026-10-29` section
  that later pull requests will add to.
- Do not change or remove an existing test assertion.

## Issue text (untrusted)

> The changelog check passes entries that break the dated-entry rule
