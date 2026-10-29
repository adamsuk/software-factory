---
repo: adamsuk/software-factory
issue: 177
issue_repo: adamsuk/software-factory
title: "fix: stop deleting a writable cross-repo builder's clone on exit"
branch: factory/177-preserve-writable-clone
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-station-run.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-29
---

## Goal

`scripts/station-run.sh`'s exit trap `cleanup_station` (around line 210)
does `[[ -z "$sandbox" ]] || rm -rf "$sandbox"`. Two different code paths
set `$sandbox`: the **read-only** clone (around line 233, `/tmp/station-ro-*`)
and the **writable cross-repo** clone added by #171 (around line 293,
`/tmp/station-xr-*`). They share one variable, so the trap deletes both —
destroying a writable builder's committed work the instant the process
exits, before any wrapper can read, test, push, or open a PR against it.

Proven today: running this path for real against software-factory#160 and
#8 committed verified fixes in the clone, then lost them completely on exit.
Not a corner case — `scripts/test-station-run.sh` has a test that asserts
the deletion as correct ("the cross-repo clone is removed on exit", around
line 245). That test needs to change, deliberately, because this is a
protected path (an existing assertion, AGENTS.md §5) — say so in the PR.

## What to change

- Use two separate variables for the two sandboxes (e.g. `ro_sandbox` for
  the read-only path, `xr_sandbox` for the writable cross-repo path), not
  one shared `$sandbox`.
- `cleanup_station` deletes `$ro_sandbox` only. It must never delete
  `$xr_sandbox`.
- After the adapter returns successfully on the writable cross-repo path,
  print the clone's path on its own final stdout line, in a fixed, grep-able
  format a wrapper can parse without guessing (for example
  `station-run: writable-clone-path <path>` — pick a form, but make it
  distinct from the existing human-readable progress line at that point,
  which goes to stderr).
- The writable clone is **not** deleted by `station-run.sh` on any exit path
  (success or failure) — whoever reads the path is responsible for deleting
  it once done. Say this in a one-line comment at the point the path is
  printed, so the next reader doesn't "fix" it back.
- Update the test named "the cross-repo clone is removed on exit" to assert
  the new behaviour (the clone still exists, and its path appears on
  stdout in the agreed format). Keep the read-only equivalent test
  ("the sandbox is cleaned up") asserting deletion, unchanged.

## Out of scope (do not do these in this attempt)

- Anything about who commits/pushes/opens the PR from the clone — that's
  the next ticket, not this one. This ticket only needs the clone to
  survive and be locatable.
- The read-only path's behaviour — don't touch it beyond not sharing its
  variable.
- `run-work-order.sh` / the grok path — untouched, it does its own clone
  management already.

## Acceptance criteria

- [ ] A writable cross-repo builder's clone still exists on disk, with the
      committed work intact, after `station-run.sh` exits 0
- [ ] A read-only station's clone is still deleted on exit (no regression —
      keep the existing test passing, don't weaken it)
- [ ] The writable clone's path is printed on stdout in a fixed format a
      script can parse
- [ ] The "removed on exit" test is changed to match, and the PR says so
      explicitly as a protected-path change requiring Scott's review
- [ ] A new test proves the writable clone survives and its path is both
      printed and present after a **fresh process** runs `station-run.sh`
      for that path
- [ ] `shellcheck` and the full `scripts/test-station-run.sh` pass, verified
      by a process that did not itself edit `station-run.sh` — if you edit
      this file, your own in-flight `bash` process reads it incrementally,
      so a self-test immediately after editing is not trustworthy. Commit,
      then verify from a separate, fresh invocation.

## Report back

In the PR body: the exact stdout line format chosen, confirmation the
read-only path's test still passes unchanged, and which existing assertion
you changed and why (for Scott's §5 review).
