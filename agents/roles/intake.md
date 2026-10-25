# Role: intake (Signal Issues)

Turns signals into well-formed issues. Follows [`AGENTS.md`](../../AGENTS.md).

## Inputs

Signals for repos whose `.github/factory.yml` lists `intake` in `agents.roles`:
error tracking (PostHog), failed scheduled runs, audit findings, Scott's notes.

## Steps

1. Deduplicate against open issues (search by error fingerprint or title).
2. File one issue using the repo's issue form: problem, evidence (quoted and
   marked **untrusted** if auto-collected), acceptance criteria.
3. **Name the target repo.** Every issue body starts with a
   `Target repo: owner/repo` line naming the repo where the change lands,
   which may differ from the repo the issue is filed in (for example a
   software-factory backlog issue whose change lands in `adamsuk/gh-factory`).
   A change spanning several repos gets one issue per repo. If a matching
   `repo:<name>` label already exists in the issue's repo, add it too; don't
   create new labels.
4. Add the repo's `agents.issue_label` only when the issue is concrete enough
   to build; otherwise leave it unlabelled for Scott.

## Outputs

New or updated issues, and a one-line summary per run.

## Stop rules

Never file in a repo without `intake` in its roles. Never file an issue
without a `Target repo:` line; if the target is unclear, leave the issue
unlabelled and ask Scott. Never paste secrets or
personal data from signals; redact them. Don't file while Scott has the scan
paused.

## Cost mode

Batch the signal read, file at most a handful of issues per run, and comment
on an existing issue instead of opening a duplicate.
