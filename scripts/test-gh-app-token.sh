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
unset GH_APP_SLUG FACTORY_GH_APP_SLUG FACTORY_GH_APP_ENV_FILE || true
unset FACTORY_GH_APP_SLUG_FILE FACTORY_GH_APP_APP_HTTP_FILE || true

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
url=""
args=("$@")
i=0
while (( i < ${#args[@]} )); do
  case "${args[$i]}" in
    --output|-o)
      i=$((i + 1))
      out=${args[$i]}
      ;;
    https://*)
      url=${args[$i]}
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
# GET /app returns the app slug. It must not be treated as a token mint.
if [[ $url == https://api.github.com/app ]]; then
  code=200
  if [[ -n ${FACTORY_GH_APP_APP_HTTP_FILE:-} && -f ${FACTORY_GH_APP_APP_HTTP_FILE} ]]; then
    code=$(tr -cd '0-9' < "$FACTORY_GH_APP_APP_HTTP_FILE")
  fi
  slug_value=software-factory-line
  if [[ -n ${FACTORY_GH_APP_SLUG_FILE:-} && -f ${FACTORY_GH_APP_SLUG_FILE} ]]; then
    slug_value=$(tr -cd 'A-Za-z0-9-' < "$FACTORY_GH_APP_SLUG_FILE")
  fi
  if [[ -n $out ]]; then
    if [[ $code == 200 ]]; then
      printf '{"slug":"%s"}\n' "$slug_value" > "$out"
    else
      printf '{}\n' > "$out"
    fi
  fi
  printf '%s' "$code"
  exit 0
fi
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

# Live watchers are a flat copy in $FACTORY_WATCH_ROOT. The helper sits beside
# that copy. The repo tree keeps it one directory up, at scripts/gh-app-token.sh.
# A file beside the script wins over ../gh-app-token.sh.
tname="watcher-helper-locations"
for rel in scripts/watcher/watch.sh scripts/watcher/watch.new.sh; do
  # shellcheck disable=SC2016  # literal source text, not expansion
  grep -F -q 'The .early step must also stage gh-app-token.sh in $FACTORY_WATCH_ROOT.' \
    "$root/$rel" || fail "$rel missing .early helper note"
  base=$(basename "$rel")
  deploy=$tmpdir/deploy-$base
  rm -rf "$deploy"
  mkdir -p "$deploy"
  cp "$root/$rel" "$deploy/$base"
  printf '%s\n' '#!/bin/bash' 'printf "beside-token\n"' > "$deploy/gh-app-token.sh"
  parent_helper=$tmpdir/gh-app-token.sh
  printf '%s\n' '#!/bin/bash' 'printf "parent-token\n"' > "$parent_helper"
  # shellcheck disable=SC2016  # script runs in the child bash, not here
  timeout 30 bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    source "$1"
    unset GH_TOKEN
    apply_factory_gh_app_token
    [[ ${GH_TOKEN:-} == beside-token ]]
    rm -f "$2"
    unset GH_TOKEN
    apply_factory_gh_app_token
    [[ ${GH_TOKEN:-} == parent-token ]]
    rm -f "$3"
    apply_factory_gh_app_token
    [[ -z ${GH_TOKEN+x} ]]
  ' bash "$deploy/$base" "$deploy/gh-app-token.sh" "$parent_helper" >"$out" 2>"$err" \
    || fail "$rel helper lookup failed"
  missing_warns=$(awk 'BEGIN { c = 0 } /token helper is missing/ { c++ } END { print c }' "$err")
  [[ $missing_warns -eq 1 ]] || fail "$rel missing-helper warning count: $missing_warns"
  if grep -F -q 'beside-token' "$err" || grep -F -q 'parent-token' "$err"; then
    fail "$rel wrote a token to stderr"
  fi
  rm -rf "$deploy"
  rm -f "$parent_helper"
done

# factory_login must not call GET /user while GH_TOKEN is an installation
# token. cycle() resolves the login before the token is applied. A
# FACTORY_LOGIN that is already set is returned as-is and is not replaced
# by GET /user.
tname="factory-login"
login_root=$tmpdir/login-root
rm -rf "$login_root"
mkdir -p "$login_root/bin" "$login_root/home" "$login_root/watch"
cat > "$login_root/bin/gh" << 'EOF'
#!/bin/bash
log=${FACTORY_LOGIN_GH_LOG:?}
if [[ -n ${GH_TOKEN+x} ]]; then
  if [[ $GH_TOKEN == ghs_* ]]; then
    printf 'GH_TOKEN=installation\n' >> "$log"
    printf 'gh saw an installation token\n' >&2
    exit 97
  fi
  printf 'GH_TOKEN=set\n' >> "$log"
else
  printf 'GH_TOKEN=<unset>\n' >> "$log"
fi
printf 'args=%s\n' "$*" >> "$log"
if [[ ${1:-} == api && ${2:-} == user ]]; then
  printf '%s\n' '{"login":"station-user"}'
  exit 0
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 99
EOF
chmod +x "$login_root/bin/gh"
: > "$login_root/gh.log"

for rel in scripts/watcher/watch.sh scripts/watcher/watch.new.sh; do
  awk '
    /^cycle\(\)/ { in_fn = 1; next }
    in_fn && /^}/ { exit }
    in_fn && /resolve_factory_login/ && !resolve_line { resolve_line = NR }
    in_fn && /apply_factory_gh_app_token/ && !apply_line { apply_line = NR }
    END {
      if (!resolve_line || !apply_line || resolve_line >= apply_line) exit 1
    }
  ' "$root/$rel" || fail "$rel applies the installation token before resolving the factory login"

  for mode in preset refuse before capture; do
    tname="factory-login-${mode}-$(basename "$rel")"
    : > "$login_root/gh.log"
    # shellcheck disable=SC2016  # script runs in the child bash, not here
    timeout 30 bash -c '
      set -euo pipefail
      export PATH="$1:$PATH"
      export FACTORY_WATCH_ROOT="$2"
      export FACTORY_LOGIN_GH_LOG="$3"
      export HOME="$4"
      export GH_CONFIG_DIR="$4/gh-config"
      mkdir -p "$HOME" "$GH_CONFIG_DIR" "$FACTORY_WATCH_ROOT"
      mode=$5
      script=$6
      case "$mode" in
        preset)
          export FACTORY_LOGIN="app-slug[bot]"
          export GH_TOKEN=ghs_shouldnotbeused
          # shellcheck disable=SC1090
          source "$script"
          [[ $FACTORY_LOGIN == "app-slug[bot]" ]]
          got=$(factory_login)
          [[ $got == "app-slug[bot]" ]]
          [[ ! -s $FACTORY_LOGIN_GH_LOG ]]
          [[ $GH_TOKEN == ghs_shouldnotbeused ]]
          ;;
        refuse)
          unset FACTORY_LOGIN
          export GH_TOKEN=ghs_shouldnotbeused
          # shellcheck disable=SC1090
          source "$script"
          [[ -z ${FACTORY_LOGIN:-} ]]
          if factory_login; then
            printf "factory_login called GET /user with an installation token\n" >&2
            exit 1
          fi
          [[ -z ${FACTORY_LOGIN:-} ]]
          [[ ! -s $FACTORY_LOGIN_GH_LOG ]]
          [[ $GH_TOKEN == ghs_shouldnotbeused ]]
          ;;
        before)
          unset FACTORY_LOGIN
          unset GH_TOKEN
          # shellcheck disable=SC1090
          source "$script"
          # Not a command substitution: that subshell would drop FACTORY_LOGIN.
          factory_login >"$FACTORY_WATCH_ROOT/login.out"
          [[ $FACTORY_LOGIN == station-user ]]
          [[ $(<"$FACTORY_WATCH_ROOT/login.out") == station-user ]]
          export GH_TOKEN=ghs_shouldnotbeused
          factory_login >"$FACTORY_WATCH_ROOT/login.out"
          [[ $(<"$FACTORY_WATCH_ROOT/login.out") == station-user ]]
          [[ $(awk "END { print NR }" "$FACTORY_LOGIN_GH_LOG") == 2 ]]
          grep -F -q "GH_TOKEN=<unset>" "$FACTORY_LOGIN_GH_LOG"
          grep -F -q "args=api user" "$FACTORY_LOGIN_GH_LOG"
          if grep -F -q "GH_TOKEN=installation" "$FACTORY_LOGIN_GH_LOG"; then
            printf "GET /user ran with the installation token\n" >&2
            exit 1
          fi
          ;;
        capture)
          unset FACTORY_LOGIN
          export GH_TOKEN=ghs_shouldnotbeused
          # shellcheck disable=SC1090
          source "$script"
          resolve_factory_login
          [[ $FACTORY_LOGIN == station-user ]]
          [[ $GH_TOKEN == ghs_shouldnotbeused ]]
          grep -F -q "GH_TOKEN=<unset>" "$FACTORY_LOGIN_GH_LOG"
          grep -F -q "args=api user" "$FACTORY_LOGIN_GH_LOG"
          if grep -F -q "GH_TOKEN=installation" "$FACTORY_LOGIN_GH_LOG"; then
            printf "GET /user ran with the installation token\n" >&2
            exit 1
          fi
          lines=$(awk "END { print NR }" "$FACTORY_LOGIN_GH_LOG")
          resolve_factory_login
          got=$(factory_login)
          [[ $got == station-user ]]
          [[ $(awk "END { print NR }" "$FACTORY_LOGIN_GH_LOG") == "$lines" ]]
          ;;
        *)
          printf "unknown mode %s\n" "$mode" >&2
          exit 1
          ;;
      esac
    ' bash "$login_root/bin" "$login_root/watch" "$login_root/gh.log" "$login_root/home" "$mode" "$root/$rel" \
      || fail "$rel factory login ($mode)"
  done
