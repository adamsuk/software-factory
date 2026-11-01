#!/usr/bin/env bash
# Mint a GitHub App installation token for station gh and git push writes.
#
# Reads FACTORY_GH_APP_ID, FACTORY_GH_APP_INSTALLATION_ID and
# FACTORY_GH_APP_KEY_FILE from the environment. Signs a short RS256 JWT
# (exp at most 10 minutes after iat) and exchanges it at
# POST /app/installations/<id>/access_tokens. The token is the only stdout.
#
#   gh-app-token.sh --slug
# prints only the app slug used for the bot login "<slug>[bot]". Order:
#   1. GH_APP_SLUG or FACTORY_GH_APP_SLUG in the environment
#   2. those names in the gh-app env file (FACTORY_GH_APP_ENV_FILE, else
#      gh-app.env beside FACTORY_GH_APP_KEY_FILE, else
#      $HOME/.factory-secrets/gh-app.env)
#   3. a slug cached beside the installation token
#   4. GET /app with the app JWT (never the installation token, never GET /user)
#   5. software-factory-line, and only as that last resort
# The slug cache is mode 0600 next to the token. Callers must not use the
# slug as a comment login unless an installation token was applied.
#
# The token is cached outside this repository, mode 0600, and reused until
# five minutes before expires_at. The private key, the JWT, and the token
# are never written to stdout or stderr.
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

# GitHub App slugs are letters, digits, and hyphens. The bot login is
# "<slug>[bot]". Dots and underscores are rejected so a token cannot be
# mistaken for a slug.
slug_re='^[A-Za-z0-9][A-Za-z0-9-]{0,98}$'
# Last resort when the slug is not configured and GET /app returns none.
# This factory's GitHub App. Not a comment login unless a token was applied.
default_app_slug=software-factory-line

slug_ok() {
  [[ ${1:-} =~ $slug_re ]]
}

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

trim_ws() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

