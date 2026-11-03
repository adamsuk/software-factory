#!/usr/bin/env bash
# Fail when the audit candidates file is over the 60000-byte limit that the
# triage job can pass on, so nothing is silently truncated.
set -euo pipefail
file=$1
size=$(wc -c < "$file")
if [ "$size" -gt 60000 ]; then
  echo "::error::candidates.md is $size bytes, over the 60000-byte limit; triage would silently drop candidates"
  exit 1
fi