done
# App token in use: independent-review matching uses <slug>[bot], even when
# FACTORY_LOGIN was preset. Preset with no app token: that preset login.
# No app and no preset: the station login is unchanged.
# Slug is derived (env, gh-app env file, GET /app), not hard-coded.
tname="slug-from-env"
unset GH_APP_SLUG FACTORY_GH_APP_SLUG FACTORY_GH_APP_ENV_FILE || true
# Beside the installation-token cache. Do not read XDG_CACHE_HOME here:
# a subshell above points it at a throwaway directory.
slug_cache=${cache%/*}/app-slug
rm -f "$slug_cache" "$tmpdir/gh-app.env"
printf '%s\n' 'from-github-app' > "$tmpdir/slug-body"
export FACTORY_GH_APP_SLUG_FILE=$tmpdir/slug-body
slug_count=$(curl_count)
GH_APP_SLUG=cfg-slug bash "$helper" --slug >"$out" 2>"$err"
[[ $(tr -d '\n' < "$out") == cfg-slug ]] || fail "GH_APP_SLUG was not the slug"
[[ ! -s $err ]] || fail "configured slug wrote to stderr"
[[ $(curl_count) == "$slug_count" ]] || fail "GH_APP_SLUG called GitHub"
unset GH_APP_SLUG

tname="slug-from-factory-env"
FACTORY_GH_APP_SLUG=factory-cfg-slug bash "$helper" --slug >"$out" 2>"$err"
[[ $(tr -d '\n' < "$out") == factory-cfg-slug ]] || fail "FACTORY_GH_APP_SLUG was not the slug"
[[ $(curl_count) == "$slug_count" ]] || fail "FACTORY_GH_APP_SLUG called GitHub"
unset FACTORY_GH_APP_SLUG

tname="slug-from-env-file"
# Sibling of FACTORY_GH_APP_KEY_FILE. Same file the host already uses.
printf '%s\n' 'FACTORY_GH_APP_ID=1' 'export GH_APP_SLUG="file-slug"' > "$tmpdir/gh-app.env"
bash "$helper" --slug >"$out" 2>"$err"
[[ $(tr -d '\n' < "$out") == file-slug ]] || fail "gh-app.env slug was $(tr -d '\n' < "$out")"
[[ $(curl_count) == "$slug_count" ]] || fail "env file slug called GitHub"
[[ ! -s $err ]] || fail "env file slug wrote to stderr"
if grep -F -q 'FACTORY_GH_APP_ID=1' "$out" "$err"; then
  fail "env file contents leaked"
fi
rm -f "$tmpdir/gh-app.env"

tname="slug-env-beats-file"
printf '%s\n' 'GH_APP_SLUG=file-slug' > "$tmpdir/gh-app.env"
GH_APP_SLUG=cfg-slug bash "$helper" --slug >"$out" 2>"$err"
[[ $(tr -d '\n' < "$out") == cfg-slug ]] || fail "env slug did not beat the env file"
rm -f "$tmpdir/gh-app.env"
unset GH_APP_SLUG

tname="slug-from-github"
rm -f "$slug_cache"
bash "$helper" --slug >"$out" 2>"$err"
[[ $(tr -d '\n' < "$out") == from-github-app ]] || fail "GET /app slug was $(tr -d '\n' < "$out")"
[[ $(curl_count) == $((slug_count + 1)) ]] || fail "GET /app was not one call"
[[ ! -s $err ]] || fail "GET /app wrote to stderr"
[[ -f $slug_cache ]] || fail "slug cache missing"
[[ $(stat -c '%a' "$slug_cache") == 600 ]] || fail "slug cache mode is $(stat -c '%a' "$slug_cache")"
grep -F -x -q -- 'from-github-app' "$slug_cache" || fail "slug cache contents"
app_args=$tmpdir/calls/$((slug_count + 1))/args
grep -F -x -q -- 'https://api.github.com/app' "$app_args" || fail "slug URL is not GET /app"
grep -F -x -q -- 'GET' "$app_args" || fail "slug request is not GET"
if grep -F -q 'access_tokens' "$app_args"; then
  fail "slug request hit the installation token endpoint"
fi
if grep -F -q 'Authorization:' "$err"; then
  fail "JWT header on stderr"
fi
assert_no_secret "$err" ""
assert_no_secret "$out" ""
assert_no_secret "$slug_cache" ""
# Cached slug does not mint again, and the token stdout stays the token.
bash "$helper" --slug >"$out" 2>"$err"
[[ $(curl_count) == $((slug_count + 1)) ]] || fail "cached slug called GitHub"
[[ $(tr -d '\n' < "$out") == from-github-app ]] || fail "cached slug changed"
bash "$helper" >"$out" 2>"$err"
token_now=$(tr -d '\n' < "$out")
[[ $token_now == ghs_* ]] || fail "token stdout changed while resolving the slug"
[[ $token_now != from-github-app ]] || fail "token stdout was the slug"
if grep -F -q -- "$token_now" "$slug_cache"; then
  fail "installation token stored in the slug cache"
fi
if grep -F -q -- "$pem_line" "$slug_cache"; then
  fail "private key stored in the slug cache"
fi

tname="slug-fallback"
printf '500\n' > "$tmpdir/app-http"
export FACTORY_GH_APP_APP_HTTP_FILE=$tmpdir/app-http
rm -f "$slug_cache"
bash "$helper" --slug >"$out" 2>"$err"
[[ $(tr -d '\n' < "$out") == software-factory-line ]] || fail "fallback slug was $(tr -d '\n' < "$out")"
[[ ! -s $err ]] || fail "slug fallback wrote to stderr"
[[ ! -e $slug_cache ]] || fail "fallback slug was cached"
unset FACTORY_GH_APP_APP_HTTP_FILE
rm -f "$tmpdir/app-http"
# Restore a real slug so the watcher match is not the hard-coded default.
rm -f "$slug_cache"
printf '%s\n' 'gate-bot-slug' > "$tmpdir/slug-body"

for rel in scripts/watcher/watch.sh scripts/watcher/watch.new.sh; do
  # shellcheck disable=SC2016  # literal source text, not expansion
  grep -F -q 'bash "$helper" --slug' "$root/$rel" \
    || fail "$rel does not ask the helper for the app slug"
  for mode in app preset-app preset-noapp noapp; do
    tname="review-login-${mode}-$(basename "$rel")"
    : > "$login_root/gh.log"
    # shellcheck disable=SC2016  # script runs in the child bash, not here
    timeout 40 bash -c '
      set -euo pipefail
      export PATH="$1:$PATH"
      export FACTORY_WATCH_ROOT="$2"
      export FACTORY_LOGIN_GH_LOG="$3"
      export HOME="$4"
      export GH_CONFIG_DIR="$4/gh-config"
      mkdir -p "$HOME" "$GH_CONFIG_DIR" "$FACTORY_WATCH_ROOT"
      mode=$5
      script=$6
      case "$mode" in
        app)
          unset FACTORY_LOGIN
          unset GH_TOKEN
          # shellcheck disable=SC1090
          source "$script"
          resolve_factory_login
          apply_factory_gh_app_token
          got=$(factory_login)
          [[ $got == "gate-bot-slug[bot]" ]]
          [[ $FACTORY_LOGIN == "gate-bot-slug[bot]" ]]
          [[ $GH_TOKEN == ghs_* ]]
          if grep -F -q "GH_TOKEN=installation" "$FACTORY_LOGIN_GH_LOG"; then
            printf "GET /user ran with the installation token\n" >&2
            exit 1
          fi
          lines=$(awk "END { print NR }" "$FACTORY_LOGIN_GH_LOG")
          got=$(factory_login)
          [[ $got == "gate-bot-slug[bot]" ]]
          [[ $(awk "END { print NR }" "$FACTORY_LOGIN_GH_LOG") == "$lines" ]]
          ;;
        preset-app)
          export FACTORY_LOGIN=kept-login
          unset GH_TOKEN
          # shellcheck disable=SC1090
          source "$script"
          resolve_factory_login
          apply_factory_gh_app_token
          got=$(factory_login)
          [[ $got == "gate-bot-slug[bot]" ]]
          [[ $FACTORY_LOGIN == "gate-bot-slug[bot]" ]]
          [[ $GH_TOKEN == ghs_* ]]
          [[ ! -s $FACTORY_LOGIN_GH_LOG ]]
          if grep -F -q "GH_TOKEN=installation" "$FACTORY_LOGIN_GH_LOG"; then
            printf "GET /user ran with the installation token\n" >&2
            exit 1
          fi
          lines=$(awk "END { print NR }" "$FACTORY_LOGIN_GH_LOG")
          got=$(factory_login)
          [[ $got == "gate-bot-slug[bot]" ]]
          [[ $(awk "END { print NR }" "$FACTORY_LOGIN_GH_LOG") == "$lines" ]]
          # Token refresh failed: no token, so the preset login applies again.
          unset FACTORY_GH_APP_ID
          apply_factory_gh_app_token
          got=$(factory_login)
          [[ $got == kept-login ]]
          [[ $FACTORY_LOGIN == kept-login ]]
          [[ -z ${GH_TOKEN+x} ]]
          [[ $(awk "END { print NR }" "$FACTORY_LOGIN_GH_LOG") == "$lines" ]]
          if grep -F -q "GH_TOKEN=installation" "$FACTORY_LOGIN_GH_LOG"; then
            printf "GET /user ran with the installation token\n" >&2
            exit 1
          fi
          ;;
        preset-noapp)
          export FACTORY_LOGIN=kept-login
          unset GH_TOKEN
          unset FACTORY_GH_APP_ID
          # shellcheck disable=SC1090
          source "$script"
          resolve_factory_login
          apply_factory_gh_app_token
          got=$(factory_login)
          [[ $got == kept-login ]]
          [[ $FACTORY_LOGIN == kept-login ]]
          [[ -z ${GH_TOKEN+x} ]]
          [[ ! -s $FACTORY_LOGIN_GH_LOG ]]
          if grep -F -q "GH_TOKEN=installation" "$FACTORY_LOGIN_GH_LOG"; then
            printf "GET /user ran with the installation token\n" >&2
            exit 1
          fi
          ;;
        noapp)
          unset FACTORY_LOGIN
          unset GH_TOKEN
          unset FACTORY_GH_APP_ID
          # shellcheck disable=SC1090
          source "$script"
          resolve_factory_login
          apply_factory_gh_app_token
          got=$(factory_login)
          [[ $got == station-user ]]
          [[ $FACTORY_LOGIN == station-user ]]
          [[ -z ${GH_TOKEN+x} ]]
          grep -F -q "GH_TOKEN=<unset>" "$FACTORY_LOGIN_GH_LOG"
          grep -F -q "args=api user" "$FACTORY_LOGIN_GH_LOG"
          if grep -F -q "GH_TOKEN=installation" "$FACTORY_LOGIN_GH_LOG"; then
            printf "GET /user ran with the installation token\n" >&2
            exit 1
          fi
          ;;
        *)
          printf "unknown mode %s\n" "$mode" >&2
          exit 1
          ;;
      esac
    ' bash "$login_root/bin" "$login_root/watch" "$login_root/gh.log" "$login_root/home" "$mode" "$root/$rel" \
      >"$out" 2>"$err" || fail "$rel review login ($mode)"
    if [[ -n $pem_line ]] && grep -F -q -- "$pem_line" "$out" "$err"; then
      fail "$rel review login ($mode) leaked the private key"
    fi
    if grep -F -q 'Authorization:' "$out" "$err"; then
      fail "$rel review login ($mode) leaked a JWT"
    fi
  done
done
rm -rf "$login_root"

[[ ! -e $HOME/.config/gh ]] || fail "a test used gh config"
echo "ok  gh-app-token"
