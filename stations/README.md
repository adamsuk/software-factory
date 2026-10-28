# Stations

Stations are provider-agnostic implementations of factory roles. The canonical definitions live in `agents/roles/*.md` and are composed with `AGENTS.md` by `scripts/station-run.sh`.

## Architecture

1. **Canonical prompts** (`AGENTS.md`, `agents/roles/*.md`) - Provider-agnostic rules and role definitions
2. **Station runner** (`scripts/station-run.sh`) - Composes prompts and delegates to adapters
3. **Adapters** (`adapters/*/`) - Translate to provider-specific CLIs/APIs
4. **Orchestration** (`scripts/foreman-orchestrate.sh`) - Starts a station. It does not pick an issue or merge.
5. **GitHub trail** (`scripts/station-post.sh`, `stations/github-writes.md`) - The comment and the single `factory:*` label a person sees on the issue. Every provider uses it. The Grok watcher keeps its own poster.

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
