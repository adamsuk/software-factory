---
repo: adamsuk/software-factory
issue: 174
issue_repo: adamsuk/software-factory
title: "fix: re-exec station-run.sh from a snapshot so self-edits can't corrupt a run"
branch: factory/174-reexec-snapshot
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

bash reads a script incrementally, not all at once. When a builder station
rewrites the very script that's executing it (`station-run.sh`, an adapter
under `adapters/*/run.sh`, or anything else on the execution path), the
running process re-reads the file at a stale byte offset after the edit
and can execute a fragment as a command. Observed firsthand, twice, this
same evening — once while building #171 (`station-run.sh:283`) and again
building #136 (`station-run.sh:312`/`:313`). Both times the error went to
stderr mid-run, the process exited 0, and the only way to trust the
run's self-reported test results was to re-measure them from a fresh,
separate process afterward.

This affects any ticket that touches `scripts/station-run.sh`,
`scripts/run-work-order.sh`, `scripts/station-post.sh`,
`scripts/gate-issue.sh`, or an adapter under `adapters/*/run.sh` — a
large share of the factory's own backlog.

## Fix: re-exec from a snapshot (recommended in the issue), with a guard

1. At the very start of `station-run.sh`, before anything else can read
   from the working tree it might later edit, copy the whole execution
   path it depends on — itself, the adapters directory, `AGENTS.md`,
   `agents/roles/`, `stations/github-writes.md` (whatever it currently
   reads to run) — to a temp directory, and **re-exec itself from that
   copy** (`exec bash "$snapshot/station-run.sh" "$@"` or equivalent).
   From that point on, nothing a builder writes to the real working tree
   can reach the running process, because it isn't reading from there
   anymore.
2. Checksum the snapshotted scripts at the start of the run and compare
   again at the end (or rely on the fact that a snapshot literally cannot
   change — pick whichever is simpler and still satisfies the acceptance
   criteria below). If anything about the execution path the run depends
   on changed in the *real* working tree during the run (which a snapshot
   makes irrelevant to correctness, but is still worth surfacing), say so
   in the run's output rather than staying silent.
3. The exit trap (`cleanup_station`) must still run and still clean up
   whatever it's supposed to clean up, now that the running process is
   the re-exec'd copy, not the original invocation.
4. `#136` changed `station-run.sh` to read `AGENTS.md`/`agents/roles/*.md`
   from a promoted release tag by default, not the live working tree —
   read that change first. It already closes part of this gap for those
   specific files; this ticket is about the *script* doing the reading,
   which still runs from the working tree (or the clone #171/#177 made)
   and is still vulnerable to being rewritten mid-run.

## Out of scope (do not do these in this attempt)

- Option 3 from the issue (refuse to build any ticket touching these
  scripts) — explicitly rejected in the issue. The factory must be able
  to change its own scripts
- Rewriting `run-work-order.sh`'s own clone/exec model (it already clones
  before running, per #154/#171) — this ticket is about `station-run.sh`
  and the adapters it directly invokes

## Acceptance criteria

- [ ] A station run is unaffected by an edit to `scripts/station-run.sh`
      or the adapter it is using, made *during* the run — proven by a
      test that deliberately rewrites the script mid-run and checks the
      run still completes correctly
- [ ] The sandbox/cleanup trap still runs in that case
- [ ] If the execution path's source changed during a run, the run says
      so plainly in its output (not just silent exit 0)
- [ ] `stations/README.md` records the hazard and the fix
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` and
      `bash scripts/test-station-run.sh` pass, run from a **fresh process
      that did not itself edit `station-run.sh`** — if you edit this file
      while building this ticket, your own in-flight bash process reads it
      incrementally too (the exact bug you're fixing), so a self-test
      immediately after editing is not trustworthy. Commit, then verify
      from a separate, fresh invocation — exactly the same discipline
      #171 and #177 already required
- [ ] `CHANGELOG.md` gains a dated entry

## Report back

In the PR body: how the snapshot/re-exec works concretely, how cleanup
still runs after the re-exec, and confirmation the verification ran from
a fresh process, not the one that made the edit.
