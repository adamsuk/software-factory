---
repo: adamsuk/software-factory
issue: 154
issue_repo: adamsuk/software-factory
title: "fix: let the bench clone somewhere that exists"
branch: factory/154-bench-workspace
base: main
test_command: "bash scripts/test-run-work-order.sh && bash scripts/test-station-run.sh && bash scripts/test-check-test-assertions.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-29
---

## Goal

`scripts/run-work-order.sh:496` hardcodes its clone root:

```bash
dir=$(mktemp -d "/workspace/wo-${repo/\//_}-$issue-XXXXXX")
```

`/workspace` does not exist on the factory box and cannot be created — `/` is a
read-only volume on this macOS. Every grok-provider builder run dies there
before cloning, so station 03 Bench has never executed on this machine.

Make the clone root configurable, with a loud fallback, so the bench runs.

## Acceptance criteria

- [ ] `FACTORY_WORKSPACE` chooses the bench clone root; unset keeps `/workspace`
      as the default, so the documented setup is unchanged
- [ ] A root that does not exist but can be created is created and used
- [ ] A root that cannot be created or is not writable falls back to a temporary
      directory, and the run **says on stderr** which root it fell back from and
      which it is using. A relocated bench run must never be silent: the paths in
      the run log have to match where the work happened
- [ ] When neither the root nor a temporary directory is usable, the script fails
      with its own message naming the root, not `mktemp`'s
- [ ] The clone root stays outside the real repo and outside the checkout:
      `$dir.grok.json`, `$dir.bench.txt` and `$dir.venv` are written beside it
- [ ] The script's header comment documents the exit code used for an unusable
      root
- [ ] `scripts/test-run-work-order.sh` gains cases for: the default root, an
      explicit override, a root that gets created, a non-writable root falling
      back, and a regression guard that `main` calls the helper and no longer
      contains the literal `/workspace`
- [ ] `stations/README.md` and `agents/grok-build.md` say where the bench clones
      and how to move it
- [ ] `CHANGELOG.md` gains a dated entry in the form the top of that file describes

## Likely files

- `scripts/run-work-order.sh`
- `scripts/test-run-work-order.sh`
- `stations/README.md`
- `agents/grok-build.md`
- `CHANGELOG.md`

## Out of scope

- Changing where the bench clones **by default**. `/workspace` stays the default;
  this adds an override and a fallback, it does not relocate the documented setup.
- The provider split that hid this bug: `run-work-order.sh` is reachable only
  from `adapters/grok/run.sh`, while the opencode adapter edits the working tree
  in place. Worth a ticket, not this one.
- #135, which is blocked behind this and resumes at 03 once this lands.

## Constraints

- Do not change or remove any existing assertion in any `scripts/test-*.sh`.
  Only add. `scripts/check-test-assertions.sh` fails the pull request otherwise
  (AGENTS.md §5).
- `shellcheck` is **not installed on this box**, so it is not in `test_command`
  and cannot be verified locally. Keep the script shellcheck-clean by eye; CI's
  ShellCheck job is the authority and must pass before review.
- `scripts/test-run-work-order.sh` sources `run-work-order.sh`, so the new helper
  must be a plain function that is safe to source with no side effects.

## Issue text (untrusted)

> Station 03 Bench has never run: run-work-order.sh hardcodes /workspace
