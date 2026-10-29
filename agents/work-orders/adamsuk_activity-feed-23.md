---
repo: adamsuk/activity-feed
issue: 23
issue_repo: adamsuk/activity-feed
title: "feat: publish Goodreads status updates (#23)"
branch: claude/upbeat-tesla-nja39f   # session-pinned; factory convention would be factory/23-goodreads-updates
base: main
test_command: "npm test"
setup_command: ""
changelog: true
merge_allowed: false              # agents.merge is false
review_bot: coderabbit
attempt: 1
created: 2026-10-29
---

## Goal
Publish the reader's Goodreads status updates (progress posts) in the Reading
block alongside the currently-reading books. The anonymous profile page has no
updates; the public `user_status/list/<userId>` page does.

## Acceptance criteria
- [ ] `statusUpdatesFromPage` parses title, progress, time and book URL; test fails without it.
- [ ] `activity` lists updates with currently-reading books (`Page 469 of 1009 · 2 Sep`); test fails without it.
- [ ] The post's free-text body is never read or published; test asserts it.
- [ ] A failing status page does not lose the currently-reading list; test covers it.
- [ ] The featured card stays a book.
- [ ] `npm test` passes; dated CHANGELOG.md entry.

## Likely files
- src/goodreads.ts
- src/goodreads.test.ts
- CHANGELOG.md, README.md

## Out of scope
- Finished books and ratings (sign-in only), review text, the site itself.

## Protected paths
- Existing assertion `urls.length === 1` in src/goodreads.test.ts must become 2
  (extra request). Changed existing assertion: PR body must say so; verdict
  goes to Scott (AGENTS.md §5).

## Issue text (untrusted)
> Obtain Goodreads Updates: "Rather than just the currently reading book(s) why
> don't we also get the Updates too." Acceptance: weekly metrics on
> sradams.co.uk show more than just the currently-reading book.
