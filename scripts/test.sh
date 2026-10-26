#!/usr/bin/env bash
# The configured test command; run from any directory.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
shellcheck scripts/*.sh
bash scripts/test-run-work-order.sh
python3 scripts/test-workflow.py
