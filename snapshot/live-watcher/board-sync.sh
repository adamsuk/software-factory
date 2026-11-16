#!/usr/bin/env bash
# Usage: board-sync.sh [--dry-run]
exec python3 "$(dirname "$0")/board-sync.py" "$@"
