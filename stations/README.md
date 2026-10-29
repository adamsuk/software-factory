# Stations

Stations are provider-agnostic implementations of factory roles. The canonical definitions live in `agents/roles/*.md` and are composed with `AGENTS.md` by `scripts/station-run.sh`.

## Architecture

1. **Canonical prompts** (`AGENTS.md`, `agents/roles/*.md`) - Provider-agnostic rules and role definitions
2. **Station runner** (`scripts/station-run.sh`) - Composes prompts and delegates to adapters
3. **Adapters** (`adapters/*/`) - Translate to provider-specific CLIs/APIs
4. **Orchestration** (`scripts/foreman-orchestrate.sh`) - Starts a station. It does not pick an issue or merge.
5. **GitHub trail** (`scripts/station-post.sh`, `stations/github-writes.md`) - The comment and the single `factory:*` label a person sees on the issue. Every provider uses it. The Grok watcher keeps its own poster.

## Which providers can run which roles

Every adapter takes the same composed bundle, but the `builder` role is not one
thing across providers, and treating it as one has cost two wrong conclusions
(#154, #158).

| Provider | Non-builder roles | `builder` | What the builder actually does |
| --- | --- | --- | --- |
| `grok` | yes | yes | `adapters/grok/run.sh` execs `scripts/run-work-order.sh`: clones to the bench root, runs `setup_command` and `test_command`, squash-commits, pushes, opens the pull request and sets `factory:gate` |
| `opencode` | yes | yes | runs the prompt against the working tree. No clone, no test run, no commit, no pull request, no label |
| `claudecode` | yes | yes (since #158) | as `opencode`. Model is `${FACTORY_MODEL:-sonnet}`, builder included |

So "the bench ran" means two different things. On `grok` it means the full
station. On `opencode` and `claudecode` it means the edits exist in the tree and
every step after the build is still owed. Do not report a station as complete on
the strength of a provider that cannot complete it.

The grok builder clones into the bench root — `$FACTORY_WORKSPACE`, default
`/workspace`, with a loud fallback when that is unusable (#154). The other two
edit the checkout in place, so `scripts/station-run.sh`'s read-only/writable
decision is the only thing standing between a reading role and the real repo.

Until #158, `claudecode` refused `builder` outright, on the stated grounds that
builder requires `run-work-order.sh`. That was false — `run-work-order.sh` is
reached only from the grok adapter — and it meant the one role that writes code
had a single provider with no fallback.

## Which roles may write

A station that reads must not be able to write. On 2026-10-28 the reviewer
station edited five files and staged them, including an existing test
assertion, because its brief said "post only through `scripts/station-post.sh`"
and nothing enforced it (#142).

| Role | Changes the repo? | How |
| --- | --- | --- |
| `intake` | no | `--read-only` |
| `research` | no | `--read-only` |
| `reviewer` | no | `--read-only`, set by `foreman-orchestrate.sh review` |
| `monitor` | no | `--read-only`; its scripts are read-only already |
| `foreman` | **yes** | writes the work order to `agents/work-orders/` (`agents/roles/foreman.md` step 3), so it runs in the repo |
| `builder` | **yes** | changes the files a work order asks for; `--read-only` is refused for it |

`scripts/station-run.sh` runs the reading roles — `intake`, `research`,
`reviewer`, `monitor` — in a throwaway `git clone` under `/tmp`, and deletes it
afterwards. That is the default, not an opt-in: `--writable` is the deliberate
way out. Only committed state is copied, so a station sees the head commit, not
the caller's uncommitted changes.

The clone keeps `origin`'s fetch URL and has its **push** URL broken. Keeping
the fetch URL is deliberate: removing the remote blinded the reviewer, because
`gh` infers the repository from it, so inside the sandbox it could not read the
pull request, its checks, or CodeRabbit's comments — the things §10.4 asks it to
review against. It reviewed the local diff instead and said so (#149).

A station given `--repo` also gets `GH_REPO` set to it, so an unqualified `gh`
read inside the sandbox cannot fall back to this checkout's `origin` and inspect
the wrong repository.

A global `remote.origin.pushurl` would survive into the clone alongside the
blocked one — `pushurl` is multi-valued, so git would push to both. The station
checks the effective push URLs after setting the blocked one and refuses to run
if any other remains, naming it.

**What this does and does not stop.** It moves the working directory and breaks
the clone's push URL, so an agent writing relative paths has its edits thrown
away and a plain `git push` fails. It is not a guarantee that nothing can be
pushed: an agent that supplies a URL, or that writes into the original checkout
by absolute path and pushes from there, still can. It does **not** deny access to the original checkout: the
providers run with blanket approval (`claude --permission-mode
bypassPermissions`, `opencode --auto`), and `station-run.sh` puts the work
order's absolute path in the prompt, so a determined or careless agent can still
write to the real repository by absolute path. CodeRabbit raised this on PR #143
and it is right.

Calling it a boundary therefore overstates it. It is a default working directory
plus a missing remote — enough for the failure actually seen (#141, an agent
editing files under its cwd), not enough against an agent that addresses the
checkout directly. A real boundary needs OS-level isolation: a container, or a
filesystem namespace where the original tree is unreadable. That is the sandbox
finding (#44), and it is not done.

A clone and not a linked worktree on purpose: a worktree shares `.git/config`
with the real repository, so removing the worktree's `origin` removes the
repository's own remote. That happened while building #142.

CodeRabbit is held off by `.coderabbit.yaml`, which disables `autofix`,
`fix_ci`, `unit_tests` and `docstrings`. Its **autopilot** is not covered: that
feature has no key in CodeRabbit's config schema, and its Autofix checkbox
still appeared on PR #143 after CodeRabbit had read the new config. Turning it
off is a dashboard setting (#142).

This is the filesystem half only. The agent still runs with the caller's `gh`
credentials, so it could still write through the API — comment, label, or
merge. Closing that needs a scoped token the agent owns (#7, #44). Until then
the API side rests on the brief, not on a control.

## 05 Review waits for the review bot first

`foreman-orchestrate.sh review` runs `scripts/wait-for-review-bot.sh` before the
reviewer role, because §10.4 has the independent review weigh CodeRabbit's
comments and it cannot do that if CodeRabbit has not finished.

It had not been waiting. Across #141, #143 and #146 CodeRabbit left **16 inline
findings** and no verdict read any of them; four were real, and one had broken
the pull request it was reviewing.

The wait is satisfied when the bot has posted a review **or** a review comment
written against that exact commit. Both are checked, because neither is
sufficient alone — on #149 CodeRabbit left a review record on `79632eb` with no
comments.

The two use different fields, which matters. GitHub **re-anchors** a review
comment when the diff moves under it, rewriting `commit_id` to a newer commit
while `original_commit_id` keeps the one it was written against. Every comment
on #149 reporting `commit_id` `a8ca777` had originated on an older head, and
`/reviews` had no record for `a8ca777` at all — so matching `commit_id` ended
the wait on a head the bot had never seen, the exact failure this exists to
prevent. Comments are matched on `original_commit_id`; reviews on `commit_id`.

The bot's check is only a secondary signal, and only when the requested commit
is the pull request's current head: `gh pr checks` always reports the head, so a
terminal check says nothing about an older commit. The check alone is a poor
proxy anyway — CodeRabbit sits `pending` for many minutes while already posting
findings, and auto-pauses to `skipping` after enough commits, which never
becomes terminal.

A timeout is not fatal. The review still runs, and the reviewer says what it
could and could not see. After §10.2's threshold the wait posts
`@coderabbitai full review` once per head, never twice.

`agents.review_bot: none` skips the wait entirely. A missing `factory.yml` is an
error rather than a silent skip — defaulting to `none` there once made the script
look like it was waiting while doing nothing.

## Design Principles

- **Capability-based**: Roles describe what needs to be done, not how (no provider-specific tool calls)
- **Script-first for heavy operations**: Use existing `scripts/run-work-order.sh`, `scripts/gate-issue.sh` rather than reimplementing
- **Untrusted input**: All external content treated as data per AGENTS.md §1
- **Label-driven state machine**: GitHub labels are source of truth (AGENTS.md §9)
- **Provider swappable**: Change `FACTORY_PROVIDER` or adapter without modifying roles

## Usage

```bash
# Run a station directly
FACTORY_PROVIDER=opencode ./scripts/station-run.sh intake issue-context.md

# Dry run to inspect composed prompt
./scripts/station-run.sh --dry-run builder work-order-context.md

# Orchestrated flow. Options may come before or after the action.
./scripts/foreman-orchestrate.sh pick --provider opencode
```

What you see on the issue is whatever `scripts/station-post.sh` posted.
A run that only talks in its own transcript is not a finished station.
