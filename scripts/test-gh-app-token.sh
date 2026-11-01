#!/usr/bin/env bash
# Behaviour tests for scripts/gh-app-token.sh.
# A throwaway RSA key, a fake clock and a fake curl on PATH. No network,
# no real app key, and no ~/.config/gh.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper=$root/scripts/gh-app-token.sh

tname="startup"
fail() {
  printf 'FAIL (%s): %s\n' "$tname" "$*" >&2
  exit 1
}

[[ -f $helper ]] || fail "missing scripts/gh-app-token.sh"

tmpdir=$(mktemp -d)
inside=""
cleanup() {
  rm -rf "$tmpdir"
  if [[ -n $inside ]]; then
    rm -rf "$inside"
  fi
}
trap cleanup EXIT

# --- static: env, not hard-coded -------------------------------------------

tname="reads-env"
for name in FACTORY_GH_APP_ID FACTORY_GH_APP_INSTALLATION_ID FACTORY_GH_APP_KEY_FILE; do
  grep -q "$name" "$helper" || fail "helper does not reference $name"
done
if grep -E -q 'FACTORY_GH_APP_ID=[0-9]|FACTORY_GH_APP_INSTALLATION_ID=[0-9]' "$helper"; then
  fail "app or installation id is hard-coded"
fi
if grep -E -q '/app/installations/[0-9]+/' "$helper"; then
  fail "installation id is hard-coded in the token URL"
fi
# shellcheck disable=SC2016  # literal source text, not expansion
grep -F -q 'app/installations/${installation_id}/access_tokens' "$helper" \
  || fail "token URL is not built from the installation id"
if grep -E -q 'BEGIN [A-Z ]*PRIVATE KEY' "$helper"; then
  fail "private key embedded in the helper"
fi
if grep -F -q '.config/gh' "$helper"; then
  fail "helper touches gh config"
fi
if grep -q 'export GH_TOKEN' "$helper"; then
  fail "helper exports GH_TOKEN; the token must be stdout only"
fi

tname="call-sites"
for rel in scripts/run-work-order.sh scripts/watcher/watch.sh scripts/watcher/watch.new.sh; do
  grep -q 'gh-app-token.sh' "$root/$rel" || fail "$rel does not invoke gh-app-token.sh"
  grep -F -q 'env -u GH_TOKEN -u GITHUB_TOKEN' "$root/$rel" \
    || fail "$rel does not clear GH_TOKEN and GITHUB_TOKEN for grok"
done
grep -F -q 'env -u GH_TOKEN -u GITHUB_TOKEN grok' "$root/scripts/run-work-order.sh" \
  || fail "run-work-order grok invocation changed"
# shellcheck disable=SC2016  # literal source text, not expansion
grep -F -q 'timeout 40m env -u GH_TOKEN -u GITHUB_TOKEN "${grok_cmd[@]}"' \
  "$root/scripts/watcher/watch.sh" || fail "watch.sh grok invocation does not clear tokens"
# shellcheck disable=SC2016  # literal source text, not expansion
grep -F -q 'timeout 40m env -u GH_TOKEN -u GITHUB_TOKEN "${grok_cmd[@]}"' \
  "$root/scripts/watcher/watch.new.sh" || fail "watch.new.sh grok invocation does not clear tokens"
# shellcheck disable=SC2016  # literal source text, not expansion
merge_line='timeout 120 gh pr merge "$pr" -R "$repo" --squash --delete-branch --match-head-commit "$sha" || rc=$?'
grep -F -q "$merge_line" "$root/scripts/watcher/watch.sh" || fail "watch.sh merge command changed"
grep -F -q "$merge_line" "$root/scripts/watcher/watch.new.sh" || fail "watch.new.sh merge command changed"
grep -q 'merge: false' "$root/.github/factory.yml" || fail "agents.merge is not false"

# --- fakes ------------------------------------------------------------------

