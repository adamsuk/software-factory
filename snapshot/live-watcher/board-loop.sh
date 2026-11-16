#!/usr/bin/env bash
# Sidecar: run board-sync.sh every 15 min, never overlapping. Logs to board-sync.log.
cd /workspace/factory-watch
exec 8>board-loop.lock; flock -n 8 || { echo "board-loop already running"; exit 0; }
while true; do
  {
    echo "=== $(date -u +%FT%TZ) board-sync start"
    flock -w 600 9 && timeout 30m ./board-sync.sh 2>&1 | sed -E 's/(gh[opsu]_|github_pat_)[A-Za-z0-9_]+/\1***REDACTED***/g'
    echo "=== $(date -u +%FT%TZ) board-sync end rc=${PIPESTATUS[0]}"
  } 9>board-sync.lock >> board-sync.log 2>&1
  sleep 900
done
