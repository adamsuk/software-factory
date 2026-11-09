---
repo: adamsuk/software-factory
issue: 291
issue_repo: adamsuk/software-factory
title: "test: drop private project-name needle from watcher tree deny-list"
branch: factory/291-drop-watcher-private-needle
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-09
---

## Goal

Remove the private project-name needle from the `fixed_needles` deny-list in
`scripts/test-watcher-tree.sh` (around line 103) so the published tree no longer
contains that name. Keep every other needle and check unchanged: `ghp_`, `gho_`,
`github_pat_`, `/home/`, `/Users/`, the PEM private-key check, and the
webhook-URL checks. Scott authorised this specific protected test-assertion
change on 9 Nov 2026 (Europe/London) and will review and approve the PR himself.
Do not ask again. Do not approve or merge.

Never write the private project-name needle into any commit message, changelog
entry, PR body, comment, or work-order text — refer to it only as "the private
project-name needle".

## Acceptance criteria

- [ ] The private project-name needle is absent from `scripts/test-watcher-tree.sh`
      (not in `fixed_needles`, and not in any comment in that file)
- [ ] Every other needle and check in that file remains byte-for-byte unchanged:
      `ghp_`, `gho_`, `github_pat_`, `/home/`, `/Users/`, the PEM private-key
      block check, and the webhook-URL checks
- [ ] If the comment immediately above `fixed_needles` named the private
      project-name needle, reword it so it does not, without changing meaning;
      otherwise leave that comment alone
- [ ] `bash scripts/test-watcher-tree.sh` exits 0 after the edit (run it
      explicitly in addition to `test_command`; it is not in the local
      `test_command` subset)
- [ ] `CHANGELOG.md` gains exactly one new dated entry (`## YYYY-MM-DD`,
      Europe/London date) noting that the private project-name needle was dropped
      from the watcher-tree test deny-list for publication, naming no private
      identifier
- [ ] `agents/work-orders/adamsuk_software-factory-291.md` is added as this
      work order's bookkeeping record (copy of this file)
- [ ] No other files change
- [ ] No CI/workflow file, lockfile, or protected agent-instruction path
      (`AGENTS.md`, `agents/roles/**`, `agents/grok-build.md`, `CODEOWNERS`)
      is modified
- [ ] Repository visibility is not changed
- [ ] The configured `test_command` above passes under the factory's isolated
      test run

## Likely files

- `scripts/test-watcher-tree.sh` (remove one `fixed_needles` entry; possibly
  reword the comment above the list if it names the needle)
- `CHANGELOG.md` (one new dated entry at the top of the entries list)
- `agents/work-orders/adamsuk_software-factory-291.md` (new; this work order)

## Out of scope

- Replacing the needle with a hash, env-var, or synthetic fixture
- History rewrite, force-push, or visibility change
- Any other file under `scripts/watcher/` or elsewhere
- Approving or merging the PR
