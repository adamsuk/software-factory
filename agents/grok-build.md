# Running Grok Build headless for a work order

Grok Build is xAI's terminal coding agent, the `grok` CLI. The foreman runs it
headless (`grok -p` / `--prompt-file`) on one work order at a time, through
[`scripts/run-work-order.sh`](../scripts/run-work-order.sh).

Checked against Grok Build **1.0.70** on 2026-10-25, using:

- [Overview](https://docs.x.ai/build/overview) (read 2026-10-25)
- [CLI reference](https://docs.x.ai/build/cli/reference) (read 2026-10-25)
- [Headless & Scripting](https://docs.x.ai/build/cli/headless-scripting) (read 2026-10-25)
- [Enterprise deployments](https://docs.x.ai/build/enterprise) (API key for CI, read 2026-10-25)
- The user guide that ships with the CLI in `~/.grok/docs/user-guide/`
  (`14-headless-mode.md`, `02-authentication.md`, `12-project-rules.md`,
  `18-sandbox.md`, `22-permissions-and-safety.md`), version 1.0.70, and
  `grok --help`.

## Install and authenticate (the operator, once per computer)

```sh
curl -fsSL https://x.ai/cli/install.sh | bash   # installs ~/.grok/bin/grok, links ~/.local/bin/grok
grok --version
grok login --device-auth                         # SuperGrok account, no browser needed on the box
# or, for unattended runs: export XAI_API_KEY=...  (from console.x.ai; never commit or print it)
```

Credentials live in `~/.grok/auth.json` (owner-only). A stored session token
wins over `XAI_API_KEY`. `grok models` prints "You are not authenticated." when
neither is present, which is a read-only way to check. Agents never run
`grok login` themselves.

## The command

```sh
grok --no-auto-update \
  --cwd "$CLONE" \
  --trust \
  --prompt-file "$WORK_ORDER" \
  --rules "$(cat AGENTS.md)" \
  --output-format json \
  --max-turns 60 \
  --always-approve \
  --sandbox workspace \
  --deny 'Bash(git push*)' --deny 'Bash(gh *)' \
  --disable-web-search \
  > "$CLONE.grok.json"
```

| Flag | Why | Source |
| --- | --- | --- |
| `--prompt-file <PATH>` | Headless single-turn prompt from a file (same as `-p`, which takes the text inline) | Headless & Scripting; `grok --help` |
| `--cwd <PATH>` | Run in the fresh clone; Grok finds the project root by walking up to `.git` | CLI reference; headless guide "Project Root Discovery" |
| `--trust` | Loads the **target repo's** own `AGENTS.md` and project skills. Headless startup needs `--trust` or a prior grant for project instructions. It also trusts that repo's hooks/MCP, so only use it on the maintainer's own repos | `12-project-rules.md`, `22-permissions-and-safety.md`, `10-hooks.md` (not listed in `grok --help`, but accepted by 1.0.70) |
| `--rules <TEXT>` | Appends the factory's shared `AGENTS.md` to the system prompt, since it lives in this repo, not the target | CLI reference |
| `--output-format json` | One JSON object at the end: `text`, `stopReason`, `sessionId`, `num_turns`, `usage` | Headless & Scripting |
| `--max-turns <N>` | Caps agent turns (cost mode). Headless only | CLI reference |
| `--always-approve` (`--yolo`) | Without it, a headless run refuses every tool call that needs approval and **still exits 0** | headless guide "Always-approve for automation" |
| `--sandbox workspace` | Writes limited to the working directory, `~/.grok/` and temp dirs (Landlock on Linux) | `18-sandbox.md` |
| `--deny 'Bash(...)'` | Hard blocks that still apply under always-approve: Grok Build never pushes or calls `gh`; the wrapper does | `22-permissions-and-safety.md` |
| `--disable-web-search` | Fewer untrusted inputs, lower cost. Drop it per work order if research is needed | CLI reference |
| `--no-auto-update` | No update checks in scripts | Headless & Scripting |

Optional: `-m <model>` (see `grok models`), `--effort <level>`.

## Backend: a setting, not a label

The headless coding step is a setting, `FACTORY_LLM`, not a per-work-order
label on the factory. `FACTORY_LLM=grok` (unset behaves the same) runs the
command above, unchanged. `FACTORY_LLM=claude` runs Claude Code headless
instead, in `scripts/run-work-order.sh`:

```sh
GH_CONFIG_DIR="$empty_tmp_dir" GIT_TERMINAL_PROMPT=0 \
claude -p --output-format json --max-turns "$turns" \
  --permission-mode bypassPermissions \
  --disallowedTools "Read(//<absolute secrets dir>/**)" "Bash(*factory-secrets*)" \
    "Bash(git push*)" "Bash(gh *)" "Bash(gh)" "WebSearch" "WebFetch" \
  < "$prompt_file"
```

run with `cd "$dir"` first (`claude` has no `--cwd`), scrubbed the same way as
the `grok` call (plus `ANTHROPIC_API_KEY`, so the box's existing Claude login
is used, never a billed key, and `GIT_ASKPASS`/`SSH_AUTH_SOCK`). `claude` must
be on `PATH`; `CLAUDE_BIN` overrides the binary name, the same way
`FACTORY_WORKSPACE` overrides the clone root. `--max-turns` reads
`CLAUDE_MAX_TURNS`, falling back to `GROK_MAX_TURNS`, then `60`.

The wrapper writes the absolute secrets directory into that `Read` guard with
the leading `//` anchor. The snippet above shows it as the placeholder
`Read(//<absolute secrets dir>/**)`. Claude Code's permission rules anchor a
single leading `/` to the project directory, so `//` is how an absolute path
is spelled in this syntax. The same `//` form belongs anywhere else this
guard is written (this file, the wrapper script, any other doc that repeats
it): a single `/` silently does nothing. The `Bash(*factory-secrets*)` guard
stays beside the `Read` guard.

| grok | claude | Why |
| --- | --- | --- |
| `--prompt-file`/`--rules` | same text, concatenated, read over stdin | `claude` has one prompt input, not two |
| `--always-approve` | `--permission-mode bypassPermissions` | both skip interactive approval |
| (none; `--trust` is the target repo's own settings, needed for its `AGENTS.md`) | `--setting-sources user` | stops a cloned repo's own `.claude/settings.json` (for example a `SessionStart` hook) from running; `bypassPermissions` has no deny list for hooks, so without this a repo-controlled hook would run unconstrained |
| `--disable-web-search` | `--disallowedTools ... "WebSearch" "WebFetch"` | same fewer-untrusted-inputs reason |
| `--deny 'Bash(git push*)' --deny 'Bash(gh *)'` | `--disallowedTools ... "Bash(git push*)" "Bash(gh *)" "Bash(gh)"` | `bypassPermissions` on its own would let Claude run `git push` or `gh` itself; the bare `Bash(gh)` form catches a no-argument call the `gh *` glob misses |
| (none; the `--factory-secrets` guard is the env scrub) | `--disallowedTools "Read(//<absolute secrets dir>/**)" "Bash(*factory-secrets*)"` | belt-and-suspenders on top of the env scrub, which is the real guard for both backends. The wrapper writes the absolute secrets directory into the `Read` guard with the leading `//` anchor |
| `GH_CONFIG_DIR` set to a fresh empty directory, removed after the run | same | stops a `gh` call that somehow runs anyway from reading the box's real `~/.config/gh` (tokens included); applied to both backends |
| `GIT_TERMINAL_PROMPT=0`, `GIT_ASKPASS`/`SSH_AUTH_SOCK` unset | same | stops a `git` call that somehow runs anyway from prompting for or finding real credentials, or reaching the box's ssh-agent; applied to both backends |

The result is normalised into `$dir.grok.json` — **that file name does not
change**, so `write_bench_handoff` and every other caller that reads
`.total_cost_usd`/`.num_turns` for cost need no change. The raw Claude Code
result (`subtype`, `is_error`, …) is mapped to the same `.stopReason` field
`grok` already has: `success` with no error becomes `end_turn`;
`error_max_turns` becomes `max_turn_requests`; anything else passes the
`subtype` straight through, so it still fails the `end_turn` check below.

## Reading the result

- Exit code `0` is success, `1` is an auth, network or runtime error, `130`/`143`
  are interrupts. Exit `0` alone is **not** enough: check
  `jq -r .stopReason` is `end_turn` (`max_tokens` or a max-turns stop means
  unfinished), and that the clone has commits or changes.
- Keep `sessionId` to continue a fix attempt with `grok -p "..." --resume <id>`.
- Never paste the JSON into an issue or PR; it can contain file contents.

## Run environment

What this runs on today, and what protects it (tracked in #44; the identity
decision is #7):

- **The box.** It runs on the shared box. There is no per-agent sandbox.
  `--sandbox workspace` limits where Grok writes, nothing more.
- **Credentials on that box.** The owner's `gh` token, the Grok CLI signed in
  as the owner, and the GitHub App `software-factory-line` used by the watcher.
  The wrapper may keep those for clone, push, and the pull request.
- **What the builder process receives.** None of those tokens or secrets.
  The child is started without `GH_TOKEN`, `GITHUB_TOKEN`,
  `GH_ENTERPRISE_TOKEN`, `GITHUB_ENTERPRISE_TOKEN`, `FACTORY_GH_APP_ID`,
  `FACTORY_GH_APP_INSTALLATION_ID`, `FACTORY_GH_APP_KEY_FILE`,
  `FACTORY_GH_APP_ENV_FILE`, `FACTORY_GH_APP_PRIVATE_KEY`,
  `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`,
  `AWS_SECURITY_TOKEN`, `GOOGLE_APPLICATION_CREDENTIALS`,
  `CLOUDSDK_AUTH_ACCESS_TOKEN`, and `AZURE_CLIENT_SECRET`.
  Keep `XAI_API_KEY` when that is how the box logs the CLI in: Grok needs it
  to run, and a stored session wins when one is present. Non-secret `GH_REPO`
  and `GH_HOST` stay. `scripts/test-run-work-order.sh` (`grok-token-scrub`)
  sets a fake sentinel on each scrubbed name and checks the child environment.
- **Forbidden.** The builder must not `git push`, call `gh`, or see the
  secrets listed above. Push and the pull request stay in the wrapper. Keep
  `--deny 'Bash(git push*)' --deny 'Bash(gh *)'` for grok, and the matching
  `--disallowedTools "Bash(git push*)" "Bash(gh *)" "Bash(gh)"` for claude
  (`bypassPermissions` has no deny list of its own, so without it Claude could
  push or call `gh` directly).
- **The on-disk `gh` config.** `GH_CONFIG_DIR` is pointed at a fresh empty
  directory for the duration of the run, for both backends, removed
  afterwards, so a `gh` call that runs despite the rule above still can't read
  the box's real `~/.config/gh` (tokens included). `GIT_TERMINAL_PROMPT=0` and
  unsetting `GIT_ASKPASS`/`SSH_AUTH_SOCK`, for both backends, do the same for a
  stray `git` call that needs credentials or the box's ssh-agent.
- **Claude's own startup hooks.** A cloned repo can ship `.claude/settings.json`
  with a `SessionStart` hook; `bypassPermissions` does not gate hooks, only
  tools. `--setting-sources user` keeps Claude from loading that repo's
  project/local settings, so a repo-controlled hook never runs.
- **`--restricted` was considered and rejected here.** `claude --help`
  documents a `--restricted` mode that confines file tools to the working
  directories and refuses `bypassPermissions`. That conflicts with this
  wrapper's design (parity with grok's `--always-approve`, so the builder
  never stops for an interactive prompt headless has no one to answer), so it
  is not used. If that trade-off ever changes, check `claude --help` again
  first — flags on an installed `claude` build are the only ones safe to
  add; this file predates several of them.
- **The secrets directory's own permissions.** Before each run, the wrapper
  checks `$HOME/.factory-secrets` (`FACTORY_SECRETS_DIR` to override) is mode
  `0700` or tighter, and tightens it if not. That only catches an
  accidentally loosened directory; it is not a defence against a process that
  can already read as this user (see below).
- **A guardrail, not isolation.** All of the above — the deny/disallow rules,
  `GH_CONFIG_DIR`, the secrets-permission check, the `Read`/`Bash` rules
  guarding `.factory-secrets` — are guardrails, not isolation: the builder
  (grok or claude) runs as the **same OS user** as the wrapper. Any subprocess
  it starts, however it starts it, can still read and write anything that
  user can read and write, `.factory-secrets` and the real `gh`/git
  credentials included, because nothing here changes the OS-level
  permissions that process is running under. Real isolation needs a separate
  OS account or an OS-level sandbox (a container, Landlock/seccomp profile
  broader than grok's own `--sandbox workspace`, or similar) — that stays
  later work, tracked with the egress allowlist and separate bot identity
  (#7).
- **Review.** The maintainer must review this file because `agents/**` is protected
  (AGENTS.md §5).

## What the wrapper does

`scripts/run-work-order.sh [--push] <work-order.md>`:

1. Reads `repo`, `issue`, `branch`, `base`, `test_command`, `title` and the
   optional `setup_command` from the work order's front matter, and validates them.
2. Clones the repo into a new bench clone directory under the clone root. By
   default the wrapper's built-in root is used; set `FACTORY_WORKSPACE` to
   choose a different root. If the root does not exist it is created if possible; if it cannot be
   created or is not writable the script falls back to a temporary directory
   and prints which root it fell back from and which it is using on stderr. If
   neither is usable it exits with code 8 naming the root. The paths in the run
   log must match where the work happened. `$dir.grok.json`, `$dir.bench.txt`
   and `$dir.venv` are written beside the clone directory.
3. Runs the command above, with GitHub tokens, GitHub App key material and
   cloud credentials removed from the builder process (`XAI_API_KEY` stays
   when that is how the box logs the CLI in; `GH_REPO` and `GH_HOST` stay).
4. Stops (exit 3) if Grok fails or doesn't end with `end_turn`, or made no
   change. Grok Build often commits by itself, so its commits and any leftover
   changes become one commit on top of the starting revision, titled
   `<title> (#<issue>)` (commits already on a reused remote branch stay put).
   Stops (exit 4) if the change touches a protected path (AGENTS.md §5; `scripts/protected-paths.sh`, which
   leaves `agents/work-orders/` alone).
5. Prepares the test environment (#34): the work order's `setup_command`, else
   `agents.setup_command` from `.github/factory.yml` on `origin/<base>`, else
   auto-detect: a Python venv at `<clone>.venv`, outside the clone
   (`pip install -e` with whichever of the `dev` and `test` extras
   `pyproject.toml` declares in `[project.optional-dependencies]`, e.g.
   `.[dev,test]`, else `.`; Poetry groups aren't pip extras and are ignored;
   then each `requirements*.txt`, plus pytest/ruff/mypy/black/flake8 when
   `test_command` names them), or a Node
   install (`pnpm`/`yarn` with a frozen lockfile, `npm ci`, or
   `npm install --no-package-lock`). Stops with exit 6 if setup fails, and exit 4
   if setup changed a tracked file such as a lockfile. `setup_command` runs in
   its own shell, so it can't change `PATH` for the tests.
6. Runs `test_command` in the clone and stops (exit 5) if it fails.
7. Pushes the branch only with `--push`. It never opens PRs or merges.

## Verified, and still not verified

First end-to-end run: 2026-10-26 on Grok Build 1.0.70 (#33, adamsuk/gh-factory#23),
then a second run that built #34 in this repo.

- **Works:** the command above, unchanged. `--trust` is accepted (it's still not
  listed in `grok --help`). A finished run ends with `stopReason: end_turn`.
- **JSON output** has more fields than the docs list: `thought`, `modelUsage`,
  `total_cost_usd`, `total_cost_usd_ticks`, `requestId` and `cwd`, as well as
  `text`, `stopReason`, `sessionId`, `num_turns` and `usage`. `thought` and
  `text` can hold file contents and reasoning, so **never paste the JSON**
  anywhere; report only `stopReason`, `num_turns` and `usage`.
- **Billing:** the factory computer is signed in with a grok.com (SuperGrok)
  session, so runs draw from the SuperGrok weekly allowance, not API billing.
  `total_cost_usd` is an API-equivalent figure, useful for comparing runs, not
  a charge. (The smoke test was about $0.10 equivalent and 12 turns; #34 was
  about $1.05, 44 turns and 24 minutes.)
- **Grok Build commits by itself**, with its own message; the wrapper now
  squashes that into `<title> (#<issue>)`.
- **Not verified yet:** the exact `stopReason` after a `--max-turns` stop in
  `json` output (the streaming formats document `error_max_turns` and a
  `max_turns_reached` event), so the wrapper still treats anything but
  `end_turn` as unfinished. Running with `XAI_API_KEY` instead of a session.
- The sandbox's `workspace` profile (bubblewrap on this computer) still lets
  Grok **read** everywhere, including the `gh` login. Until agents have their
  own identity (#7), the `--deny` rules and removing `GH_TOKEN` are guardrails,
  not isolation.
