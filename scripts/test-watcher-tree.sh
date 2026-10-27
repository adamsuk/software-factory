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
require_topic "env" "/workspace/factory-watch"
require_topic "env" "/workspace/factory-budget.json"
require_topic "env" "/workspace/factory-ledger.csv"
require_topic "env" "\`/workspace\`"
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
require_topic "constants" "committed constants"
require_topic "constants" "PVT_kwHOAYEAOs4Bo3vn"
require_topic "constants" "PVTSSF_lAHOAYEAOs4Bo3vnzhnV1ik"
require_topic "constants" "cdd562ca"
require_topic "constants" "84a24ea9"
require_topic "constants" "ed952d58"
require_topic "constants" "9cfe6bd1"
require_topic "constants" "befc9395"
require_topic "constants" "240a84ea"
require_topic "constants" "d53e0069"
require_topic "constants" "c59dd1a6"
require_topic "constants" "037f9c49"

# Fixed strings. The word token, a github.com URL, webhook.curl, a
# /workspace default, and touchlineHQ are not in this list.
fixed_needles=(
  'ghp_'
  'gho_'
  'github_pat_'
  '/home/'
  '/Users/'
  '[private reference redacted]'
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