# Print GH_APP_SLUG or FACTORY_GH_APP_SLUG from a KEY=VALUE file.
# The file is not sourced, so a value cannot run as shell.
read_slug_from_env_file() {
  local file=$1 line key val found_gh="" found_factory=""
  [[ -f $file && -r $file ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    case "$line" in
      ''|\#*) continue ;;
    esac
    [[ $line == *=* ]] || continue
    key=$(trim_ws "${line%%=*}")
    val=$(trim_ws "${line#*=}")
    if [[ $key == export\ * ]]; then
      key=$(trim_ws "${key#export }")
    fi
    if [[ $val == \"*\" ]]; then
      val=${val#\"}
      val=${val%\"}
    elif [[ $val == \'*\' ]]; then
      val=${val#\'}
      val=${val%\'}
    fi
    case "$key" in
      GH_APP_SLUG) found_gh=$val ;;
      FACTORY_GH_APP_SLUG) found_factory=$val ;;
    esac
  done < "$file"
  if slug_ok "$found_gh"; then
    printf '%s\n' "$found_gh"
    return 0
  fi
  if slug_ok "$found_factory"; then
    printf '%s\n' "$found_factory"
    return 0
  fi
  return 1
}

# gh-app.env beside the key, or the host file the factory already uses.
gh_app_env_file() {
  local candidate dir
  if [[ -n ${FACTORY_GH_APP_ENV_FILE:-} && -f $FACTORY_GH_APP_ENV_FILE ]]; then
    printf '%s\n' "$FACTORY_GH_APP_ENV_FILE"
    return 0
  fi
  if [[ -n ${FACTORY_GH_APP_KEY_FILE:-} ]]; then
    dir=$(dirname -- "$FACTORY_GH_APP_KEY_FILE")
    candidate="${dir}/gh-app.env"
    if [[ -f $candidate ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  if [[ -n ${HOME:-} && -f ${HOME}/.factory-secrets/gh-app.env ]]; then
    printf '%s\n' "${HOME}/.factory-secrets/gh-app.env"
    return 0
  fi
  return 1
}

configured_slug() {
  local slug="" file=""
  if slug_ok "${GH_APP_SLUG:-}"; then
    printf '%s\n' "$GH_APP_SLUG"
    return 0
  fi
  if slug_ok "${FACTORY_GH_APP_SLUG:-}"; then
    printf '%s\n' "$FACTORY_GH_APP_SLUG"
    return 0
  fi
  file=$(gh_app_env_file) || return 1
  slug=$(read_slug_from_env_file "$file") || return 1
  printf '%s\n' "$slug"
}

slug_cache_path() {
  printf '%s\n' "$(cache_dir)/app-slug"
}

read_cached_slug() {
  local file mode slug
  file=$(slug_cache_path)
  [[ -f $file ]] || return 1
  mode=$(stat -c '%a' "$file" 2>/dev/null || true)
  [[ $mode == 600 ]] || return 1
  slug=$(tr -d '[:space:]' < "$file" 2>/dev/null || true)
  slug_ok "$slug" || return 1
  printf '%s\n' "$slug"
}

write_cached_slug() {
  local slug=$1 dir file tmp
  slug_ok "$slug" || return 1
  dir=$(cache_dir)
  mkdir -p "$dir" 2>/dev/null || return 1
  chmod 700 "$dir" 2>/dev/null || true
  tmp=$(mktemp "${dir}/.app-slug.XXXXXX" 2>/dev/null) || return 1
  if ! printf '%s\n' "$slug" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chmod 600 "$tmp" 2>/dev/null || true
  file="${dir}/app-slug"
  if ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi
  chmod 600 "$file" 2>/dev/null || true
}

parse_app_slug() {
  python3 -c '
import json
import sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(1)
slug = data.get("slug")
if not isinstance(slug, str):
    raise SystemExit(1)
if slug == "" or "\n" in slug or "\r" in slug:
    raise SystemExit(1)
sys.stdout.write(slug)
' 2>/dev/null
}

# GET /app authenticates with the app JWT. The installation token is not
# sent, and the response body is never logged.
fetch_app_slug() {
  local jwt="" url body_file="" http="" slug=""
  [[ ${app_id:-} =~ ^[0-9]+$ ]] || return 1
  [[ -n ${key_file:-} && -f $key_file && -r $key_file ]] || return 1
  jwt=$(make_app_jwt) || return 1
  url="https://api.github.com/app"
  body_file=$(mktemp 2>/dev/null) || {
    unset jwt
    return 1
  }
  http=$(curl \
    --silent \
    --show-error \
    --connect-timeout 10 \
    --max-time 30 \
    --request GET \
    --header "Accept: application/vnd.github+json" \
    --header "Authorization: Bearer ${jwt}" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    --output "$body_file" \
    --write-out '%{http_code}' \
    "$url" 2>/dev/null) || http=""
  unset jwt
  if [[ $http != 200 ]]; then
    rm -f "$body_file"
    return 1
  fi
  slug=$(parse_app_slug < "$body_file") || {
    rm -f "$body_file"
    return 1
  }
  rm -f "$body_file"
  slug_ok "$slug" || return 1
  printf '%s\n' "$slug"
}

resolve_app_slug() {
  local slug=""
  if slug=$(configured_slug); then
    :
  elif slug=$(read_cached_slug); then
    :
  elif slug=$(fetch_app_slug); then
    write_cached_slug "$slug" || true
  else
    slug=$default_app_slug
  fi
  printf '%s\n' "$slug"
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

# Prints the app JWT. Callers capture it. It is not logged.
make_app_jwt() {
  local now iat exp header payload h_b64 p_b64 signing sig jwt
  now=$(now_epoch) || return 1
  # iat is 60s in the past for clock skew. exp is exactly 10 minutes after iat,
  # which is under GitHub's "no more than 10 minutes from now" limit.
  iat=$((now - 60))
  exp=$((iat + 600))
  header='{"alg":"RS256","typ":"JWT"}'
  payload=$(printf '{"iat":%s,"exp":%s,"iss":"%s"}' "$iat" "$exp" "$app_id")
  h_b64=$(printf '%s' "$header" | b64url) || return 1
  p_b64=$(printf '%s' "$payload" | b64url) || return 1
  [[ -n $h_b64 && -n $p_b64 ]] || return 1
  signing="${h_b64}.${p_b64}"
  sig=$(printf '%s' "$signing" | openssl dgst -sha256 -sign "$key_file" -binary 2>/dev/null | b64url) || return 1
  [[ -n $sig ]] || return 1
  jwt="${signing}.${sig}"
  printf '%s\n' "$jwt"
}

mint_token() {
  local jwt url body_file http json parsed token expires exp_epoch dir
  if ! now_epoch >/dev/null; then
    warn "could not read the clock; keeping the current gh login"
    exit 0
  fi
  jwt=$(make_app_jwt) || {
    warn "could not sign a GitHub App JWT; keeping the current gh login"
    exit 0
  }
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
  unset jwt
  printf '%s\n' "$token"
}

app_id=${FACTORY_GH_APP_ID:-}
installation_id=${FACTORY_GH_APP_INSTALLATION_ID:-}
key_file=${FACTORY_GH_APP_KEY_FILE:-}

# Slug only. Must run before the token path's early exits so a configured
# slug still prints when the caller asks for it. Stdout is the slug alone.
if [[ ${1:-} == --slug ]]; then
  resolve_app_slug
  exit 0
fi

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
