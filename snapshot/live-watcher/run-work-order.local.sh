#!/usr/bin/env bash
# Local override until software-factory factory/claude-backend merges.
# Drops the patched script beside its siblings in the sf clone (cwd) so
# gh-app-token.sh and protected-paths.sh resolve, then runs it.
set -euo pipefail
cp /workspace/factory-watch/run-work-order.claude-branch.sh scripts/run-work-order.claude.sh
exec bash scripts/run-work-order.claude.sh "$@"
