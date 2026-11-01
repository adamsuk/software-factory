#!/usr/bin/env bash
# Mint a GitHub App installation token for station gh and git push writes.
#
# Reads FACTORY_GH_APP_ID, FACTORY_GH_APP_INSTALLATION_ID and
# FACTORY_GH_APP_KEY_FILE from the environment. Signs a short RS256 JWT
# (exp at most 10 minutes after iat) and exchanges it at
# POST /app/installations/<id>/access_tokens. The token is the only stdout.
#
# The token is cached outside this repository, mode 0600, and reused until
# five minutes before expires_at. The private key and the token are never
# written to stderr.
#
# If any of the three values is missing, or the key file is not a readable
# regular file, print nothing and warn on stderr. The caller then leaves
# GH_TOKEN unset and keeps the current gh login.
set -euo pipefail
# A caller with xtrace must not echo the key or the token.
set +x
umask 077

warn() {
  printf 'gh-app-token: warning: %s\n' "$1" >&2
}

b64url() {
  openssl base64 -A 2>/dev/null | tr '+/' '-_' | tr -d '=\n\r'
}

now_epoch() {
  local now
  now=$(date +%s 2>/dev/null) || return 1
  [[ $now =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$now"
}

iso_to_epoch() {
  python3 -c '
import datetime
import sys
value = sys.argv[1]
parsed = None
for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ"):
    try:
        parsed = datetime.datetime.strptime(value, fmt)
        break
    except ValueError:
        parsed = None
if parsed is None:
    raise SystemExit(1)
parsed = parsed.replace(tzinfo=datetime.timezone.utc)
sys.stdout.write(str(int(parsed.timestamp())))
' "$1" 2>/dev/null
}

# 0 when $1 is the repo root or a path inside it.
in_repo() {
  local path=$1 root=$2
  [[ -n $root ]] || return 1
  case "$path" in
    "$root"|"$root"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Cache directory outside the work tree. XDG_CACHE_HOME (or $HOME/.cache)
# unless that would land inside the repo, in which case TMPDIR or /tmp.
cache_dir() {
  local root base
  root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n ${XDG_CACHE_HOME:-} ]]; then
    base="${XDG_CACHE_HOME}/software-factory"
  elif [[ -n ${HOME:-} ]]; then
    base="${HOME}/.cache/software-factory"
  else
    base="${TMPDIR:-/tmp}/software-factory-gh-app-${UID}"
  fi
  if in_repo "$base" "$root"; then
    base="${TMPDIR:-/tmp}/software-factory-gh-app-${UID}"
  fi
  if in_repo "$base" "$root"; then
    base="/tmp/software-factory-gh-app-${UID}"
  fi
  printf '%s\n' "$base"
}

# Opaque installation token. Legacy values are short [A-Za-z0-9_]. Stateless
# ghs_ tokens (October 2026) are JWTs: dots, hyphens, and well past 255 chars.
token_re='^[A-Za-z0-9._-]{8,}$'

# Print a cached token when it is still more than five minutes from expiry.
read_cached_token() {
  local file=$1 inst=$2 mode exp cached_inst cached_token now
  [[ -f $file ]] || return 1
  mode=$(stat -c '%a' "$file" 2>/dev/null || true)
  [[ $mode == 600 ]] || return 1
  exp=$(sed -n '1p' "$file" 2>/dev/null || true)
  cached_inst=$(sed -n '2p' "$file" 2>/dev/null || true)
  cached_token=$(sed -n '3p' "$file" 2>/dev/null || true)
  [[ $exp =~ ^[0-9]+$ ]] || return 1
  [[ $cached_inst == "$inst" ]] || return 1
  # Unquoted so the variable is a regex, not a literal string.
  [[ $cached_token =~ $token_re ]] || return 1
  now=$(now_epoch) || return 1
  if (( now < exp - 300 )); then
    printf '%s\n' "$cached_token"
    return 0
  fi
  return 1
}

write_cache() {
  local dir=$1 exp=$2 inst=$3 tok=$4 tmp
  mkdir -p "$dir" 2>/dev/null || return 0
  chmod 700 "$dir" 2>/dev/null || true
  tmp=$(mktemp "${dir}/.installation-token.XXXXXX" 2>/dev/null) || return 0
  if ! printf '%s\n%s\n%s\n' "$exp" "$inst" "$tok" > "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  chmod 600 "$tmp" 2>/dev/null || true
  if ! mv -f "$tmp" "${dir}/installation-token"; then
    rm -f "$tmp"
    return 0
  fi
  chmod 600 "${dir}/installation-token" 2>/dev/null || true
}

parse_token_json() {
  python3 -c '
import json
import sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(1)
token = data.get("token")
expires = data.get("expires_at")
if not isinstance(token, str) or not isinstance(expires, str):
    raise SystemExit(1)
if "\n" in token or "\r" in token or "\n" in expires or "\r" in expires:
    raise SystemExit(1)
sys.stdout.write(token + "\n" + expires + "\n")
' 2>/dev/null
}

mint_token() {
  local now iat exp header payload h_b64 p_b64 signing sig jwt url
  local body_file http json parsed token expires exp_epoch dir
  now=$(now_epoch) || {
    warn "could not read the clock; keeping the current gh login"
    exit 0
  }
  # iat is 60s in the past for clock skew. exp is exactly 10 minutes after iat,
  # which is under GitHub's "no more than 10 minutes from now" limit.
  iat=$((now - 60))
  exp=$((iat + 600))
  header='{"alg":"RS256","typ":"JWT"}'
  payload=$(printf '{"iat":%s,"exp":%s,"iss":"%s"}' "$iat" "$exp" "$app_id")
  h_b64=$(printf '%s' "$header" | b64url) || {
    warn "could not sign a GitHub App JWT; keeping the current gh login"
    exit 0
  }
  p_b64=$(printf '%s' "$payload" | b64url) || {
    warn "could not sign a GitHub App JWT; keeping the current gh login"
    exit 0
  }
  [[ -n $h_b64 && -n $p_b64 ]] || {
    warn "could not sign a GitHub App JWT; keeping the current gh login"
    exit 0
  }
  signing="${h_b64}.${p_b64}"
  sig=$(printf '%s' "$signing" | openssl dgst -sha256 -sign "$key_file" -binary 2>/dev/null | b64url) || {
    warn "could not sign a GitHub App JWT; keeping the current gh login"
    exit 0
  }
  [[ -n $sig ]] || {
    warn "could not sign a GitHub App JWT; keeping the current gh login"
    exit 0
  }
  jwt="${signing}.${sig}"
  url="https://api.github.com/app/installations/${installation_id}/access_tokens"
  body_file=$(mktemp 2>/dev/null) || {
    warn "could not reach the GitHub App installation token endpoint; keeping the current gh login"
    exit 0
  }
  http=$(curl \
    --silent \
    --show-error \
    --connect-timeout 10 \
    --max-time 30 \
    --request POST \
    --header "Accept: application/vnd.github+json" \
    --header "Authorization: Bearer ${jwt}" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    --output "$body_file" \
    --write-out '%{http_code}' \
    "$url" 2>/dev/null) || http=""
  if [[ $http != 201 && $http != 200 ]]; then
    rm -f "$body_file"
    warn "GitHub App installation token request was rejected; keeping the current gh login"
    exit 0
  fi
  json=$(cat "$body_file" 2>/dev/null || true)
  rm -f "$body_file"
  parsed=$(printf '%s' "$json" | parse_token_json) || {
    warn "GitHub App installation token response had no token; keeping the current gh login"
    exit 0
  }
  token=${parsed%%$'\n'*}
  expires=${parsed#*$'\n'}
  expires=${expires%%$'\n'*}
  unset json parsed
  # Unquoted so token_re is a regex, not a literal string.
  if [[ ! $token =~ $token_re ]]; then
    warn "GitHub App installation token response had no token; keeping the current gh login"
    exit 0
  fi
  exp_epoch=$(iso_to_epoch "$expires") || {
    warn "GitHub App installation token response had no expiry; keeping the current gh login"
    exit 0
  }
  [[ $exp_epoch =~ ^[0-9]+$ ]] || {
    warn "GitHub App installation token response had no expiry; keeping the current gh login"
    exit 0
  }
  dir=$(cache_dir)
  write_cache "$dir" "$exp_epoch" "$installation_id" "$token"
  printf '%s\n' "$token"
}

app_id=${FACTORY_GH_APP_ID:-}
installation_id=${FACTORY_GH_APP_INSTALLATION_ID:-}
key_file=${FACTORY_GH_APP_KEY_FILE:-}

if [[ -z $app_id ]]; then
  warn "FACTORY_GH_APP_ID is unset; keeping the current gh login"
  exit 0
fi
if [[ -z $installation_id ]]; then
  warn "FACTORY_GH_APP_INSTALLATION_ID is unset; keeping the current gh login"
  exit 0
fi
if [[ -z $key_file ]]; then
  warn "FACTORY_GH_APP_KEY_FILE is unset; keeping the current gh login"
  exit 0
fi
if [[ ! $app_id =~ ^[0-9]+$ ]]; then
  warn "FACTORY_GH_APP_ID is not an app id; keeping the current gh login"
  exit 0
fi
if [[ ! $installation_id =~ ^[0-9]+$ ]]; then
  warn "FACTORY_GH_APP_INSTALLATION_ID is not an installation id; keeping the current gh login"
  exit 0
fi
if [[ ! -f $key_file || ! -r $key_file ]]; then
  warn "GitHub App private key is not readable; keeping the current gh login"
  exit 0
fi

cache_file="$(cache_dir)/installation-token"
if cached=$(read_cached_token "$cache_file" "$installation_id"); then
  printf '%s\n' "$cached"
  exit 0
fi

mint_token
