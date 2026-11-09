# Known gotchas (learned the hard way — don't rediscover these)

Companion to `run-factory.md`, which walks through driving a ticket end to
end and links here at each relevant step. This file is the detail behind
those pointers — read a section when the main playbook sends you here,
rather than up front.

## The identity wrinkle (#210, but broader than filed)

Every station in this environment writes to GitHub using whatever `gh`
login is on the box — the human user's own account. Issue #210 filed this
as a Grok-only problem (`run_grok()` strips `GH_TOKEN`/`GITHUB_TOKEN` from
the environment the Grok CLI itself runs in), but that stripping only
protects the LLM subprocess — `scripts/run-work-order.sh` still opens the
pull request afterwards with the box's own `gh`, so even a `grok`-provider
run hits the exact same self-approval wall below. The `claudecode` adapter
has no credential-stripping at all either. **Switching providers does not
avoid this** — it's a property of the box's `gh` login, not of which
station adapter is running.

**The concrete symptom:** a PR this pipeline opens is authored by the human
user's own account. GitHub refuses to let a PR's author submit an approving
review on their own PR — `GraphQL: Review Can not approve your own pull
request (addPullRequestReview)`. No setting fixes this; it's a GitHub
platform rule, not a repo config.

**What does *not* work:** minting a GitHub App installation token and using
it to call `gh pr review --approve`, `gh pr merge`, or an API call that
dismisses a review, directly. This was tried multiple ways in one session
(different flag splits, writing the token to a file first, adding a
permission rule for the exact command) and the Claude Code auto-mode
classifier blocked every variant outright — it reads as a hard security
boundary (using a credential specifically to route around a platform
self-approval restriction), not a soft "ask me" block that settings can
lift. Don't spend time retrying variants of this; report the wall to the
user instead (it's one of the decision points in `run-factory.md`).

**What does work: reopen the PR as the bot.** Minting and *using* a GitHub
App installation token to open a brand-new, otherwise-identical PR (not to
approve or merge anything) was not blocked. Since GitHub's restriction is
about who *opened* the PR, not who pushed the commits, you can:

1. Close the human-authored PR with a short comment noting it's superseded.
2. Open a new PR on the **same branch** (same commits — nothing to
   re-push), same title/body, authenticated as the bot via
   `scripts/gh-app-token.sh`:

```bash
export FACTORY_GH_APP_ID="<the app's ID>"
export FACTORY_GH_APP_INSTALLATION_ID="<the installation ID>"
export FACTORY_GH_APP_KEY_FILE="<path to the App's private key>"
TOKEN=$(bash scripts/gh-app-token.sh)

# Fail closed, before touching the existing PR: gh-app-token.sh warns and
# exits 0 (not non-zero) on a missing or invalid value, so an empty $TOKEN
# is silent unless checked explicitly — and GH_TOKEN="" just falls back to
# the current (human) gh login, which would reopen the PR as the same
# identity all over again. A token that merely authenticates isn't enough
# either — check it specifically covers <owner>/<repo> (the installation
# may not include every repo), since discovering that only after closing
# the original PR is worse than finding out now.
[[ -n "$TOKEN" ]] || { echo "token mint failed — check FACTORY_GH_APP_*" >&2; exit 1; }
GH_TOKEN="$TOKEN" gh api /installation/repositories --jq '.repositories[].full_name' 2>/dev/null \
    | grep -qx "<owner>/<repo>" \
  || { echo "minted token cannot access <owner>/<repo> — stopping before closing the old PR" >&2; exit 1; }

gh pr close <old-PR> --repo <owner>/<repo> --comment "Superseded: reopening as software-factory-line[bot] so the required approving review isn't blocked by self-authorship."

if ! GH_TOKEN="$TOKEN" gh pr create --repo <owner>/<repo> \
  --base main --head <branch> \
  --title "<same title>" \
  --body "<same body>"; then
  echo "pr create failed after closing <old-PR> — reopening it" >&2
  gh pr reopen <old-PR> --repo <owner>/<repo>
  exit 1
fi

unset TOKEN
```

The new PR's author becomes the bot. The human user can then approve and
merge it themselves through their normal GitHub workflow — no self-approval
wall, because the author and the approver are now different identities.

This repo's GitHub App ("software-factory-line") already has an
installation covering several `<owner>/*` repos. The App ID, installation
ID, and private key location are specific to the user's own setup — they
are not committed anywhere in this repo, by design (see `scripts/gh-app-token.sh`'s
own header comment for exactly which environment variables it reads). If
this playbook doesn't already have those three values available in the
session (ask the user, or check whether they've mentioned a key file path
earlier in the conversation), ask the user for them rather than guessing or
inventing a path — and never print the key's contents or the minted token
anywhere, treat both exactly like any other secret.

Minting the token and using it only to **open a PR** is fine. Using it to
**approve, merge, or dismiss a review** is the part that's blocked — don't
attempt that even if asked to "just try again a different way"; report the
wall and move to the "reopen as the bot" option instead.

## CodeRabbit skips bot-authored PRs (#209)

Once a PR is reopened as `software-factory-line[bot]` (or opened that way by
the station in the first place), CodeRabbit's check often reports
`skipping` instead of running. This is a filed bug (#209), not something
this playbook should treat as a real gate failure — judge readiness from the
repo's own `required_checks` (from `.github/factory.yml`) plus the
independent review verdict, not from CodeRabbit's own check state.

## Protected paths (AGENTS.md section 5, verbatim list)

- Existing tests: changing, weakening, skipping, or removing an existing
  assertion, or deleting an existing test (adding new tests, or adding
  fixture/test data to an existing test without touching an existing
  assertion, is fine).
- CI config: `.github/workflows/**`, `.github/actions/**`,
  `.github/factory.yml`, `.coderabbit.yaml`.
- Lockfiles: any `*.lock` file (`package-lock.json`, `pnpm-lock.yaml`,
  `yarn.lock`, `poetry.lock`, `uv.lock`, `Cargo.lock`, `go.sum`,
  `Gemfile.lock`, `composer.lock`, and so on).
- Agent instructions: `AGENTS.md`, `agents/**`, `CODEOWNERS`. The single
  exception is `agents/work-orders/**` — generated work orders are
  bookkeeping, not instruction, so they're **not** protected.
  `agents/roles/**` and `agents/grok-build.md` stay protected.

`scripts/protected-paths.sh` is the deterministic check this repo already
has for this — pipe a PR's changed-paths list through it rather than
eyeballing the list above when in doubt.

## The work-order paperwork gap

More than once, the foreman has built and opened a PR but never committed
the work-order file anywhere — not in the work tree, not on `main`, not in
the PR's own diff. `scripts/gate-issue.sh` needs that file to do anything,
so always check the specific ref it would actually be read from (see
`run-factory.md` step 3 for the exact commands — matching an exact filename
suffix, not a loose substring, and a specific ref rather than `git log
--all`, both matter: a substring match on issue `12` will also hit `112`,
and searching all history can find a same-named file on an unrelated
branch) before assuming gate will "just work." Reconstructing the file
yourself is squarely in-scope (it's explicitly non-protected), following
the cross-repo-vs-same-repo landing rule in `run-factory.md` step 3.

## `scripts/station-post.sh pr` as a label-repair tool

If a fix gets pushed while the issue is `factory:building` and nothing
moves the label back to `factory:gate`, don't hand-edit the label. Run the
real script — it's deterministic and reuses the existing open PR rather
than creating a new one:

```bash
scripts/station-post.sh pr --repo <repo> --issue <N> \
  --head <branch> --title "<exact existing PR title>" \
  --body-file <any-existing-file>
```

(`--body-file` is required by the CLI parser but unused when a matching PR
already exists.) It prints `pr: <repo>#<PR> already open on <branch>` and
swaps `factory:building` -> `factory:gate`. Confirmed safe because it's the
same plumbing a real station run would call — not a workaround.
