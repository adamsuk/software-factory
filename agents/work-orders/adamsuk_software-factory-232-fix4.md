---
repo: adamsuk/software-factory
issue: 232
issue_repo: adamsuk/software-factory
title: "fix: close four remaining gaps in the watcher's review-record comment"
branch: factory/232-review-record-watcher
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 4
created: 2026-11-03
---

## Goal

CodeRabbit's round-3 review of PR adamsuk/software-factory#257 found four
more real gaps, all confirmed by reading the code directly. Fix all four,
in **both** `scripts/watcher/watch.sh` and `scripts/watcher/watch.new.sh`
(identical change in each, same as every prior round).

1. **`redact()` misses non-GitHub token shapes (Major, security).**
   `redact()` only matches `gho_`/`ghp_`/`github_pat_`/`ghs_`. If
   `checks_ran` (CI output restated by the reviewer) contains an OpenAI-
   shaped `sk-...` key or an `xai-...` key (this codebase's own
   `XAI_API_KEY` is exactly that shape — see AGENTS.md §7), it reaches the
   posted comment unredacted.
2. **An empty string bypasses the "not available" fallback (Minor).**
   `(.agreed_behaviour // "not available")` only substitutes on
   `null`/`false` in jq — an empty string `""` is truthy, so a reviewer
   result with `agreed_behaviour: ""` renders as a blank line rather than
   `not available`.
3. **Truncation happens after mention-escaping, which can lose the field's
   last character (Minor).** `prose` does `gsub("@"; "@​") | .[0:600]`
   — escaping first means every `@` grows the string by one character
   before the 600-char slice, so a field that's exactly 600 characters and
   contains `@` loses content at the end that would otherwise fit.
4. **The full head SHA is posted as a bare string, which GitHub auto-links
   and visually shortens (Minor).** `"Head: " + $sha` is not wrapped in
   backticks, so GitHub's autolinking renders it as a short link
   (`abc1234`), not the 40-character text #232's acceptance criteria
   actually asked for.

## What to change

In **both** watcher files:

1. Extend `redact()`'s pattern to also match `sk-` and `xai-` prefixed
   tokens, keeping a `\b` word boundary so ordinary words like
   "risk-based" aren't touched. Follow CodeRabbit's suggested pattern:
   `|\bsk-[A-Za-z0-9_-]+|\bxai-[A-Za-z0-9_-]+` appended to the existing
   `sed -E` pattern.
2. In `ir_post_comment`'s `jq` pipeline, normalize empty or whitespace-only
   values for all four review-record fields to `"not available"` too —
   not just missing/null. (For example, test the field after the `//`
   substitution: if it's empty or all-whitespace, use `"not available"`
   instead.)
3. In `prose`, apply the `600`-character slice **before** escaping `@`
   mentions, not after — so truncation always operates on the original
   text's character positions, and the zero-width-space insertion never
   pushes real content past the cap.
4. Wrap the head SHA in backticks when rendering it: `"Head: `" + $sha +
   "`"` (or equivalent), so GitHub renders it as inline code and shows all
   40 characters instead of autolinking a shortened form.

## New/updated tests needed

In `scripts/test-watcher-dismiss.sh`'s `t_ir_record` (or new cases next to
it), for both watcher files:
- An `sk-`/`xai-`-shaped value in a field is redacted (not present
  verbatim in the posted comment), the same way the existing `ghp_` case
  works. Also keep a check that an ordinary word like `risk-based` stays
  intact (not swallowed by the new pattern).
- A field with an explicit empty string (`""`) renders as `not available`
  in the posted comment, not a blank line.
- A 600-character field value containing a trailing `@` near the end
  keeps all 600 of its original characters' worth of content (check the
  test proves the order-of-operations fix, not just that *a* fix exists).
- The posted comment's `Head:` line wraps the full SHA in backticks
  (update the existing full-SHA assertion to check for the backtick-
  wrapped form specifically, not just the raw substring, since GitHub's
  rendering is what #232 actually cares about).

Each new/updated case must be non-vacuous: show it failing against this
PR's current head and passing after the fix.

## Out of scope

- Everything else already correct from rounds 1-3.
- Any further restructuring of `ir_post_comment` beyond these four
  targeted fixes.

## Acceptance criteria

- [ ] `redact()` also catches `sk-` and `xai-` shaped tokens, in both
      watcher files, without breaking ordinary hyphenated words
- [ ] An empty-string field value renders as `not available`, not blank
- [ ] `prose`'s 600-character cap is applied before `@` escaping, not after
- [ ] The posted comment's full head SHA is backtick-wrapped (inline code),
      so GitHub doesn't autolink/shorten it
- [ ] New tests prove all four, non-vacuously, for both watcher files
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` stays clean
- [ ] `CHANGELOG.md` gets a line for this round

## Constraints

- Keep both watcher files byte-identical in their diff.
- Don't touch any existing assertion — only add new ones.
- Don't touch `redact()`'s existing GitHub-token patterns, only extend them.

## Report back

For each of the four fixes, show the specific new assertion failing
against the pre-fix code and passing after.
