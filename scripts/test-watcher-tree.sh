#!/usr/bin/env bash
# Checks scripts/watcher: exact tree, README topics, no forbidden patterns.
# Reads files only. Does not call the network, gh, or the live watcher.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
watch=$root/scripts/watcher
readme=$watch/README.md

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ -d $watch ]] || fail "missing scripts/watcher"
[[ -f $watch/watch.sh ]] || fail "missing scripts/watcher/watch.sh"

subs=$(find "$watch" -mindepth 1 -type d -printf '%P\n')
[[ -z $subs ]] || fail "scripts/watcher has a subdirectory"

expected=$(printf '%s\n' \
  README.md \
  autopush.sh \
  board-sync.sh \
  push-protected.sh \
  swap-early.sh \
  watch.new.sh \
  watch.sh)
actual=$(find "$watch" -type f -printf '%P\n' | sort)
[[ $actual == "$expected" ]] || fail "scripts/watcher is not the expected tree"

require_topic() {
  local topic=$1
  local needle=$2
  grep -F -q -- "$needle" "$readme" || fail "README missing topic: ${topic}"
}

require_topic "lanes" "180-second cycle sleep"
require_topic "lanes" "watch.sh"
require_topic "lanes" "watch.new.sh"
require_topic "lanes" "watch.lock"
require_topic "lanes" "watch-build.lock"
require_topic "lanes" "watch.log"
require_topic "lanes" "watch-build.log"
require_topic "lanes" "main lane"
require_topic "lanes" "build lane"
require_topic "env" "FACTORY_WATCH_ROOT"
require_topic "env" "FACTORY_BUDGET_FILE"
require_topic "env" "FACTORY_LEDGER_FILE"
require_topic "env" "FACTORY_CLONE_ROOT"
require_topic "env" "LANE"
require_topic "env" "committed default"
require_topic "env" "FACTORY_HOME"
require_topic "env" "FACTORY_WORKSPACE"
require_topic "env" "| \`FACTORY_HOME\` | \`\${XDG_DATA_HOME:-\$HOME/.local/share}/software-factory\` |"
require_topic "env" "| \`FACTORY_WATCH_ROOT\` | \`\$FACTORY_HOME/factory-watch\` |"
require_topic "env" "| \`FACTORY_BUDGET_FILE\` | \`\$FACTORY_HOME/factory-budget.json\` |"
require_topic "env" "| \`FACTORY_LEDGER_FILE\` | \`\$FACTORY_HOME/factory-ledger.csv\` |"
require_topic "env" "| \`FACTORY_CLONE_ROOT\` | \`\$FACTORY_HOME\` |"
require_topic "env" "FACTORY_HOME_REPO"
require_topic "env" "FACTORY_REPOS"
require_topic "env" "FACTORY_APPROVER_LOGIN"
require_topic "env" "<!-- factory:approve -->"
require_topic "env" "FACTORY_BLOCKED_OWNERS"
require_topic "env" "# >>> factory env"
require_topic "env" "committed default is \`main\`"
require_topic "state" "\$FACTORY_WATCH_ROOT/state/"
require_topic "state" "per-PR markers"
require_topic "state" "grok output"
require_topic "state" "events-pending.txt"
require_topic "state" "events-sent.log"
require_topic "state" "cr-requests.log"
require_topic "state" "plan-count-YYYY-MM-DD"
require_topic "state" "append.lock"
require_topic "state" "events.lock"
require_topic "state" "build-claim.lock"
require_topic "budget" "max_grok_build_runs_per_week"
require_topic "budget" "max_grok_build_runs_per_day"
require_topic "budget" "max_runs_per_loop"
require_topic "budget" "max_coderabbit_requests_per_hour"
require_topic "budget" "merge_protected_issues"
require_topic "ledger" "date_utc,kind,repo,issue_or_pr,grok_sessions,api_equiv_usd,result"
require_topic "swap" "swap-early.sh"
require_topic "swap" "cycle sleep"
require_topic "swap" "lock holder"
require_topic "swap" "live script"
require_topic "swap" "staged script"
require_topic "swap" "LANE=build"
require_topic "uncommitted" "State files, budget contents, ledger contents, and \`webhook.curl\` are not committed."
require_topic "board" "Board settings"
require_topic "board" "not committed constants"
require_topic "board" "FACTORY_BOARD_OWNER"
require_topic "board" "FACTORY_BOARD_NUMBER"
require_topic "board" "FACTORY_BOARD_PROJECT_ID"
require_topic "board" "FACTORY_BOARD_FIELD_ID"
require_topic "board" "FACTORY_BOARD_OPTIONS"
require_topic "board" "board sync not configured"

# board-sync.sh reads every board setting from the environment.
for board_var in FACTORY_BOARD_OWNER FACTORY_BOARD_NUMBER FACTORY_BOARD_PROJECT_ID \
  FACTORY_BOARD_FIELD_ID FACTORY_BOARD_OPTIONS; do
  grep -F -q -- "$board_var" "$watch/board-sync.sh" || fail "board-sync.sh does not read ${board_var}"
done

# Fixed strings. The word token, a github.com URL, webhook.curl, and the
# FACTORY_HOME defaults are not in this list. Project node ids (PVT_, PVTSSF_)
# are configuration, never committed.
fixed_needles=(
  'ghp_'
  'gho_'
  'github_pat_'
  '/home/'
  '/Users/'
  'PVT_'
  'PVTSSF_'
)

while IFS= read -r -d '' file; do
  rel=${file#"$root"/}
  for needle in "${fixed_needles[@]}"; do
    if grep -F -q -- "$needle" "$file"; then
      fail "forbidden pattern ${needle} in ${rel}"
    fi
  done
  if grep -E -q -- '-----BEGIN ([A-Z]+ )*PRIVATE KEY-----' "$file"; then
    fail "forbidden private-key block in ${rel}"
  fi
  if grep -E -q -i -- 'https?://[^[:space:]]*webhook' "$file"; then
    fail "forbidden webhook URL in ${rel}"
  fi
  if grep -F -q -- 'hooks.slack.com' "$file"; then
    fail "forbidden webhook URL in ${rel}"
  fi
  if grep -F -q -- 'discord.com/api/webhooks' "$file"; then
    fail "forbidden webhook URL in ${rel}"
  fi
  if grep -F -q -- 'discordapp.com/api/webhooks' "$file"; then
    fail "forbidden webhook URL in ${rel}"
  fi
done < <(find "$watch" -type f -print0)
