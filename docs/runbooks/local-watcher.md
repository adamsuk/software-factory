# Local watcher: both lanes on one machine

Bring up the main lane and the build lane on a maintainer's machine.

- Main lane: `scripts/watcher/watch.sh`
- Build lane: `scripts/watcher/watch.new.sh` with `LANE=build`

`watch.new.sh` is a symlink to `watch.sh` (#520): both lanes are the same script, chosen by `LANE`.

`scripts/watcher-preflight.sh` checks the settings below. It exits 0 when every one is present. Otherwise it exits non-zero and prints `watcher-preflight: missing <name>` for each missing variable, command or path. Its output is names only.

Part of #386. Lane behaviour is unchanged. See `scripts/watcher/README.md` for what the lanes do once they are running.

## Variables the preflight checks

| Variable | When it is required | Meaning |
| --- | --- | --- |
| `FACTORY_PROVIDER` | optional | `grok` (the default when unset), `claudecode` or `opencode`. |
| `FACTORY_WATCHER_BUILDS` | optional | `on` (the default when unset) or `off`. The build foreman always runs through Grok, so when this is not `off` the preflight also runs the Grok CLI and credential checks for `claudecode` and `opencode`. When it is `off`, those providers do not need Grok. |
| `XAI_API_KEY` | Grok credential, unless `FACTORY_GROK_AUTH_FILE` is set | API-key credential. Required for `FACTORY_PROVIDER=grok`, and for `claudecode` or `opencode` unless `FACTORY_WATCHER_BUILDS=off`. |
| `FACTORY_GROK_BIN` | optional | Executable file: the host `grok` binary. Accepted as the grok CLI when it is set. Checked on its own; the auth file does not need it. |
| `FACTORY_GROK_AUTH_FILE` | Grok credential when `XAI_API_KEY` is unset | Readable absolute path of the subscription login file. Sufficient on its own, with or without `FACTORY_GROK_BIN`. |
| `CLAUDE_CODE_OAUTH_TOKEN` | `claudecode` | Claude Code credential (`claude setup-token`). |
| `OPENCODE_API_KEY` | `opencode`, one of these four | opencode credential. |
| `OPENROUTER_API_KEY` | `opencode`, one of these four | opencode credential. |
| `OPENAI_API_KEY` | `opencode`, one of these four | opencode credential. |
| `ANTHROPIC_API_KEY` | `opencode`, one of these four | opencode credential. |
| `FACTORY_CONTAINER_RUNTIME` | optional | `podman`, `docker`, `nerdctl`, or a path to one. When unset, the preflight uses the first of `podman`, `docker` and `nerdctl` on `PATH`. |
| `FACTORY_CONTAINER_IMAGE` | always | Image that carries the model CLI. |
| `FACTORY_WATCH_ROOT` | optional | Watcher root. The preflight requires `$FACTORY_WATCH_ROOT/state` to be a directory the process can write and search. For a non-root owner, mode `0600` is rejected and mode `0700` passes. Default: `$FACTORY_HOME/factory-watch`. |
| `FACTORY_HOME` | optional | Base directory the watch root derives from. Default: `${XDG_DATA_HOME:-$HOME/.local/share}/software-factory`. |
| `XDG_DATA_HOME` | optional | Used only in the `FACTORY_HOME` default. |
| `HOME` | optional | Used only when `FACTORY_HOME` and `XDG_DATA_HOME` are unset. |

The same names are in `stations/run-factory.md` (provider credentials) and `scripts/watcher/factory-env.sh` (the watch-root default).

## Commands and paths the preflight checks

- `gh` is on `PATH`, and `gh auth status` exits 0. The status text is discarded.
- Grok CLI: `grok` on `PATH`, or an executable `FACTORY_GROK_BIN`, or `FACTORY_CONTAINER_IMAGE` (the image carries the CLI). The credential is `XAI_API_KEY`, or a readable absolute `FACTORY_GROK_AUTH_FILE` on its own. These checks run for `FACTORY_PROVIDER=grok`, and also for `claudecode` and `opencode` unless `FACTORY_WATCHER_BUILDS=off`, because the build foreman always runs through Grok.
- Claude Code CLI: `claude` on `PATH`, or `FACTORY_CONTAINER_IMAGE`.
- opencode CLI: `opencode` on `PATH`, or `FACTORY_CONTAINER_IMAGE`.
- Container runtime: `FACTORY_CONTAINER_RUNTIME` when that variable is set, otherwise the first of `podman`, `docker` and `nerdctl` on `PATH`.
- `$FACTORY_WATCH_ROOT/state` is a directory the process can write and search. For a non-root owner, mode `0600` is rejected and mode `0700` passes. The preflight does not create it.

## Run the preflight

From a checkout of this repo, with the variables above exported in the shell:

```bash
mkdir -p "${FACTORY_WATCH_ROOT:-${FACTORY_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/software-factory}/factory-watch}/state"
bash scripts/watcher-preflight.sh
```

`watcher-preflight: ok` means every check passed. Any other exit is non-zero, and each line names one missing variable, command or path.

## Start both lanes

Do this after the preflight prints `watcher-preflight: ok`, in a shell where those variables are still exported.

The container path also reads `FACTORY_CONTAINER_NETWORK` (required) and `FACTORY_CONTAINER_PROXY` (optional) from `docs/runbooks/station-container.md` and `docs/runbooks/work-order-container.md`. Export those before starting. The preflight does not check them.

### Start commands

From the checkout:

```bash
setsid nohup bash scripts/watcher/watch.sh >> nohup.out 2>&1 < /dev/null &
setsid nohup env LANE=build bash scripts/watcher/watch.new.sh >> nohup.out 2>&1 < /dev/null &
```

When the lane scripts have been copied to `$FACTORY_WATCH_ROOT` (see `scripts/watcher/README.md`), the same two processes from that directory:

```bash
cd "$FACTORY_WATCH_ROOT"
setsid nohup bash ./watch.sh >> nohup.out 2>&1 < /dev/null &
setsid nohup env LANE=build bash ./watch.new.sh >> nohup.out 2>&1 < /dev/null &
```

The main lane is `watch.sh` with no `LANE` override. The build lane is `watch.new.sh` with `LANE=build`.

### systemd --user

Two units, under `~/.config/systemd/user/`. Point `ExecStart` at the checkout that contains the lane scripts. Keep the preflight variables in an `EnvironmentFile` outside the repo (mode `0600`). The unit files hold names and `LANE=build` only.

`~/.config/systemd/user/factory-watcher-main.service`:

```ini
[Unit]
Description=Factory watcher main lane

[Service]
Type=simple
EnvironmentFile=%h/.config/factory/watcher.env
ExecStart=/usr/bin/env bash /path/to/software-factory/scripts/watcher/watch.sh
Restart=on-failure

[Install]
WantedBy=default.target
```

`~/.config/systemd/user/factory-watcher-build.service`:

```ini
[Unit]
Description=Factory watcher build lane

[Service]
Type=simple
Environment=LANE=build
EnvironmentFile=%h/.config/factory/watcher.env
ExecStart=/usr/bin/env bash /path/to/software-factory/scripts/watcher/watch.new.sh
Restart=on-failure

[Install]
WantedBy=default.target
```

`watcher.env` is a list of assignments for the variables in the table above, plus `FACTORY_HOME_REPO=<owner>/<repo>` for this checkout (required: a user service starts in the home directory, which is not a clone, so neither lane can resolve a home repo), plus `FACTORY_CONTAINER_NETWORK` and, when the network is not `none`, `FACTORY_CONTAINER_PROXY`. Replace `/path/to/software-factory` with the checkout.

```bash
systemctl --user daemon-reload
systemctl --user enable --now factory-watcher-main.service
systemctl --user enable --now factory-watcher-build.service
```

## Related

- `scripts/watcher/README.md` — lane scripts, state files and path defaults.
- `docs/runbooks/station-container.md` — image, internal network and proxy for the station container.
- `docs/runbooks/work-order-container.md` — the same runtime and image for the builder.
