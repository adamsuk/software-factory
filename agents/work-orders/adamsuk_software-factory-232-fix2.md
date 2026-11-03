---
repo: adamsuk/software-factory
issue: 232
issue_repo: adamsuk/software-factory
title: "fix: redact and preserve the review-record fields in the watcher's posted comment"
branch: factory/232-review-record-watcher
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-11-03
---

## Goal

CodeRabbit's review of PR adamsuk/software-factory#257 found a real,
Major-severity security gap in round 1's change: `ir_post_comment` builds
its body with `jq`'s `clean` helper (strips newlines, strips `@`,
truncates to 300 chars) but never calls the existing `redact()` function
(defined once near the top of each watcher file, already used for log
lines at a couple of call sites — confirm with `grep -n redact
scripts/watcher/watch.sh`). The new `checks_ran` field can carry raw CI
check output, which can itself contain a leaked credential (e.g. a token
printed by a misbehaving check). That text would reach the PR comment
unredacted. Confirmed by reading the code directly: `comment_pr` posts
`$body` straight to `gh pr comment`, no redaction anywhere in this path.

A second, lower-severity (Minor) finding on the same lines: `clean`
deletes every `@` character outright (so `@org/package` in a field's value
silently becomes `org/package`, changing its meaning) and truncates at 300
characters, which may be too short for these four fields specifically
(they're meant to carry a real, if brief, account of behaviour — not a
one-line list item like `fix`/`dismissed`/`escalate`).

## What to change

In **both** `scripts/watcher/watch.sh` and `scripts/watcher/watch.new.sh`
(apply the identical change to each, same as round 1):

1. **Security (must fix):** pass the fully-assembled `body` through
   `redact` before it reaches `comment_pr`, in `ir_post_comment`. Follow
   CodeRabbit's suggested shape:
   ```bash
   body=$(printf '%s' "$body" | redact) || return 1
   ```
   placed right after the `jq` pipeline that builds `body`, before the
   `comment_pr` call.
2. **Field preservation (worth fixing alongside, same function):** for the
   four review-record fields specifically (`agreed_behaviour`,
   `checks_ran`, `unasked_behaviour`, `blast_radius`), stop stripping `@`
   outright — escape a mention instead (for example insert a zero-width
   space after `@`, or similar, so `@org/package` reads correctly without
   pinging anyone on GitHub) and raise or drop the 300-character truncation
   for just these four fields (they're a short prose account, not a list
   item — judge a sensible cap, e.g. 600 characters, and say what you
   picked). Leave the existing `clean` helper's behaviour (and the
   300-char cap) untouched for `summary`, `fix`, `dismissed`, and
   `escalate` — those are unaffected by this finding.

## New/updated tests needed

In `scripts/test-watcher-dismiss.sh`'s `t_ir_record` (or a new case next
to it): prove a `checks_ran` value containing something that looks like a
real token (e.g. `ghp_` followed by 36 alphanumeric characters, matching
`redact`'s own pattern) is **not** present verbatim in the posted comment
— it should show `[redacted]` instead. Also prove a value containing
`@org/package` still reads sensibly in the posted comment (not silently
turned into `org/package`). Non-vacuous: both cases must fail against
round 1's code and pass after this fix.

## Out of scope

- Any change to `redact()` itself, or to its two existing log-line call
  sites.
- The `<!-- factory:review -->` station-run verdict path
  (`scripts/station-post.sh`) — unaffected, uses its own `--summary`
  argument, not this watcher code.
- Everything else already correct in round 1.

## Acceptance criteria

- [ ] `ir_post_comment`'s assembled body is passed through `redact` before
      posting, in both watcher files
- [ ] A `checks_ran` value containing a token-shaped string is redacted in
      the posted comment (new test, non-vacuous)
- [ ] The four review-record fields no longer silently drop `@`
      characters, and get a more generous (stated) character cap than 300
- [ ] `summary`, `fix`, `dismissed`, `escalate` behaviour is unchanged
- [ ] All existing `test-watcher-dismiss.sh` cases for both watcher files
      still pass (where runnable on this box — the known pre-existing
      `flock` gap on unrelated cases is not this PR's concern)
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` stays clean
- [ ] `CHANGELOG.md` gets a line noting the redaction fix

## Constraints

- Keep both watcher files byte-identical in their diff (confirm with
  `diff` the same way round 1 did).
- Don't touch any existing assertion in `scripts/test-watcher-dismiss.sh`
  — only add new ones.

## Report back

Show the new test(s) failing against round 1's code and passing after the
fix. State the exact character cap chosen for the four fields and why.
