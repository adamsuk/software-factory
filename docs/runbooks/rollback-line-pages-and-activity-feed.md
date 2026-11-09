# Rollback: line Pages and the activity-feed worker

Use this runbook to roll back the live `adamsuk/line` GitHub Pages site or the `activity-feed` Cloudflare Worker. Run the commands yourself. This file does not deploy anything, and it does not record a drill that has not happened.

## line Pages

`.github/workflows/pages.yml` in `adamsuk/line` builds on pull request and deploys only on push to `main` and `workflow_dispatch`, using environment `github-pages` (branch policy and required reviewers) and `actions/deploy-pages`. The concurrency group for non-PR runs is `pages-deploy` with `cancel-in-progress: false`, so a later push waits.

Roll the site back in this order.

1. List push runs and pick the known-good run:

   ```sh
   gh run list --repo adamsuk/line --workflow pages.yml --event push --limit 20
   ```

2. Cancel every queued, waiting, or in-progress push run newer than the known-good run. Repeat for each newer run:

   ```sh
   gh run cancel --repo adamsuk/line <run-id>
   ```

3. Redeploy that known-good commit:

   ```sh
   gh run rerun --repo adamsuk/line <run-id>
   ```

   A rerun uses that run's commit. `workflow_dispatch` on current `main` does not roll back.

4. Approve the `github-pages` environment when the deploy job waits.

5. Confirm https://adamsuk.github.io/line/ shows "Last updated" with the known-good 7-character SHA. That SHA links at `https://github.com/adamsuk/line/commit/<sha>`.

If `main` still contains the bad commit, revert `main` with a normal PR. The next push deploys again. No force-push.

Clearing a waiting Pages run (cancel, or reject the environment review) is Scott's step and is recorded on issue 309, not in this PR.

## activity-feed worker

`.github/workflows/deploy.yml` in `adamsuk/activity-feed` runs on push to `main`, environment `production` (required reviewers), tests, then `cloudflare/wrangler-action`. The concurrency group `production` does not cancel in progress. The Worker name is `activity-feed` (`name` in `wrangler.toml`).

Immediate rollback is from a checkout of that repo, using the Cloudflare credential Scott already has. Use the interactive command, or pass a version id:

```sh
npx wrangler rollback
npx wrangler rollback <version-id>
```

Dashboard alternative: Workers & Pages → `activity-feed` → Deployments → Rollback.

A rollback serves that version at 100%. It does not revert KV data (binding `FEED`). It can only target the last 100 published versions. It fails if a bound resource was deleted.

Cancel queued or in-progress Deploy runs of the bad commit before or right after, or the next push publishes it again:

```sh
gh run list --repo adamsuk/activity-feed --workflow deploy.yml --event push --limit 20
gh run cancel --repo adamsuk/activity-feed <run-id>
```

Confirm the dashboard shows the chosen version as active, and that the worker's existing public `/feed.json` returns JSON with `updatedAt`. Do not add a route.

Durable fix: revert the bad commit on `main` with a PR before another push.

## Practise log

Scott fills a row only after he runs that drill. Leave Date, Outcome and Operator empty until then.

| System | Date | Outcome | Operator |
| --- | --- | --- | --- |
| line Pages | | | |
| activity-feed worker | | | |
