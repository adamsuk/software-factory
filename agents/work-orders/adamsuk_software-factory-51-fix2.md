---
repo: adamsuk/software-factory
issue: 51
issue_repo: adamsuk/software-factory
title: "fix: precise flag extraction in brief-drift-check.sh"
branch: factory/51-brief-drift-check
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-brief-drift-check.sh"
setup_command: ""
changelog: false
merge_allowed: false
review_bot: coderabbit
attempt: 3
created: 2026-10-30
---

## Goal

CodeRabbit's "full review" round on PR #187 found two still-valid, related
precision bugs in the flag-extraction half of `scripts/brief-drift-check.sh`
(the exit-code half and the label half are not affected). One finding from
an earlier round was already fixed and is confirmed addressed — don't touch
anything related to `stations/README.md` or label extraction.

## What to change, in `scripts/brief-drift-check.sh`

1. **Flags on a separate line are missed, and unrelated flags can leak in.**
   The current flag loop scans the *entire* "What the wrapper does" section
   for lines matching `run-work-order\.sh`, then extracts `--flag` tokens
   from those same lines. If a brief documents the command and its flag on
   separate lines (a valid layout), the flag is never seen. The section-wide
   scan can also pick up an unrelated flag mentioned elsewhere in the same
   section (e.g. a `--no-package-lock` setup-command option).

   Fix: extract the invocation block starting at the `run-work-order.sh`
   mention through its blank-line boundary first, then extract `--flag`
   tokens from *that block* only:

   ```diff
   +invocation=$(printf '%s\n' "$section" | sed -n '/run-work-order\.sh/,/^$/p')
   +
    while read -r flag; do
      [[ -n "$flag" ]] || continue
      if ! grep -qF -- "\"$flag\"" "$wrapper"; then
        report "agents/grok-build.md documents flag $flag but scripts/run-work-order.sh does not parse it"
      fi
   -done < <(printf '%s\n' "$section" | grep -E 'run-work-order\.sh' | grep -oE '\-\-[a-z][a-z0-9_-]*' | sort -u)
   +done < <(printf '%s\n' "$invocation" | grep -oE '\-\-[a-z][a-z0-9_-]*' | sort -u)
   ```

2. **Flag tokens get truncated.** The extraction pattern
   `\-\-[a-z][a-z-]*` stops at the first digit or underscore, so a
   documented flag like `--push2` (or anything with digits/underscores)
   would be extracted as `--push`, which the wrapper does parse — so an
   unsupported flag with a numeric/underscore suffix silently passes.
   Include digits and underscores in the token pattern.

## Tests to add/update in `scripts/test-brief-drift-check.sh`

- A fixture where the documented command and its flag are on separate
  lines, with an unsupported flag — confirm the fixed extraction still
  catches it (this would have passed silently before fix #1).
- A fixture with a flag like `--push2` (digits) that the wrapper doesn't
  parse — confirm it's still reported as drift, not truncated to the
  real `--push` and accepted.
- A matching underscore case (e.g. `--push_suffix`) is covered by the same
  pattern and acceptance criteria.
- Confirm non-vacuous: both new tests fail against the pre-fix script and
  pass against the fix.

## Out of scope

- The "match executable wrapper behavior, not arbitrary text" finding
  (commented-out code, `exit 4;` syntax) — already explicitly skipped in
  an earlier round as Heavy-lift/out of proportion; still out of scope.
- `stations/README.md` / label extraction — already fixed and confirmed
  addressed by CodeRabbit; don't touch.
- Anything in the exit-code half of the script.

## Acceptance criteria

- [ ] A brief with the command and flag on separate lines, naming an
      unsupported flag, is caught
- [ ] A documented flag containing digits or underscores that the wrapper
      doesn't parse is caught (not truncated to a supported prefix)
- [ ] All existing cases in `scripts/test-brief-drift-check.sh` still pass
- [ ] `shellcheck` stays clean

## Report back

No changelog entry needed (this PR's dated entry already covers #51; this
is a precision fix on a PR not yet merged). Confirm both new tests are
non-vacuous (fail pre-fix, pass post-fix).
