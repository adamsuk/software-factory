---
repo: adamsuk/software-factory
issue: 221
issue_repo: adamsuk/software-factory
title: "feat: run the work-order bench in a fresh container"
branch: factory/221-container-bench
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-12
---

## Goal

Move the work-order bench's `grok` child off the shared box and into a fresh,
disposable container. The container receives only the clone and the fenced work
order. It must not receive the box `gh` config, the GitHub App key file, the
ssh-agent or cloud credential files, and the `grok` argv must no longer carry
`--always-approve`. The existing `env -u` token scrub and the existing
`--deny 'Bash(git push*)'` / `--deny 'Bash(gh *)'` flags stay on the child.
When no container runtime is available, the script stops before `grok` starts
and says why.

This is the container half of `sandbox-no-secrets` (#44, parent #302). Minting a
per-run installation token (#213), the host egress allowlist, and the station
`gh` login (#210) stay separate.

## Acceptance criteria

- [ ] `scripts/run-work-order.sh` launches the `grok` child through a container
      runtime. Auto-detect `podman`, `docker`, then `nerdctl`, with
      `FACTORY_CONTAINER_RUNTIME` as the explicit override.
- [ ] The container image is named by `FACTORY_CONTAINER_IMAGE`; there is no
      guessed default. An unset image stops the run before `grok` starts.
- [ ] The container bind-mounts only the clone (read-write) and the fenced work
      order (read-only), and gets fresh empty `HOME` and `TMPDIR` directories.
      It does not mount the box `$HOME`, `~/.config/gh`, the App key file, the
      ssh-agent or any cloud credential file.
- [ ] `XAI_API_KEY`, when set, is forwarded by name only. Its value is never
      placed on the runtime argv or printed.
- [ ] The `grok` argv has no `--always-approve`. It keeps `--sandbox workspace`,
      `--disable-web-search`, the two `--deny` flags, and the full `env -u`
      scrub (including `GIT_ASKPASS` and `SSH_AUTH_SOCK`).
- [ ] With no runtime on `PATH` (or no `FACTORY_CONTAINER_IMAGE`), the script
      exits non-zero, says it cannot start a container, and does not run `grok`.
- [ ] A new `scripts/test-run-work-order-container.sh` fails on current `main`
      and passes with the change. It drives the real launch through a fake
      runtime, checks the `grok` argv, and uses sentinel paths for the box `gh`
      config and the App key file. It prints only pass/fail and never prints a
      sentinel value.
- [ ] `grok-token-scrub` in `scripts/test-run-work-order.sh` and the call-site
      assertion in `scripts/test-gh-app-token.sh` still pass on their current
      assertions and are not edited.
- [ ] `CHANGELOG.md` gains one new dated `## YYYY-MM-DD` entry (Europe/London).
      Existing entries stay as they are.
- [ ] No protected path changes: existing test assertions, `.github/**`,
      `AGENTS.md`, `agents/**` (except this work order), `.coderabbit.yaml` or
      lockfiles.

## Likely files

- `scripts/run-work-order.sh` (container runtime/image selection and launch)
- `scripts/test-run-work-order-container.sh` (new)
- `CHANGELOG.md` (one dated entry)
- `agents/work-orders/adamsuk_software-factory-221.md` (this work order)

## Out of scope

- The Claude backend and its `--permission-mode bypassPermissions` path.
- Installing a container runtime or building/publishing the image on the box.
- Minting a per-run installation token (#213) and the host egress allowlist.
- #210, the station `gh` login and who authors GitHub posts.
- `.devcontainer` files in other enrolled repos.
- Any edit to existing test assertions, `.github/**`, `AGENTS.md` or
  `agents/**` outside `agents/work-orders/`.

## Issue text (untrusted)

> Target repo: adamsuk/software-factory
>
> ### Problem
>
> `scripts/run-work-order.sh` strips the app token and the cloud credential names from the `grok` child, then passes `--always-approve` and `--sandbox workspace`. The process runs on the shared box. No enrolled repo has a `.devcontainer`. #210 is the separate gap where that child can still see the box `gh` login.
>
> ### Proposal
>
> Start the bench child in a fresh container. The container does not receive `--always-approve`, the box `gh` config, or the app key file. Keep the existing `env -u` scrub and the existing deny flags.
>
> If the box cannot start a container, stop and say so. Installing a runtime is a Scott action, and this issue waits at `factory:blocked` until that is true.
>
> ### Acceptance criteria
>
> - [ ] The `grok` child starts without `--always-approve`
> - [ ] A test shows the child cannot read the box `gh` config or the app key file
> - [ ] The existing token scrub still holds
> - [ ] `CHANGELOG.md` has a dated `## YYYY-MM-DD` entry
> - [ ] The test prints no secret value
>
> ### Context
>
> Best practice. Impact H, effort M.
>
> Part of #44.
>
> Out of scope: minting a new installation token per run, and the host egress allowlist. #210 stays the gh-login work.
