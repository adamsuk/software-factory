---
repo: adamsuk/software-factory
issue: 232
issue_repo: adamsuk/software-factory
title: "fix: carry the four review-record fields and full head SHA in the watcher's review comment"
branch: factory/232-review-record-watcher
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-watcher-dismiss.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-03
---

## Goal

`agents/roles/reviewer.md` step 7 defines a "four-field record" every
independent review must write for the head it reviewed: **agreed
behaviour**, **checks that ran**, **behaviour nobody asked for**, and
**blast radius**. The brief already says plainly: "`scripts/watcher` does
not record these four fields today" and "does not record agreed behaviour,
the checks that ran, behaviour nobody asked for, or blast radius today."
The watcher's own comment also only shows the **short** (7-char) head SHA
in its human-readable text; the full 40-char SHA is only inside the HTML
marker comment, not visible to a reader.

`scripts/watcher/watch.sh` and `scripts/watcher/watch.new.sh` are two
separate, nearly-identical files (confirm with `diff`, they drift slightly
in line numbers but the functions below are the same shape in both). **Make
the same change in both.**

## What to change

In each of `scripts/watcher/watch.sh` and `scripts/watcher/watch.new.sh`:

1. **`step_independent_review`'s JSON schema** (the `schema=` line just
   before the Grok prompt is built): add four new required string fields
   to the schema, matching reviewer.md's names: `agreed_behaviour`,
   `checks_ran`, `unasked_behaviour`, `blast_radius`. Keep the existing
   five (`verdict`, `summary`, `fix`, `dismissed`, `escalate`) as they are.
2. **The prompt text** built in the same function (the `printf` lines
   above `write_untrusted_block`): add an instruction asking for these four
   fields, with reviewer.md's own descriptions so the model knows what
   each means:
   - `agreed_behaviour`: what this head was supposed to do, from the
     acceptance criteria and the work order.
   - `checks_ran`: the checks that ran on this head, and what they
     reported.
   - `unasked_behaviour`: behaviour in this head the acceptance criteria
     do not ask for. Literally `"none"` when there is none.
   - `blast_radius`: what else this head can change or break.
3. **`ir_save_result`**: store the four new fields from the structured
   output (or the parsed fallback paths) into the saved JSON, the same way
   `summary` is handled. Every fallback branch that builds a result object
   without structured output (the `VERDICT:`-line-only fallback, and the
   "output was missing or not parseable" fallback) needs the four fields
   too, with a safe placeholder value (for example `"not available"`) so
   `ir_post_comment` never fails on a missing key.
4. **`ir_post_comment`**: render the four fields after the existing
   summary line, in the same list style as the Fix/CodeRabbit/Needs-a-
   person sections (a short heading then the value, or "none" literally for
   `unasked_behaviour` when that's what was recorded). Also change the
   visible verdict line so it states the **full** head SHA (`$sha`), not
   just `$sha[0:7]` — keep the short SHA too if that reads better, but the
   full SHA must appear as plain visible text, not only inside the `<!--
   factory:independent-review v2 sha=... -->` marker.
5. **A new test** (pick the existing watcher test file this behaviour best
   fits — check `scripts/test-watcher-dismiss.sh` and any other
   `scripts/test-watcher-*.sh` first; add a new `scripts/test-watcher-*.sh`
   file only if none fits) using a **fake result JSON file** (no real `gh`,
   no network): assert the posted comment body contains all four new
   fields' content and the full head SHA, and that nothing resembling a
   secret appears in the comment text. Follow this codebase's existing
   fake-`gh`/fixture style (see `scripts/test-ruleset-drift-check.sh` for
   the pattern of a fake binary + fixture file, even though that's a
   different script).

## Out of scope

- The station-run reviewer path (`agents/roles/reviewer.md` step 7's own
  `--summary` field to `scripts/station-post.sh verdict`) — already does
  this; this issue is the watcher path only.
- Changing the `<!-- factory:review -->` comment's `verdict:`/`should-
  fix:`/`nits:` lines — untouched, per reviewer.md.
- Anything about `ir_build_pack` or the review prompt's judgment criteria
  beyond adding the four new fields.

## Acceptance criteria

- [ ] The independent-review comment includes all four review-record
      fields (`agreed_behaviour`, `checks_ran`, `unasked_behaviour`,
      `blast_radius`), rendered with readable labels
- [ ] The comment includes the full 40-character head SHA as visible text
- [ ] Both `scripts/watcher/watch.sh` and `scripts/watcher/watch.new.sh`
      get the same change
- [ ] A new test, using a fake result file (no real `gh`/network), checks
      the comment body for all four fields and prints no secret
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` stays clean
- [ ] `CHANGELOG.md` has a dated entry

## Constraints

- Do not touch anything in `agents/roles/**` (already correct and
  protected) or `scripts/station-post.sh` (the station-run path, unrelated
  to this issue).
- `scripts/watcher/watch.sh` and `.new.sh` are not in the protected-paths
  list (not CI config, not `agents/**`), but they are large, careful files
  — keep the diff minimal and mirrored between the two files.

## Issue text (untrusted)

> The Line audit of 2026-11-03 (`review-record`, quick win) found the
> watcher's independent-review comment, posted by `ir_post_comment` in the
> watcher, does not carry the four review-record fields or the full head
> SHA. The reviewer brief says the station-run path must; the watcher path
> does not.
>
> Extend `ir_post_comment` so the posted comment includes the four review-
> record fields defined in the reviewer brief and the full 40-character
> head SHA it reviewed.

## Report back

Confirm both watcher files got the identical change, show the new test's
non-vacuity (fails without the fix, passes with it), and quote the exact
field names used so they can be checked against reviewer.md's prose.
