# Rollback: GitHub Pages and Cloudflare Workers

Use this runbook to roll back a live GitHub Pages site or a Cloudflare Worker in any repository that deploys that way. Run the commands yourself. This file does not deploy anything, and it does not record a drill that has not happened.

Set `$OWNER` and `$REPO` to the target repository (`$OWNER/$REPO`). Read the other placeholders from that repository, as each section describes. No force-push.

## GitHub Pages

Find the deploy workflow, the environment and the concurrency group in the target repository.

- The workflow file is the file under `.github/workflows/` that deploys with `actions/deploy-pages`. Call that file `$PAGES_WORKFLOW`.
- The environment is the `environment:` name on the deploy job. Call it `$PAGES_ENVIRONMENT`. Read that environment for its branch policy and required reviewers.
- The concurrency group is the `concurrency` value on non-pull-request runs. Note whether `cancel-in-progress` is true or false. When it is false, a later push waits behind the in-progress deploy.

Read the workflow `on:` block for the events that deploy. A common pattern is to build on `pull_request` and deploy only on `push` to `main` and on `workflow_dispatch`. Follow the events this repository actually uses.

Roll the site back in this order.

1. List `push` and `workflow_dispatch` runs and pick the known-good run. Listing only `--event push` hides `workflow_dispatch` runs, and those runs deploy too:

   ```sh
   gh run list --repo "$OWNER/$REPO" --workflow "$PAGES_WORKFLOW" --event push --limit 20
   gh run list --repo "$OWNER/$REPO" --workflow "$PAGES_WORKFLOW" --event workflow_dispatch --limit 20
   ```

2. Cancel every queued, waiting, or in-progress run of either event that is newer than the known-good run. Repeat for each newer run:

   ```sh
   gh run cancel --repo "$OWNER/$REPO" <run-id>
   ```

3. Redeploy that known-good commit by re-running the whole run. Do not pass `--job` or `--failed`, so the build job recreates the Pages artifact.

   ```sh
   gh run rerun --repo "$OWNER/$REPO" <run-id>
   ```

   GitHub allows a re-run only up to 30 days after the initial run. A rerun uses that run's commit. `workflow_dispatch` on current `main` does not roll back. When the known-good run is older than 30 days, skip the re-run and revert `main` with a normal pull request, as below.

4. Approve `$PAGES_ENVIRONMENT` when the deploy job waits.

5. Confirm the live site shows the known-good SHA when the site is built to show the commit it came from. Use the public URL the operator already has. A short SHA or a last-updated marker on that page should be the known-good 7-character SHA, which is `https://github.com/$OWNER/$REPO/commit/<sha>`.

If `main` still contains the bad commit, revert `main` with a normal pull request. The next push deploys again. No force-push. Use the same revert when the known-good run is older than 30 days.

Clearing a waiting Pages run (cancel, or reject the environment review) is the maintainer's step.

## Cloudflare Worker

Find the deploy workflow, the environment, the concurrency group and the Worker name in the target repository.

- The workflow file is the file under `.github/workflows/` that deploys the Worker (a `cloudflare/wrangler-action` step, or a step that runs Wrangler). Call it `$WORKER_WORKFLOW`.
- The environment is the `environment:` name on the deploy job. Call it `$WORKER_ENVIRONMENT`. Read it for required reviewers.
- The concurrency group is the `concurrency` value on that workflow. Note whether `cancel-in-progress` is true or false. When it is false, a later run waits.
- The Worker name is the `name` field in the Wrangler config (`wrangler.toml`, `wrangler.json`, or `wrangler.jsonc`). Call it `$WORKER_NAME`.

Immediate rollback is from a checkout of `$OWNER/$REPO`, using the Cloudflare credential the maintainer already has. Prefer the pinned Wrangler when the repository documents one (a dependency version, or the version in the deploy workflow). This runbook does not document a pin. Otherwise `npx wrangler` may install the latest Wrangler. Use the interactive command, or pass a version id:

```sh
npx wrangler rollback
npx wrangler rollback <version-id>
```

Dashboard alternative: Workers & Pages → `$WORKER_NAME` → Deployments → Rollback.

A rollback serves that version at 100%. It does not revert bindings or KV data. It can only target the last 100 published versions. It fails if a bound resource was deleted.

Cancel queued, waiting, or in-progress deploy runs of the bad commit before or right after the rollback, so the next push does not publish it again. List `push` and `workflow_dispatch`. Listing only `--event push` hides `workflow_dispatch` runs, and a `workflow_dispatch` run deploys when the workflow includes that event:

```sh
gh run list --repo "$OWNER/$REPO" --workflow "$WORKER_WORKFLOW" --event push --limit 20
gh run list --repo "$OWNER/$REPO" --workflow "$WORKER_WORKFLOW" --event workflow_dispatch --limit 20
gh run cancel --repo "$OWNER/$REPO" <run-id>
```

Confirm the dashboard shows the chosen version as active. Confirm the Worker's public URL the operator already has returns the known-good response. Do not add a route.

Approve `$WORKER_ENVIRONMENT` when a later deploy job waits.

Durable fix: revert the bad commit on `main` with a normal pull request before another push. No force-push.

## Practise log

The maintainer fills a row only after running that drill. Leave Date, Outcome and Operator empty until then.

| Approach | Date | Outcome | Operator |
| --- | --- | --- | --- |
| GitHub Pages | 2026-11-11 | Practised on `adamsuk/line`. Cancelled the two waiting deploy runs (queue cleared 08:55 UTC), reran known-good run `41638961238` (`371d2ff`), approved `github-pages`, deploy succeeded (08:57 UTC). Restored main `bb1a7a1` by rerunning `42776879128` (08:59 UTC). Live site content not checked. | adamsuk |
| Cloudflare Worker | | | |
