# Station container: preparing a host

Stations (intake, foreman, reviewer and the rest) run in a
container on a network with one way out: an allow-listing proxy (#418). This
page is the host side: two images, one internal network, one proxy container
and one credential. `docs/runbooks/work-order-container.md` covers the same
settings for the builder in `scripts/run-work-order.sh`; the two share them.

Run end to end on one host on 2026-11-15: rootless podman 5.7.0 with netavark,
Ubuntu. docker and nerdctl have not been tried.

## 1. Build the images

```bash
scripts/build-station-image.sh
```

This builds `localhost/factory-station:claude-<version>-gh-<version>` and
`localhost/factory-egress-proxy:1`. The base images are pinned by digest and
the Claude Code CLI by version, all in that script. `--print` shows the build
commands without running them.

The station image holds bash, git, gh, jq, python3 with PyYAML, shellcheck and
the `claude` CLI. It holds no credential and copies nothing from the host.

## 2. Create the network and start the proxy

```bash
podman network create --internal factory-egress
```

```bash
podman network create factory-egress-out
```

```bash
mkdir -p ~/.config/containers/systemd && cp containers/egress-proxy/factory-egress-proxy.container ~/.config/containers/systemd/
```

```bash
systemctl --user daemon-reload && systemctl --user start factory-egress-proxy.service
```

```bash
systemctl --user is-active factory-egress-proxy.service
```

The proxy runs as a systemd user service (a Quadlet unit), so it starts when
the user logs in and is restarted if it stops. It starts at login, not at boot:
a host that must run stations with nobody logged in also needs
`loginctl enable-linger`, which is the operator's call. On docker or nerdctl
there is no Quadlet; run the same image on the same two networks with that
runtime's own restart policy.

`factory-egress` is internal: a container on it has no route to any other
host. The proxy sits on both networks, so it is the only way out. It needs the
second network to be one with DNS (a network you create, not podman's default
`podman` network), or it cannot resolve the hosts it is allowed to reach.

The proxy allows `CONNECT` to port 443 on the hosts in
`containers/egress-proxy/allowlist.txt` and refuses everything else:

| Host | Why |
| --- | --- |
| `api.anthropic.com` | Claude Code's model API |
| `api.x.ai`, `cli-chat-proxy.grok.com` | Grok's model API (the second is what a subscription login uses) |
| `api.github.com`, `github.com` | `gh` reads, `scripts/station-post.sh` writes, git fetch and push |

A change to that list is a change to the file and a rebuild of the proxy image.

## 3. Check it

Each of these should print what the comment says.

```bash
podman run --rm --network factory-egress -e HTTPS_PROXY=http://factory-egress-proxy:8888 localhost/factory-station:claude-2.1.322-gh-2.103.3 curl -sS -o /dev/null -m 15 -w '%{http_code}\n' https://api.github.com/   # 200
```

```bash
podman run --rm --network factory-egress -e HTTPS_PROXY=http://factory-egress-proxy:8888 localhost/factory-station:claude-2.1.322-gh-2.103.3 curl -sS -o /dev/null -m 15 -w '%{http_code}\n' https://example.com/   # 000, CONNECT tunnel failed
```

```bash
podman run --rm --network factory-egress localhost/factory-station:claude-2.1.322-gh-2.103.3 curl -sS -o /dev/null -m 8 -w '%{http_code}\n' https://api.github.com/   # 000, no route without the proxy
```

On 2026-11-15 the first printed 200, `api.anthropic.com` answered 404 at `/`
(reachable), and `example.com`, `raw.githubusercontent.com` and the no-proxy
case all failed as intended.

## 4. The provider credential

The container has no home directory from the host, so the CLI's own login is
not there. Claude Code takes a long-lived token from the environment instead:

```bash
claude setup-token
```

Export what it prints as `CLAUDE_CODE_OAUTH_TOKEN` in the shell (or service)
that starts stations. Never commit it, and never put it in an image. Grok takes
`XAI_API_KEY` the same way.

### Grok

With an API key, export `XAI_API_KEY` and use an image that has the `grok` CLI.

A SuperGrok subscription has no API key. Two settings cover that, both off
unless set:

```bash
export FACTORY_GROK_BIN="$HOME/.grok/bin/grok"
```

```bash
export FACTORY_GROK_AUTH_FILE="$HOME/.grok/auth.json"
```

`FACTORY_GROK_BIN` mounts the host's `grok` binary read-only at
`/usr/local/bin/grok`; it is one static file, so the station image needs
nothing added. `FACTORY_GROK_AUTH_FILE` mounts the login file read-only into
the container's own empty `~/.grok`. It is used only when `XAI_API_KEY` is not
set.

The login file is a long-lived account credential, and inside the container the
model can read it. The proxy limits where it could be sent; it does not remove
the risk. Use `XAI_API_KEY` where one exists (AGENTS.md section 7).

## 5. What to export

```bash
export FACTORY_CONTAINER_IMAGE=localhost/factory-station:claude-2.1.322-gh-2.103.3
```

```bash
export FACTORY_CONTAINER_NETWORK=factory-egress
```

```bash
export FACTORY_CONTAINER_PROXY=http://factory-egress-proxy:8888
```

Checking a host, names only:

```bash
echo "${FACTORY_CONTAINER_IMAGE:-unset}" "${FACTORY_CONTAINER_NETWORK:-unset}" "${FACTORY_CONTAINER_PROXY:-unset}" "${CLAUDE_CODE_OAUTH_TOKEN:+token set}"
```

## What starts in the container

`scripts/station-run.sh` starts every provider adapter in it, and the watcher's
non-Grok provider calls go through `scripts/station-container.sh`, which builds
the same container. Both exit 9 and start nothing when the runtime, the image,
the restricted network or the provider credential is missing. `--dry-run` needs
none of it.

| In the container | Not in the container |
| --- | --- |
| The working tree, read-write: the real checkout for a writing role (foreman, builder), a throwaway clone for a reading one | The original checkout, for a reading role |
| The start-of-run snapshot of `scripts/`, `adapters/` and the prompts, read-only | This host's home directory, `gh` login and ssh agent |
| The prompt bundle, and the work order file, read-only | The App key file and every other repository on the box |
| The provider's own credential and `GH_TOKEN`, forwarded by name | Every other environment variable, other providers' credentials included |

`GH_TOKEN` has to be in the environment, or `FACTORY_GH_APP_ID` and its two
companions set so `station-run.sh` mints an installation token. The watcher
forwards no GitHub token: it does the GitHub writes itself.

The container runs as the calling user, with all capabilities dropped. It must
not be root: Claude Code refuses to run with approval off as root, and rootless
podman maps the caller to root unless `--userns keep-id` is passed, which the
scripts do.

Checked on 2026-11-15 from a real container on this setup: `gh api` and
`git ls-remote` worked through the proxy, `example.com` was refused, `/home`
held nothing of the host, the App key file and the real checkout were not
there, a file written in the working tree was owned by the calling user, and a
read-only mount could not be written. A reviewer station run with a
deliberately invalid token reached the model API and was answered `401 Invalid
bearer token`. A run with a valid token has not been done yet.

The watcher's Grok calls go through the same container (#428). They get no
GitHub token, except the foreman, dependabot-triage and plan jobs, whose
prompts call `gh`: those get `GH_TOKEN` by name, and only when the App is
configured, so it is the bot's one-hour installation token. The foreman also
gets the orders directory read-write, where it writes the work order.

Checked on 2026-11-15 with a real Grok on a subscription login: a job ran in
the container and answered, a second one called `gh api` with the bot's token
and returned the repository name, and the login file on the host was unchanged
afterwards. The proxy refused `api.mixpanel.com` and `grok.com`, which Grok
tries and does not need. Not run: the watcher itself, end to end, on a host
that runs it.

Not covered: the Grok builder clones, runs the target repo's tests and pushes
on the host through `scripts/run-work-order.sh`; only its model child is in a
container.

## A watcher host that cannot run a container

Some hosts cannot take this setup at all. The maintainer's remote watcher host
is one: it is itself a disposable container with no runtime, and its own egress
allow-list refused the Debian mirrors over both HTTP and HTTPS, so nothing
could be installed (2026-11-16). For a host like that, and only for the
watcher's Grok launch, there is one explicit setting (#440):

```bash
export FACTORY_GROK_ON_HOST=host-is-a-disposable-sandbox
```

The value must be that exact phrase. Anything else, or nothing, keeps the
container. With it set, the watcher starts `grok` directly on the host and logs
`grok uncontained ...` for every such run. Stations and `scripts/station-run.sh`
ignore the setting: they stay container-only.

What the watcher still does in this mode:

- gives `gh` an empty `GH_CONFIG_DIR`, so a cleared `GH_TOKEN` does not fall
  back to whatever `gh` login the host has;
- removes the App settings from grok's environment;
- passes deny rules for the secrets directory, the host's `gh` config and
  grok's own login file;
- applies the same GitHub-token rule as the container: the bot's installation
  token for foreman, dependabot-triage and plan, and only with the App
  configured.

What it does not do. There is no filesystem or network boundary of ours: grok
runs as the host's user, on the host's network, with those files on the same
disk. The deny rules are grok's own permission rules, not an enforcement layer.
They held in a test against a real grok on 2026-11-16 (a file read and a `cat`
of a denied path were both refused, and `gh` had no login), but a model that
found another way to read a file would not be stopped by them. The host's own
sandbox is what limits the damage. Use the container wherever it can run.

## Known traps

- **The proxy and reboots.** Started with a bare `podman run -d --restart
  unless-stopped`, the proxy did not come back after a reboot under rootless
  podman: the images and networks were still there and the container was
  `Exited`, so every station run would have failed at the network step (#433).
  The Quadlet unit above replaces that. It was killed once on purpose on
  2026-11-16 and systemd had it back within seconds; a reboot with the unit
  installed has not been tried yet.

- **Debian's gh is too old.** The first image took `gh` from Debian (2.46.0),
  which has no `gh pr checks --json`. `scripts/ready-gate.sh` then failed with
  "could not read checks" inside the container, so a reviewer's PASS was posted
  but the label did not move (#430). The image now installs a pinned release.

- **AppArmor and tinyproxy.** Ubuntu ships an AppArmor profile attached to
  `/usr/bin/tinyproxy`. It applies inside a rootless container too and stops
  the proxy reading its filter file (`filter file: Permission denied`, exit
  65). The proxy image installs the binary as `/usr/local/bin/egress-proxy` for
  that reason.
- **Proxy DNS.** Attached to the internal network and podman's default network
  only, the proxy answered every request with 500 and logged `Name does not
  resolve`. The second network has to be a user-created one.
- **Plain HTTP.** The proxy also forwards plain HTTP on port 80 to the allowed
  hosts. Nothing a station uses needs it.
- **The builder's image.** `scripts/run-work-order.sh` needs an image with the
  target repo's test tools as well. The station image is enough for this repo's
  own tests; another repo may need its own.
