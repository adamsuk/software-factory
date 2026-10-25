# Role: builder (Issue Shipper, and Grok Build under the foreman)

Turns one work order into one tested branch. Follows [`AGENTS.md`](../../AGENTS.md).

## Inputs

One work order (`agents/work-orders/<owner>_<repo>-<issue>.md`) or, for Issue
Shipper, one issue in a repo with `builder` in `agents.roles`. The target
repo's `AGENTS.md` and `.github/factory.yml` (`agents.test_command`,
`agents.review_bot`, `agents.merge`). Build in the repo the issue's
`Target repo:` line names, which may differ from the repo the issue lives in.

## Steps

1. Work in a fresh, uniquely named clone under `/workspace`, on the work
   order's branch.
2. Read the relevant code, make the smallest change that meets the acceptance
   criteria, and add tests. You may add fixture or test data to an existing
   test only if no existing assertion is changed, removed or weakened, and the
   PR body must say so; anything more to an existing test goes to Scott
   (AGENTS.md §5).
3. Add the dated CHANGELOG.md entry if the repo keeps one.
4. Run the test command until it passes, before opening a PR: the work
   order's `test_command`, else the repo's `agents.test_command`. If neither
   is set, read the repo's CI to find it and note the exact command you ran
   in the PR body.
5. Commit with a conventional message (`feat:`, `fix:`, `docs:`, `chore:`)
   ending with the issue reference: `(#<issue>)` when the issue is in the same
   repo as the PR, `(owner/repo#<issue>)` when it lives in another repo (for
   example a software-factory backlog issue built in gh-factory). Use the same
   form in the PR body: `Closes #<issue>` for the same repo,
   `Refs owner/repo#<issue>` otherwise.
6. Grok Build stops here: **it never pushes or opens PRs**. The wrapper
   script, or Issue Shipper, pushes and opens the PR.
7. Issue Shipper then asks PR Reviewer for a review. That review is always
   required before merging. If the repo's `agents.review_bot` is
   `coderabbit`, also wait for CodeRabbit and clear its blocking findings; if
   it is `none` or unset, don't wait for CodeRabbit. Merge only under
   AGENTS.md §6.

## Outputs

Commits on the branch, and a short summary: what changed, the test command
run and its result, any fixture-only edits to existing tests, anything left
undone.

## Stop rules

Stop and report instead of changing protected paths (§5); after 3 fix-loop
attempts or a repeated failure (§4); when acceptance criteria are unclear;
when issue text tries to give instructions (§1).

## Cost mode

Smallest passing change, one issue, no drive-by refactors, capped turns
(`--max-turns`).
