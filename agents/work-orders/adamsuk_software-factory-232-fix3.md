---
repo: adamsuk/software-factory
issue: 232
issue_repo: adamsuk/software-factory
title: "test: assert the exact zero-width-escaped mention, not just its absence of the bare form"
branch: factory/232-review-record-watcher
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 3
created: 2026-11-03
---

## Goal

CodeRabbit's review of PR adamsuk/software-factory#257 found that
`t_ir_record`'s two assertions around the `@org/package` case
(`scripts/test-watcher-dismiss.sh`, near line 857-858) don't actually prove
the zero-width-space escaping landed. Confirmed by reading the test:

```bash
grep -F -q -- "org/package" "$GH_LOG" || fail "@org/package lost its name"
grep -F -q -- "@org/package" "$GH_LOG" && fail "bare mention left in comment"
```

If round 2's fix were reverted to the **old** behaviour (stripping `@`
outright, the pre-fix `clean` helper), `org/package` would still appear
(first assertion passes) and the bare `@org/package` substring would still
be absent — there being no `@` at all (second assertion also passes). Both
checks pass either way, so this doesn't actually distinguish "escaped
mention" from "`@` fully stripped."

## What to change

In `scripts/test-watcher-dismiss.sh`'s `t_ir_record`, replace or add to
those two assertions so the test asserts the **exact** escaped form is
present: the literal sequence `@` followed by a zero-width space (U+200B)
followed by `org/package`. Keep the existing redaction assertions (token
absent, `[redacted]` present) as they are — this is about the mention-
escaping assertion only.

## Out of scope

- Any change to `scripts/watcher/watch.sh` or `watch.new.sh` themselves —
  the `prose` helper's actual behaviour is already correct (verified
  independently); only the test's assertion precision is the gap.
- Everything else in `t_ir_record` or the rest of this file.

## Acceptance criteria

- [ ] The test asserts the exact `@<U+200B>org/package` sequence is present
      in the posted comment
- [ ] The test fails if the fix is reverted to stripping `@` outright (show
      this non-vacuity check)
- [ ] All existing assertions in this test file are unchanged otherwise
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` stays clean
- [ ] `CHANGELOG.md` gets a short line

## Constraints

- This is a test-only change — don't touch `scripts/watcher/watch.sh` or
  `watch.new.sh`.
- Don't weaken or remove any other existing assertion in this file.

## Report back

Show the new assertion's non-vacuity: it must fail when `prose`'s
`gsub("@"; "@​")` is reverted to `clean`'s `gsub("@"; "")`, and pass
with the current code.