tname="fixtures"
mkdir -p "$tmpdir/bin" "$tmpdir/home" "$tmpdir/xdg" "$tmpdir/tmp" "$tmpdir/gh-config" "$tmpdir/calls"
export HOME=$tmpdir/home
export XDG_CACHE_HOME=$tmpdir/xdg
export TMPDIR=$tmpdir/tmp
export GH_CONFIG_DIR=$tmpdir/gh-config
export PATH="$tmpdir/bin:$PATH"
unset FACTORY_GH_APP_ID FACTORY_GH_APP_INSTALLATION_ID FACTORY_GH_APP_KEY_FILE || true
unset GH_TOKEN GITHUB_TOKEN || true

export FACTORY_GH_APP_NOW_FILE=$tmpdir/now
export FACTORY_GH_APP_CURL_DIR=$tmpdir/calls
export FACTORY_GH_APP_TOKEN_FILE=$tmpdir/token
export FACTORY_GH_APP_EXPIRES_FILE=$tmpdir/expires
export FACTORY_GH_APP_TOKEN_NEXT_FILE=$tmpdir/token.next
printf '0\n' > "$tmpdir/calls/count"

cat > "$tmpdir/bin/date" << 'EOF'
#!/bin/bash
if [[ $# -eq 1 && $1 == "+%s" ]]; then
  tr -cd '0-9' < "${FACTORY_GH_APP_NOW_FILE:?}"
  printf '\n'
  exit 0
fi
printf 'fake date: unexpected invocation: %s\n' "$*" >&2
exit 1
EOF

cat > "$tmpdir/bin/curl" << 'EOF'
#!/bin/bash
set -euo pipefail
out=""
args=("$@")
i=0
while (( i < ${#args[@]} )); do
  case "${args[$i]}" in
    --output|-o)
      i=$((i + 1))
      out=${args[$i]}
      ;;
  esac
  i=$((i + 1))
done
dir=${FACTORY_GH_APP_CURL_DIR:?}
count_file=$dir/count
n=0
if [[ -f $count_file ]]; then
  n=$(tr -cd '0-9' < "$count_file")
fi
n=$((n + 1))
printf '%s\n' "$n" > "$count_file"
mkdir -p "$dir/$n"
printf '%s\n' "$@" > "$dir/$n/args"
token=$(tr -cd 'A-Za-z0-9_.-' < "${FACTORY_GH_APP_TOKEN_FILE:?}")
expires=$(tr -d '[:space:]' < "${FACTORY_GH_APP_EXPIRES_FILE:?}")
if [[ -n $out ]]; then
  printf '{"token":"%s","expires_at":"%s"}\n' "$token" "$expires" > "$out"
fi
if [[ -f ${FACTORY_GH_APP_TOKEN_NEXT_FILE:-} ]]; then
  mv -f "$FACTORY_GH_APP_TOKEN_NEXT_FILE" "$FACTORY_GH_APP_TOKEN_FILE"
fi
printf '201'
EOF

cat > "$tmpdir/bin/gh" << 'EOF'
#!/bin/bash
printf 'gh was invoked\n' >&2
exit 99
EOF
chmod +x "$tmpdir/bin/date" "$tmpdir/bin/curl" "$tmpdir/bin/gh"

key=$tmpdir/app.pem
key_b=$tmpdir/other.pem
pub=$tmpdir/app.pub
pub_b=$tmpdir/other.pub
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$key" >/dev/null 2>&1
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$key_b" >/dev/null 2>&1
chmod 600 "$key" "$key_b"
openssl pkey -in "$key" -pubout -out "$pub" >/dev/null 2>&1
openssl pkey -in "$key_b" -pubout -out "$pub_b" >/dev/null 2>&1
pem_line=$(awk 'NR==2 { print; exit }' "$key")
[[ -n $pem_line ]] || fail "could not read a private-key line"

expires_at=2030-01-15T00:00:00Z
expires_epoch=$(python3 -c '
import datetime
import sys
value = sys.argv[1]
parsed = datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
parsed = parsed.replace(tzinfo=datetime.timezone.utc)
sys.stdout.write(str(int(parsed.timestamp())))
' "$expires_at")
[[ $expires_epoch =~ ^[0-9]+$ ]] || fail "could not compute expiry epoch"
printf '%s\n' "$expires_at" > "$tmpdir/expires"
printf '%s\n' "ghs_firsttoken" > "$tmpdir/token"
printf '%s\n' "ghs_secondtoken" > "$tmpdir/token.next"
printf '%s\n' "$((expires_epoch - 3600))" > "$tmpdir/now"

export FACTORY_GH_APP_ID=900195001
export FACTORY_GH_APP_INSTALLATION_ID=800195002
export FACTORY_GH_APP_KEY_FILE=$key

out=$tmpdir/stdout
err=$tmpdir/stderr

curl_count() {
  tr -cd '0-9' < "$tmpdir/calls/count"
}

b64url_decode() {
  local data=$1 pad padded i
  pad=$(((4 - ${#data} % 4) % 4))
  padded=$data
  for ((i = 0; i < pad; i++)); do
    padded="${padded}="
  done
  printf '%s' "$padded" | tr '_-' '/+' | openssl base64 -d -A
}

assert_no_secret() {
  local file=$1 token=$2
  if [[ -n $pem_line ]] && grep -F -q -- "$pem_line" "$file"; then
    fail "private key leaked in $file"
  fi
  if [[ -n $token ]] && grep -F -q -- "$token" "$file"; then
    fail "token leaked in $file"
  fi
}

assert_jwt() {
  local args=$1 want_iss=$2
  local auth jwt h p s sigfile input verify alg iss iat exp
  auth=$(grep -F 'Authorization: Bearer ' "$args" | head -n 1)
  [[ -n $auth ]] || fail "token request has no Authorization header"
  jwt=${auth#Authorization: Bearer }
  [[ $jwt == *.*.* ]] || fail "Authorization value is not a JWT"
  h=${jwt%%.*}
  s=${jwt##*.}
  p=${jwt#*.}
  p=${p%.*}
  sigfile=$tmpdir/sig.bin
  input=$tmpdir/signing.txt
  b64url_decode "$s" > "$sigfile"
  printf '%s' "${h}.${p}" > "$input"
  verify=$(openssl dgst -sha256 -verify "$pub" -signature "$sigfile" "$input")
  [[ $verify == "Verified OK" ]] || fail "JWT signature: $verify"
  if openssl dgst -sha256 -verify "$pub_b" -signature "$sigfile" "$input" >/dev/null 2>&1; then
    fail "JWT verified with a key that is not FACTORY_GH_APP_KEY_FILE"
  fi
  alg=$(b64url_decode "$h" | python3 -c 'import json,sys; print(json.load(sys.stdin)["alg"])')
  [[ $alg == "RS256" ]] || fail "alg is $alg"
  iss=$(b64url_decode "$p" | python3 -c 'import json,sys; print(json.load(sys.stdin)["iss"])')
  iat=$(b64url_decode "$p" | python3 -c 'import json,sys; print(json.load(sys.stdin)["iat"])')
  exp=$(b64url_decode "$p" | python3 -c 'import json,sys; print(json.load(sys.stdin)["exp"])')
  [[ $iss == "$want_iss" ]] || fail "iss is $iss, want $want_iss"
  (( exp > iat && exp - iat <= 600 )) || fail "exp-iat is $((exp - iat))"
  grep -F -x -q -- '--request' "$args" || fail "token request is not an explicit request"
  grep -F -x -q -- 'POST' "$args" || fail "token request is not POST"
  grep -F -x -q -- '--connect-timeout' "$args" || fail "token request has no connect timeout"
  [[ $(grep -F -A1 -x -- '--connect-timeout' "$args" | tail -n 1) == 10 ]] \
    || fail "connect timeout is not 10 seconds"
  grep -F -x -q -- '--max-time' "$args" || fail "token request has no max time"
  [[ $(grep -F -A1 -x -- '--max-time' "$args" | tail -n 1) == 30 ]] \
    || fail "max time is not 30 seconds"
  grep -F -x -q -- "https://api.github.com/app/installations/${FACTORY_GH_APP_INSTALLATION_ID}/access_tokens" "$args" \
    || fail "token URL does not use FACTORY_GH_APP_INSTALLATION_ID"
}

# --- mint -------------------------------------------------------------------

tname="mint"
status_before=$(git -C "$root" status --porcelain)
(
  cd "$root"
  bash "$helper" >"$out" 2>"$err"
)
status_after=$(git -C "$root" status --porcelain)
[[ $status_before == "$status_after" ]] || fail "helper changed the work tree"
[[ $(curl_count) == 1 ]] || fail "expected one token request, got $(curl_count)"
[[ $(tr -d '\n' < "$out") == "ghs_firsttoken" ]] || fail "stdout was not the installation token"
cmp -s "$out" <(printf '%s\n' "ghs_firsttoken") || fail "stdout was not exactly the token"
[[ ! -s $err ]] || fail "success path wrote to stderr"
assert_no_secret "$err" "ghs_firsttoken"
assert_jwt "$tmpdir/calls/1/args" "$FACTORY_GH_APP_ID"
[[ ! -e $HOME/.config/gh ]] || fail "helper used gh config"

cache=$XDG_CACHE_HOME/software-factory/installation-token
[[ -f $cache ]] || fail "cache file missing"
[[ $(stat -c '%a' "$cache") == 600 ]] || fail "cache mode is $(stat -c '%a' "$cache")"
repo_top=$(git -C "$root" rev-parse --show-toplevel)
case $cache in
  "$repo_top"|"$repo_top"/*) fail "cache is inside the repo: $cache" ;;
esac
if git -C "$root" ls-files --error-unmatch -- "$cache" >/dev/null 2>&1; then
  fail "cache is tracked by git"
fi
grep -F -x -q -- "ghs_firsttoken" "$cache" || fail "cache does not hold the token"
mapfile -t cache_files < <(find "$XDG_CACHE_HOME" -type f | sort)
[[ ${#cache_files[@]} -eq 1 && ${cache_files[0]} == "$cache" ]] || fail "unexpected cache files"

# A second id pair must show up in the JWT and the URL. Proves neither is fixed.
tname="ids-come-from-env"
rm -f "$cache"
printf '0\n' > "$tmpdir/calls/count"
rm -rf "$tmpdir/calls/1" "$tmpdir/calls/2" "$tmpdir/calls/3" "$tmpdir/calls/4"
export FACTORY_GH_APP_ID=900195003
export FACTORY_GH_APP_INSTALLATION_ID=800195004
printf '%s\n' "ghs_firsttoken" > "$tmpdir/token"
printf '%s\n' "ghs_secondtoken" > "$tmpdir/token.next"
bash "$helper" >"$out" 2>"$err"
assert_jwt "$tmpdir/calls/1/args" "900195003"
[[ $(tr -d '\n' < "$out") == "ghs_firsttoken" ]] || fail "second id pair did not mint"
export FACTORY_GH_APP_ID=900195001
export FACTORY_GH_APP_INSTALLATION_ID=800195002

# --- cache ------------------------------------------------------------------

tname="cache-hit"
# The second id pair wrote its own cache. Reset to the first installation's
# token and a clock well before expiry, then prove a repeat does not mint.
rm -rf "$XDG_CACHE_HOME/software-factory"
printf '0\n' > "$tmpdir/calls/count"
rm -rf "$tmpdir/calls/1" "$tmpdir/calls/2" "$tmpdir/calls/3" "$tmpdir/calls/4"
printf '%s\n' "$((expires_epoch - 3600))" > "$tmpdir/now"
printf '%s\n' "ghs_firsttoken" > "$tmpdir/token"
printf '%s\n' "ghs_secondtoken" > "$tmpdir/token.next"
bash "$helper" >"$out" 2>"$err"
[[ $(curl_count) == 1 ]] || fail "reset mint did not call curl"
bash "$helper" >"$out" 2>"$err"
[[ $(curl_count) == 1 ]] || fail "second invocation called the token endpoint"
[[ $(tr -d '\n' < "$out") == "ghs_firsttoken" ]] || fail "cache hit returned a new token"
[[ ! -s $err ]] || fail "cache hit wrote to stderr"
assert_no_secret "$err" "ghs_firsttoken"

tname="cache-before-boundary"
printf '%s\n' "$((expires_epoch - 301))" > "$tmpdir/now"
bash "$helper" >"$out" 2>"$err"
[[ $(curl_count) == 1 ]] || fail "invocation before expiry-5m called the token endpoint"
[[ $(tr -d '\n' < "$out") == "ghs_firsttoken" ]] || fail "early refresh returned a new token"

tname="cache-at-boundary"
printf '%s\n' "$((expires_epoch - 300))" > "$tmpdir/now"
bash "$helper" >"$out" 2>"$err"
[[ $(curl_count) == 2 ]] || fail "invocation at expiry-5m did not call the token endpoint, count=$(curl_count)"
[[ $(tr -d '\n' < "$out") == "ghs_secondtoken" ]] || fail "refresh did not return the new token"
[[ $(stat -c '%a' "$cache") == 600 ]] || fail "refreshed cache mode is $(stat -c '%a' "$cache")"
assert_no_secret "$err" "ghs_secondtoken"
assert_jwt "$tmpdir/calls/2/args" "$FACTORY_GH_APP_ID"

tname="cache-after-expiry"
printf '%s\n' "$expires_epoch" > "$tmpdir/now"
bash "$helper" >"$out" 2>"$err"
[[ $(curl_count) == 3 ]] || fail "invocation at expires_at did not call the token endpoint"

# --- missing configuration --------------------------------------------------

run_unset() {
  local drop=$1
  tname="unset-$drop"
  (
    unset "$drop"
    bash "$helper" >"$out" 2>"$err"
  )
  [[ ! -s $out ]] || fail "stdout was not empty"
  grep -i -q 'warning' "$err" || fail "stderr has no warning"
  assert_no_secret "$err" "ghs_firsttoken"
  assert_no_secret "$err" "ghs_secondtoken"
}

run_unset FACTORY_GH_APP_ID
run_unset FACTORY_GH_APP_INSTALLATION_ID
run_unset FACTORY_GH_APP_KEY_FILE

tname="missing-key"
(
  FACTORY_GH_APP_KEY_FILE=$tmpdir/no-such-key.pem
  export FACTORY_GH_APP_KEY_FILE
  bash "$helper" >"$out" 2>"$err"
)
[[ ! -s $out ]] || fail "stdout was not empty"
grep -i -q 'warning' "$err" || fail "stderr has no warning"

tname="key-is-directory"
(
  FACTORY_GH_APP_KEY_FILE=$tmpdir
  export FACTORY_GH_APP_KEY_FILE
  bash "$helper" >"$out" 2>"$err"
)
[[ ! -s $out ]] || fail "stdout was not empty"
grep -i -q 'warning' "$err" || fail "stderr has no warning"

tname="unreadable-key"
if [[ $(id -u) -ne 0 ]]; then
  bad=$tmpdir/noread.pem
  printf 'SENTINEL_KEY_MATERIAL_DO_NOT_LOG\n' > "$bad"
  chmod 000 "$bad"
  (
    FACTORY_GH_APP_KEY_FILE=$bad
    export FACTORY_GH_APP_KEY_FILE
    bash "$helper" >"$out" 2>"$err"
  )
  chmod 600 "$bad" || true
  [[ ! -s $out ]] || fail "stdout was not empty"
  grep -i -q 'warning' "$err" || fail "stderr has no warning"
  if grep -F -q 'SENTINEL_KEY_MATERIAL_DO_NOT_LOG' "$err"; then
    fail "unreadable key contents appeared on stderr"
  fi
fi

tname="bad-key-material"
bad=$tmpdir/bad.pem
printf 'SENTINEL_KEY_MATERIAL_DO_NOT_LOG\n' > "$bad"
chmod 600 "$bad"
count_before=$(curl_count)
(
  FACTORY_GH_APP_KEY_FILE=$bad
  export FACTORY_GH_APP_KEY_FILE
  bash "$helper" >"$out" 2>"$err"
)
[[ ! -s $out ]] || fail "stdout was not empty"
grep -i -q 'warning' "$err" || fail "stderr has no warning"
if grep -F -q 'SENTINEL_KEY_MATERIAL_DO_NOT_LOG' "$err"; then
  fail "private key material appeared on stderr"
fi
[[ $(curl_count) == "$count_before" ]] || fail "bad key still called the token endpoint"

# --- cache must stay outside the repo --------------------------------------

tname="cache-relocated"
inside=$root/.gh-app-cache-test-195
rm -rf "$inside"
mkdir -p "$inside"
(
  XDG_CACHE_HOME=$inside
  export XDG_CACHE_HOME
  bash "$helper" >"$out" 2>"$err"
)
if find "$inside" -type f | grep -q .; then
  fail "cache file written inside the repo"
fi
fallback="${TMPDIR}/software-factory-gh-app-${UID}/installation-token"
[[ -f $fallback ]] || fail "fallback cache missing"
[[ $(stat -c '%a' "$fallback") == 600 ]] || fail "fallback cache mode is $(stat -c '%a' "$fallback")"
case $fallback in
  "$repo_top"|"$repo_top"/*) fail "fallback cache is inside the repo" ;;
esac
rm -rf "$inside"
inside=""

# --- callers ----------------------------------------------------------------

check_caller_unset() {
  local script=$1
  tname="caller-unset-$(basename "$script")"
  # shellcheck disable=SC2016  # script runs in the child bash, not here
  timeout 30 bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    source "$1"
    GH_TOKEN=preset-token
    export GH_TOKEN
    unset FACTORY_GH_APP_ID
    apply_factory_gh_app_token
    if [[ -n ${GH_TOKEN+x} ]]; then
      printf "GH_TOKEN still set\n" >&2
      exit 1
    fi
  ' bash "$script" >"$out" 2>"$err"
  [[ ! -s $out ]] || fail "caller printed a token"
  grep -i -q 'warning' "$err" || fail "caller stderr has no warning"
  if grep -F -q 'preset-token' "$err"; then
    fail "preset token appeared on stderr"
  fi
  assert_no_secret "$err" "ghs_secondtoken"
}

check_caller_set() {
  local script=$1
  tname="caller-set-$(basename "$script")"
  # shellcheck disable=SC2016  # script runs in the child bash, not here
  timeout 30 bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    source "$1"
    unset GH_TOKEN
    apply_factory_gh_app_token
    if [[ ${GH_TOKEN:-} != "$EXPECTED_TOKEN" ]]; then
      printf "GH_TOKEN was not the installation token\n" >&2
      exit 1
    fi
    if env -u GH_TOKEN -u GITHUB_TOKEN env | grep -E -q "^(GH_TOKEN|GITHUB_TOKEN)="; then
      printf "token reached a cleared environment\n" >&2
      exit 1
    fi
  ' bash "$script" >"$out" 2>"$err"
  [[ ! -s $err ]] || fail "caller wrote a warning on the success path"
}

# The default cache still holds the token from the boundary refresh.
export EXPECTED_TOKEN=ghs_secondtoken
# Clock back into the fresh window so the cached token is reused.
printf '%s\n' "$((expires_epoch - 3600))" > "$tmpdir/now"

check_caller_set "$root/scripts/run-work-order.sh"
check_caller_set "$root/scripts/watcher/watch.sh"
check_caller_set "$root/scripts/watcher/watch.new.sh"
check_caller_unset "$root/scripts/run-work-order.sh"
check_caller_unset "$root/scripts/watcher/watch.sh"
check_caller_unset "$root/scripts/watcher/watch.new.sh"

tname="main-does-not-export"
# shellcheck disable=SC2016  # script runs in the child bash, not here
timeout 20 bash -c '
  set -euo pipefail
  # shellcheck disable=SC1090
  source "$1"
  main_src=$(declare -f main)
  case "$main_src" in
    *export\ GH_TOKEN*|*export\ GITHUB_TOKEN*) exit 1 ;;
  esac
  printf "%s\n" "$main_src" | grep -F -q "env -u GH_TOKEN -u GITHUB_TOKEN grok"
  printf "%s\n" "$main_src" | awk "/unset GH_TOKEN/ { saw = 1 } /prepare_env/ && saw { ok = 1 } END { exit !(ok) }"
  if printf "%s\n" "$main_src" | grep -E -q "unset[[:space:]]+GITHUB_TOKEN|unset[[:space:]]+GH_TOKEN[[:space:]]+GITHUB_TOKEN"; then
    exit 1
  fi
' bash "$root/scripts/run-work-order.sh" || fail "main exports a token or dropped the grok scrub"

tname="stateless-ghs"
# October 2026 ghs_ tokens are JWTs: dots, hyphens, and well past 255 characters.
# The fake curl must pass those characters through, and the cache must accept them.
rm -f "$cache"
printf '0\n' > "$tmpdir/calls/count"
rm -rf "$tmpdir/calls/1" "$tmpdir/calls/2" "$tmpdir/calls/3" "$tmpdir/calls/4"
printf '%s\n' "$((expires_epoch - 3600))" > "$tmpdir/now"
stateless="ghs_900195001_$(printf 'A%.0s' {1..180}).$(printf 'B%.0s' {1..180}).$(printf 'C%.0s' {1..80})-sig"
[[ ${#stateless} -gt 255 ]] || fail "fixture token is not past 255 characters"
[[ $stateless == *.* && $stateless == *-* ]] || fail "fixture token has no dot or hyphen"
printf '%s\n' "$stateless" > "$tmpdir/token"
rm -f "$tmpdir/token.next"
bash "$helper" >"$out" 2>"$err"
[[ $(tr -d '\n' < "$out") == "$stateless" ]] || fail "stateless token was dropped on mint"
cmp -s "$out" <(printf '%s\n' "$stateless") || fail "stdout was not exactly the stateless token"
[[ ! -s $err ]] || fail "stateless mint wrote to stderr"
assert_no_secret "$err" "$stateless"
assert_jwt "$tmpdir/calls/1/args" "$FACTORY_GH_APP_ID"
grep -F -x -q -- "$stateless" "$cache" || fail "cache does not hold the stateless token"
bash "$helper" >"$out" 2>"$err"
[[ $(curl_count) == 1 ]] || fail "stateless cache hit called the token endpoint"
[[ $(tr -d '\n' < "$out") == "$stateless" ]] || fail "stateless cache hit dropped the token"
[[ ! -s $err ]] || fail "stateless cache hit wrote to stderr"

tname="redact-ghs"
for rel in scripts/watcher/watch.sh scripts/watcher/watch.new.sh; do
  awk '
    /^redact\(\)/ { on = 1 }
    on { print }
    on && /^}/ { exit }
  ' "$root/$rel" > "$tmpdir/redact.sh"
  # shellcheck disable=SC1091
  source "$tmpdir/redact.sh"
  got=$(printf '%s\n' 'ghp_abc gho_def github_pat_zzz ghs_supersecrettoken' | redact)
  [[ $got == "[redacted] [redacted] [redacted] [redacted]" ]] \
    || fail "$rel redact: $got"
  got=$(printf '%s\n' "before ${stateless} after" | redact)
  [[ $got == "before [redacted] after" ]] || fail "$rel redact stateless: $got"
done

[[ ! -e $HOME/.config/gh ]] || fail "a test used gh config"
echo "ok  gh-app-token"
