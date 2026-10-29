---
repo: adamsuk/software-factory
issue: 171
issue_repo: adamsuk/software-factory
title: "feat: let a writable builder run in a clone of another repo"
branch: factory/171-work
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-station-run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-wait-for-review-bot.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-10-29
---

## Goal

Only the grok provider can build in a repo other than this one, so when Grok
Build's balance ran out on 2026-10-29 every cross-repo ticket became unbuildable:
#160, #157, #8, #114, #115, #116, #117, #118, #53, #54.

The cause is one line:

```bash
# scripts/station-run.sh:208
workdir="$here"
```

`$here` is this repo's root, and there is no option to change it. The adapters
already accept `--workdir` and `station-run.sh` already passes it — it just never
passes anything else for a writable role. `adapters/grok/run.sh` sidesteps this
by exec'ing `scripts/run-work-order.sh`, which clones the repo named in the work
order.

Let a **writable** builder run in a clone of the repo the work order names, so
claudecode and opencode can build cross-repo too.

## Approach

`station-run.sh` already clones for read-only roles (the `--read-only` sandbox).
Reuse that, writable, when the target repo is not this one. Decide the target
from the work order's `repo:` field, and keep running in place when it names this
repo.

## Acceptance criteria

- [ ] `station-run.sh` runs `builder` on claudecode or opencode against the repo
      named in the work order's `repo:` field, in a clone outside this checkout
- [ ] A work order whose `repo:` is `adamsuk/software-factory` still runs **in
      place**, exactly as today. This must not change in-repo behaviour
- [ ] **This repo's working tree is unchanged by a cross-repo run**, proven by a
      test, not asserted. The write boundary from #142 and #148 has to hold
- [ ] The clone can push: its `origin` push URL is the real remote. It must
      **not** inherit the `no-push://blocked-by-read-only-station` placeholder
      the read-only path installs, and the existing guard that rejects an
      inherited push URL must not fire on this path
- [ ] The run prints which directory it is working in, as the read-only path
      already does (`station-run: read-only clone of ... at ...`)
- [ ] The clone is cleaned up on exit, including on failure — `station-run.sh`
      installs `trap cleanup_station EXIT` before a sandbox can exist, and that
      ordering must be preserved
- [ ] `GH_REPO` is exported to the target repo for the adapter, so `gh` infers
      the right repo inside the clone
- [ ] `scripts/test-station-run.sh` covers: the in-repo path unchanged, the
      cross-repo clone, the untouched-working-tree assertion, and that the clone
      has a real push URL
- [ ] `stations/README.md`'s provider table is updated — cross-repo stops being
      grok-only
- [ ] `CHANGELOG.md` gains an entry under a `## YYYY-MM-DD` heading
      (Europe/London); `main` has a `## 2026-10-29` section, add to it rather
      than creating a second dated heading
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` exits 0

## Traps carried forward — read these before writing code

1. **Use a clone, not a worktree.** #142 learned this the hard way: a git
   worktree shares `.git/config`, so unsetting the sandbox's `origin` removed the
   **real repo's** remote. The read-only path uses
   `git clone --local --no-hardlinks` for that reason. A cross-repo clone comes
   from the remote anyway, but do not be tempted into a worktree.
2. **Do not reuse the no-push wiring.** The read-only path deliberately sets
   `remote set-url --push origin no-push://blocked-by-read-only-station` and then
   `die 7` if any push URL survives. A writable cross-repo clone needs the
   opposite, so the two paths must be clearly separated rather than sharing a
   flag.
3. **A `--writable` test once pushed a real commit.** During #142 a test with a
   fake provider that mutated the repo committed and pushed a `tamper` commit to
   a live branch. Any new test must be non-destructive: a reporting-only fake
   provider, and a checksum of the tree before and after.
4. `GIT_DIR`, `GIT_WORK_TREE` and friends are unset before cloning in the
   existing path for a reason — an exported `GIT_DIR` could otherwise reach the
   real repo. There is already a test for that; keep it passing.

## Out of scope

- **Refactoring `scripts/run-work-order.sh`.** It also does setup,
  `test_command`, the squash commit, the push, the pull request and the
  `factory:gate` label, and it is the only path that does any of that. Leave it
  alone; that asymmetry needs its own ticket.
- Making the non-grok builders push or open pull requests. After this lands they
  still only leave edits in the clone. Worth stating in the pull request so
  nobody reads this as full parity.
- Any adapter change. They already honour `--workdir`.

## Constraints

- `scripts/station-run.sh` is not a protected path, but
  `scripts/test-station-run.sh` is under `scripts/test-*.sh` (§5): **add**
  assertions, change none. Run `scripts/check-test-assertions.sh --base
  origin/main --head HEAD --label-present no` and confirm it exits 0; if it does
  not, say so rather than working around it.
- `tests` is a **required** check on this repo's ruleset now, so all twelve
  suites must stay green.
- Cloning a repo in a test must not hit the network. The existing tests clone
  the local repo with `--local`; follow that pattern and keep the cross-repo test
  offline by pointing it at a local fixture repo rather than GitHub.

## Issue text (untrusted)

> Only the grok provider can build in another repo, so its billing halts every cross-repo ticket

## Attempt 2 — the GIT_DIR unset is in the wrong place

CodeRabbit, Minor by its grading, but it is a **write-boundary** bug and should be
read as more than that. Verified against the code before passing it on.

```
282:    self_repo=$(git -C "$here" remote get-url origin 2>/dev/null ...)   # lookup
289:    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE ...                      # unset, after
```

An exported `GIT_DIR`, `GIT_WORK_TREE` or `GIT_COMMON_DIR` redirects that
`git remote get-url origin` call, so `self_repo` can come back as some other
repository. `self_repo` is what decides whether the station clones the target or
**runs in place against the real working tree**. Get it wrong and a cross-repo
work order edits this repo, which is precisely the boundary #142 and #148 exist
to hold.

Attempt 1's own work order listed this trap:

> `GIT_DIR`, `GIT_WORK_TREE` and friends are unset before cloning in the existing
> path for a reason — an exported `GIT_DIR` could otherwise reach the real repo.

The unset was added, just after the thing it needed to protect.

### Fix

Move the `unset` so it runs **before** the `origin` lookup, and before reading
the work order's front matter. The read-only path at line 230 already does this
in the right order; match it.

### Also add a test

`scripts/test-station-run.sh` already proves an exported `GIT_DIR` cannot reach
the real repo on the read-only path. Add the equivalent for this path: export a
`GIT_DIR` pointing at a different repository, run a **cross-repo** work order,
and assert that the decision and the clone are unaffected and this repo's tree is
untouched. Without that, the fix is a one-line move with nothing holding it in
place — and the trap was already named once and still missed.

### Unchanged

Everything else in attempt 1 stands. Keep the clone-not-worktree choice, the real
push URL, the checksum assertion on this repo's tree, the reporting-only fake
provider and the local fixture clone. `shellcheck` stays clean; add assertions
only, change none; confirm `scripts/check-test-assertions.sh --base origin/main
--head HEAD --label-present no` exits 0.

### Note for the builder

This work order edits `scripts/station-run.sh`, the script the station is
executing. That corrupted the tail of attempt 1's run and made its self-reported
test results untrusted (#174). Report what you changed and let the verification
happen in a fresh process; do not rely on a suite result produced after you have
rewritten that file.
