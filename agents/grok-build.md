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

## Install and authenticate (Scott, once per computer)

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
| `--trust` | Loads the **target repo's** own `AGENTS.md` and project skills. Headless startup needs `--trust` or a prior grant for project instructions. It also trusts that repo's hooks/MCP, so only use it on Scott's own repos | `12-project-rules.md`, `22-permissions-and-safety.md`, `10-hooks.md` (not listed in `grok --help`, but accepted by 1.0.70) |
| `--rules <TEXT>` | Appends the factory's shared `AGENTS.md` to the system prompt, since it lives in this repo, not the target | CLI reference |
| `--output-format json` | One JSON object at the end: `text`, `stopReason`, `sessionId`, `num_turns`, `usage` | Headless & Scripting |
| `--max-turns <N>` | Caps agent turns (cost mode). Headless only | CLI reference |
| `--always-approve` (`--yolo`) | Without it, a headless run refuses every tool call that needs approval and **still exits 0** | headless guide "Always-approve for automation" |
| `--sandbox workspace` | Writes limited to the working directory, `~/.grok/` and temp dirs (Landlock on Linux) | `18-sandbox.md` |
| `--deny 'Bash(...)'` | Hard blocks that still apply under always-approve: Grok Build never pushes or calls `gh`; the wrapper does | `22-permissions-and-safety.md` |
| `--disable-web-search` | Fewer untrusted inputs, lower cost. Drop it per work order if research is needed | CLI reference |
| `--no-auto-update` | No update checks in scripts | Headless & Scripting |

Optional: `-m <model>` (see `grok models`), `--effort <level>`.

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

- **The box:** a shared computer. There is no per-agent sandbox and no
  network egress allowlist yet. `--sandbox workspace` limits where Grok writes,
  nothing more.
- **Credentials on that box:** the owner's `gh` login and the Grok CLI signed
  in to the owner's grok.com account (or `XAI_API_KEY`). Grok Build is handed
  neither `GH_TOKEN` nor `GITHUB_TOKEN`: the wrapper runs it as
  `env -u GH_TOKEN -u GITHUB_TOKEN grok ...`, and
  `scripts/test-run-work-order.sh` (`grok-token-scrub`) runs that exact
  command with both set and checks neither reaches Grok's environment.
  `XAI_API_KEY`, when that's how this box authenticates, is **not** scrubbed
  — Grok needs it to run at all, and there's no other authentication path
  for an unattended run today.
- **The other half:** `--deny 'Bash(git push*)' --deny 'Bash(gh *)'` stop Grok
  pushing or calling `gh` directly, even if it had a credential.
- **A guardrail, not isolation.** An agent with shell access on the box could
  still reach those credentials by other means (the `gh` config file, the
  Grok login, other processes). Real isolation (sandboxing, egress limits, a
  separate bot identity) is #44's later work and #7; none of it is done here.

## What the wrapper does

`scripts/run-work-order.sh [--push] <work-order.md>`:

1. Reads `repo`, `issue`, `branch`, `base`, `test_command`, `title` and the
   optional `setup_command` from the work order's front matter, and validates them.
2. Clones the repo into a new bench clone directory under the clone root. By
   default `/workspace` is used; set `FACTORY_WORKSPACE` to choose a different
   root. If the root does not exist it is created if possible; if it cannot be
   created or is not writable the script falls back to a temporary directory
   and prints which root it fell back from and which it is using on stderr. If
   neither is usable it exits with code 8 naming the root. The paths in the run
   log must match where the work happened. `$dir.grok.json`, `$dir.bench.txt`
   and `$dir.venv` are written beside the clone directory.
3. Runs the command above, with `GH_TOKEN`/`GITHUB_TOKEN` removed from Grok's
   environment.
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
