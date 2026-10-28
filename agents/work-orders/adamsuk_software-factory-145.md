---
repo: adamsuk/software-factory
issue: 145
issue_repo: adamsuk/software-factory
title: "feat: drive the factory from the board"
branch: factory/145-board-workflow
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-28
---

## Goal

Make the board the place Scott works: every ticket on it, and a flag he can set
there that queues work without starting it.

Scott's calls on 2026-10-28:

- Flag with a label, not a board field, so labels stay the source of truth and
  the sync stays one-way.
- No daemon. Pickup happens when he asks.

## Acceptance criteria

- [ ] `board-sync.sh` adds every open issue and pull request whatever its
      last-updated date, in a pass separate from the status mirror
- [ ] The `factory status` mirror keeps its 2-day window
- [ ] No GNU-only `date -d` in the date call. Note this does not make the
      script portable on its own: it needs bash 4+ for `declare -A` and
      `${w^}`, so macOS's `/bin/bash` 3.2 cannot run it. Documented, not fixed.
- [ ] `scripts/factory-flagged.sh` lists `priority: next` issues ordered
      P0-P3 then issue number, with priority, factory status and title
- [ ] It exits 0 with a plain message when nothing is flagged
- [ ] `scripts/test-factory-flagged.sh` covers ordering, the empty case, and
      that the script only reads
- [ ] `README.md` documents the board workflow and the `project` scope it needs
- [ ] The `priority: next` row no longer says "the one" ticket

## Likely files

- scripts/watcher/board-sync.sh
- scripts/factory-flagged.sh
- scripts/test-factory-flagged.sh
- README.md
- CHANGELOG.md

## Out of scope

- Any board-to-label reverse sync
- An unattended watcher or `/loop` for pickup

## Known untested

`board-sync.sh` cannot be exercised here: `gh project` needs the `project`
scope and the current token has `gist, read:org, repo, workflow`. The membership
pass and the portable date are reviewed by reading, not by running. Scott must
run `gh auth refresh -s project` before either can be verified.

## Issue text (untrusted)

> Drive the factory from the board: sync every ticket, and flag pickup with
> priority: next
