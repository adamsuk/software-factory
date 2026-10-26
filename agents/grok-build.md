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

## What the wrapper does

`scripts/run-work-order.sh [--push] <work-order.md>`:

1. Reads `repo`, `issue_repo`, `issue`, `branch`, `base`, `test_command`, `title`
   from the work order's front matter, and validates them. Branches must use
   `factory/<issue-repo-slug>/<issue>-<short-slug>` (AGENTS.md §2); generate one
   with `issue_branch` from the runner. Old work orders need their branch
   updated to this format before running.
2. Clones the repo into a new `mktemp -d /workspace/wo-<owner>_<repo>-<issue>-XXXXXX`
   directory, and switches to the branch (reusing it if it already exists on
   the remote).
3. Runs the command above, with `GH_TOKEN`/`GITHUB_TOKEN` removed from Grok's
   environment.
4. Stops (exit 3) if Grok fails or doesn't end with `end_turn`, or made no
   change; stops (exit 4) if the change touches a protected path (AGENTS.md §5);
   commits any uncommitted change with the work order's title.
5. Runs `test_command` in the clone and stops (exit 5) if it fails.
6. Pushes the branch only with `--push`. It never opens PRs or merges.

## Not verified

- Grok Build is not authenticated on the factory computer yet, so no
  end-to-end run has been made; the flags were checked against `grok --help`
  and the docs only.
- `--trust` appears in the docs but not in `grok --help` (1.0.70).
- The exact `stopReason` value after a `--max-turns` stop in `json` output
  isn't documented (the streaming formats document `error_max_turns` and a
  `max_turns_reached` event), so the wrapper treats anything but `end_turn`
  as unfinished.
- The sandbox's `workspace` profile still lets Grok **read** everywhere,
  including the `gh` login. Until agents have their own identity (#7), the
  `--deny` rules and removing `GH_TOKEN` are guardrails, not isolation.
