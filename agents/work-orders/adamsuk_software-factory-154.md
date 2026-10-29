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
attempt: 4
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

## Attempt 2 — review findings to fix

Attempt 1 passed `test_command` but has three defects. Fix only these; do not
rewrite what works.

1. **Dead code in `choose_clone_root`.** This block does nothing and must be
   removed outright, not filled in:

   ```bash
   if [[ -e "$root" && (! -w "$root" || ! -x "$root") ]]; then
     :
   fi
   ```

2. **`bench-clone-dir-uses-helper` is environment-dependent and will fail on any
   box that has a usable `/workspace`.** This assertion is the problem:

   ```bash
   [[ "$dir_test" != /workspace/* ]] || fail "clone dir should not be under /workspace by default in this env"
   ```

   A test must assert the same thing everywhere. Set `FACTORY_WORKSPACE` to a
   known writable directory for that case and assert the clone dir is under it,
   then unset it. Keep the naming and "not inside the repo" assertions.

3. **`choose_clone_dir`'s failure message blames the wrong thing.** When
   `choose_clone_root` returned a usable root and only `mktemp` failed, the
   message still says `clone root unusable: $root`. Say that creating the clone
   directory under that root failed, and keep the root in the message.

Also add, in the same pass:

4. **`bench-clone-root-main-no-literal-workspace` only asserts the absence of
   the literal.** Add an assertion that `main` actually calls `choose_clone_dir`,
   so deleting the call does not pass the suite.

Do not change or remove any existing assertion, including the ones added in
attempt 1 — only the one named in item 2, which is being corrected, and
additions. Re-run `test_command` and leave it green.

## Attempt 3 — provider changed to claudecode/sonnet

Attempt 1 (opencode) produced the working fix now committed on this branch and
passed `test_command`. Attempt 2 (opencode) ran 15 minutes and produced a
byte-identical diff — no change at all — so the three review findings below are
still outstanding. #158 removed the claudecode builder refusal (merged as
`60778d5`), so this attempt runs on claudecode with `FACTORY_MODEL=sonnet`.

The branch already contains attempt 1's work. **Do not rewrite it.** Fix only
these, then leave `test_command` green.

1. **Remove the dead block in `choose_clone_root`.** It does nothing and must be
   deleted, not filled in:

   ```bash
   if [[ -e "$root" && (! -w "$root" || ! -x "$root") ]]; then
     :
   fi
   ```

2. **`bench-clone-dir-uses-helper` is environment-dependent** and fails on any
   box that has a usable `/workspace`. This line is the problem:

   ```bash
   [[ "$dir_test" != /workspace/* ]] || fail "clone dir should not be under /workspace by default in this env"
   ```

   A test must assert the same thing everywhere. Set `FACTORY_WORKSPACE` to a
   known writable directory for that case and assert the clone dir is under it,
   then unset it. Keep the naming and "not inside the repo" assertions.

3. **`choose_clone_dir`'s failure message blames the wrong thing.** When
   `choose_clone_root` returned a usable root and only `mktemp` failed, it still
   says `clone root unusable: $root`. Say that creating the clone directory under
   that root failed, and keep the root in the message.

4. **Add an assertion that `main` calls `choose_clone_dir`**, so deleting the
   call does not pass the suite. `bench-clone-root-main-no-literal-workspace`
   only checks that the literal `/workspace` is absent.

Constraints unchanged from above. In particular: item 2 corrects an assertion
added in attempt 1, which is permitted; do not touch any other existing
assertion in any `scripts/test-*.sh`, or `scripts/check-test-assertions.sh` will
fail the pull request. `shellcheck` 0.11.0 is now installed on the box, so run
`shellcheck scripts/*.sh adapters/*/run.sh` before finishing.

## Attempt 4 — two review findings, both verified

Attempt 3's work is correct and stays. Checks on the head are green, so AGENTS.md
§4's three-attempt cap does not apply: it governs the fix loop "when required
checks go red". These are review findings on a green head.

Both come from CodeRabbit on `d25d94a` and both were verified against the code
before being passed on.

1. **Major — resolve the bench root to an absolute path.** `mktemp -d` returns a
   relative path when given a relative template:

   ```
   $ mktemp -d reltest/wo-XXXXXX
   reltest/wo-bkjuCV
   ```

   So a relative `FACTORY_WORKSPACE` yields a relative `$dir`. `main` then does
   `cd "$dir"`, and *after* that uses `--cwd "$dir"` and `> "$dir.grok.json"`,
   which resolve against the new working directory and point somewhere wrong.
   The bench would clone and then fail, or write its run log outside the place
   every other step looks for it.

   Make the chosen root absolute before the clone directory is created, so both
   the default and an override are absolute. Cover it with a case that sets a
   **relative** `FACTORY_WORKSPACE` and asserts the returned directory is
   absolute.

2. **Minor — the changelog entry is in the wrong section.** It sits under
   `## [Unreleased]` at line 48. AGENTS.md:47 requires a dated
   `## YYYY-MM-DD` (Europe/London) entry in the same pull request. `main`
   already has a `## 2026-10-29` section with a `### Fixed` heading; move the
   entry's existing content there, unchanged, and do not create a second dated
   heading.

   Note the `changelog / changelog` check passed on this pull request regardless.
   That check only verifies the file was touched — see #160. Do not rely on it.

Constraints unchanged. Keep `test_command` green and `shellcheck scripts/*.sh
adapters/*/run.sh` clean. Change no assertion that exists on `main`.
