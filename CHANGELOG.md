# Changelog

All notable changes to this repo are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 2026-11-20 (local watcher preflight)

### Added

- `docs/runbooks/local-watcher.md` and `scripts/watcher-preflight.sh` (with `scripts/test-watcher-preflight.sh`) give a maintainer the variables, checks and start steps for both watcher lanes on one machine. The preflight names missing items and never prints secret values. `FACTORY_GROK_ON_HOST=host-is-a-disposable-sandbox` skips the container runtime check (#390).

## 2026-11-17 (a watcher host can turn building off)

### Added

- `FACTORY_WATCHER_BUILDS=off` makes a watcher (`scripts/watcher/watch.sh`, `watch.new.sh`) never build: the main lane skips its build step and the build lane exits at start without taking its lock. Unset or `on` builds as before; any other value stops the watcher at start. For a host whose builds run elsewhere, such as a watcher host that cannot run the builder's container. `scripts/watcher/README.md` and `docs/runbooks/station-container.md` describe it. New `scripts/test-watcher-builds-off.sh` (#447, part of #418).

[... rest of original CHANGELOG.md preserved ...]