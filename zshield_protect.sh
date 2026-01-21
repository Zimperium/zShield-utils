#!/usr/bin/env bash
# zshield_protect.sh
# Upload files to zShield Pro, wait for protection, and download protected artifacts.
# Supports processing multiple files one by one.
# Usage: see --help or README in repo.

set -euo pipefail
# set -x

# Set nullglob option for compatibility with bash and zsh
if [[ -n "${BASH_VERSION:-}" ]]; then
    shopt -s nullglob
elif [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt null_glob
fi

export LC_ALL=C

SCRIPT_NAME="$(basename "$0")"

# Defaults
timeout_minutes=60
poll_interval_seconds=30
max_files=5
team_name="Default"
group_name="Default Group"

print() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
err() { print "ERROR: $*" >&2; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Options:
  --console-url URL           zShield console url (required or env console_url)
  --client-id ID              API client id (required or env client_id)
  --client-secret SECRET      API client secret (required or env client_secret)
  --app-file PATTERN          Glob pattern matching input files (required, max $max_files, extensions: .apk, .aab, .xcarchive)
  --team-name NAME            Team name (default: $team_name)
  --group-name NAME           Group name (default: $group_name)
  --protection-json-file FILE Protection JSON file (optional)
  --protection-json JSON      Protection JSON inline (optional)
  --output-file FILE          Output filename for downloaded artifact (optional)
  --timeout-minutes N         Wait timeout in minutes (default: $timeout_minutes)
  --poll-interval-seconds N   Poll interval seconds (default: $poll_interval_seconds)
  -h, --help                  Show this help

Environment fallback names: console_url, client_id, client_secret

Example:
  $SCRIPT_NAME --console-url https://ziap.zimperium.com --client-id abc --client-secret secret \
    --app-file "./build/*.apk" --team-name "My Team" --group-name "My Group" --output-file ./protected/

EOF
}

# Check if at least one parameter is supplied
if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --console-url) console_url="$2"; shift 2;;
    --client-id) client_id="$2"; shift 2;;
    --client-secret) client_secret="$2"; shift 2;;
    --app-file) app_file_pattern="$2"; shift 2;;
    --team-name) team_name="$2"; shift 2;;
    --group-name) group_name="$2"; shift 2;;
    --protection-json-file) protection_json_file="$2"; shift 2;;
    --protection-json) protection_json_inline="$2"; shift 2;;
    --output-file) output_file_input="$2"; shift 2;;
    --timeout-minutes) timeout_minutes="$2"; shift 2;;
    --poll-interval-seconds) poll_interval_seconds="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    --) shift; break;;
    *) err "Unknown arg: $1"; usage; exit 2;;
  esac
done

# Env fallbacks
: "${console_url:=${console_url:-${CONSOLE_URL:-${console_url:-}}}}"
: "${client_id:=${client_id:-${CLIENT_ID:-}}}"
: "${client_secret:=${client_secret:-${CLIENT_SECRET:-}}}"

# Validate presence
if [[ -z "${console_url:-}" || -z "${client_id:-}" || -z "${client_secret:-}" || -z "${app_file_pattern:-}" ]]; then
  err "Missing required parameter."
  usage
  exit 2
fi

# Tools
command -v curl >/dev/null 2>&1 || { err "curl is required"; exit 2; }
command -v jq >/dev/null 2>&1 || { err "jq is required. Install jq and retry."; exit 2; }

# Normalize URL
if ! [[ "$console_url" =~ ^https?:// ]]; then
  err "console_url must include scheme (https://...). Got: $console_url"
  exit 2
fi
base_url="${console_url%/}"

print "Starting zShield protect flow against ${base_url}"

# Utility: login -> get access token
login() {
  # print "Entering login function"
  print "Authenticating..."
  local resp
  resp=$(curl -sS -X POST "$base_url/api/auth/v1/api_keys/login" \
    -H 'Content-Type: application/json' \
    -d "{\"clientId\": \"$client_id\", \"secret\": \"$client_secret\"}") || {
    err "Authentication request failed"; return 1; }
  token=$(printf '%s' "$resp" | jq -r '.accessToken // empty') || true
  if [[ -z "$token" ]]; then
    err "Login failed: $resp"; return 1;
  fi
  print "Authentication successful"
  # print "Exiting login function"
  return 0
}

# Find matching files (glob)
find_matching_files() {
  # printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "Entering find_matching_files function" >&2
  # Set nullglob option for compatibility with bash and zsh
  if [[ -n "${BASH_VERSION:-}" ]]; then
    shopt -s nullglob
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt null_glob
  fi
  # allow patterns with quotes/wildcards passed through
  local pattern="$1"
  # expand pattern
  files=($pattern)
  local count=${#files[@]}
  if (( count == 0 )); then
    err "No files found matching pattern: $pattern"
    return 2
  fi
  if (( count > max_files )); then
    err "Pattern matched $count files, max is $max_files. Narrow the pattern."
    return 2
  fi
  # Filter files by extension
  local valid_files=()
  for f in "${files[@]}"; do
    if [[ "$f" =~ \.(apk|aab|xcarchive)$ ]]; then
      valid_files+=("$f")
    fi
  done
  if (( ${#valid_files[@]} == 0 )); then
    err "No valid files found. Files must have .apk, .aab, or .xcarchive extensions. Matched: ${files[*]}"
    return 2
  fi
  printf '%s\n' "${valid_files[@]}"
  # printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "Exiting find_matching_files function" >&2
}

# resolve team id by name
resolve_team_id() {
  print "Resolving team id for '$team_name'..."
  local resp
  resp=$(curl -sS -H "Authorization: Bearer $token" "$base_url/api/auth/public/v1/teams") || { err "Failed to list teams"; return 1; }
  # teams are in .content
  local team_id
  team_id=$(printf '%s' "$resp" | jq -r --arg NAME "$team_name" '.content[] | select(.name== $NAME) | .id' | head -n1 || true)
  if [[ -z "$team_id" ]]; then
    err "Team '$team_name' not found. Response: $resp"
    return 2
  fi
  print "Resolved team '$team_name' -> $team_id"
  echo "$team_id"
}

# resolve group id by name with team scoping
resolve_group_id() {
  # print "Entering resolve_group_id function"
  local tname="$1"; shift
  local tid="$1"; shift
  print "Resolving group id for '$tname' (team id: $tid)..."
  local read_flag='-a'
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    read_flag='-A'
  fi
  local resp
  resp=$(curl -sS -H "Authorization: Bearer $token" "$base_url/api/mtd-policy/public/v1/groups") || { err "Failed to list groups"; return 1; }
  # find matches
  local matches
  IFS=$'\n' read -r -d '' "$read_flag" matches < <(printf '%s' "$resp" | jq -c --arg NAME "$tname" '.[] | select(.name == $NAME)' && printf '\0')
  if [[ ${#matches[@]} -eq 0 ]]; then
    err "Group '$tname' not found."
    return 2
  fi
  # prefer team-scoped match
  for m in "${matches[@]}"; do
    local teamfield
    teamfield=$(printf '%s' "$m" | jq -r '.team.id // empty' || true)
    if [[ -n "$teamfield" && "$teamfield" == "$tid" ]]; then
      local gid
      gid=$(printf '%s' "$m" | jq -r '.id')
      print "Resolved team-scoped group '$tname' -> $gid"
      echo "$gid"; return 0
    fi
  done
  # try global
  local global_matches
  IFS=$'\n' read -r -d '' "$read_flag" global_matches < <(printf '%s' "$resp" | jq -c --arg NAME "$tname" '.[] | select(.name == $NAME and (.team == null))' && printf '\0')
  if [[ ${#global_matches[@]} -eq 1 ]]; then
    local gid
    gid=$(printf '%s' "${global_matches[0]}" | jq -r '.id')
    print "Resolved global group '$tname' -> $gid"
    echo "$gid"; return 0
  fi
  err "Ambiguous or inaccessible group '$tname' for team $tid"
  return 2
}

# build protection JSON
build_protection_request() {
  # print "Entering build_protection_request function"
  local teamId="$1"; local groupId="$2"
  if [[ -n "${protection_json_file:-}" ]]; then
    if [[ ! -f "$protection_json_file" ]]; then err "Protection JSON file not found: $protection_json_file"; return 2; fi
    local j
    j=$(cat "$protection_json_file")
  elif [[ -n "${protection_json_inline:-}" ]]; then
    local j
    j="$protection_json_inline"
  else
    # default as in JS
    j='{
      "description":"CI zShield Pro protection",
      "signatureVerification":false,
      "staticDexEncryption":true,
      "resourceEncryption":true,
      "metadataEncryption":true,
      "codeObfuscation":false,
      "runtimeProtection":true,
      "autoScanBuild":true
    }'
  fi
  # inject teamId and groupId
  printf '%s' "$j" | jq --arg tid "$teamId" --arg gid "$groupId" '. + {teamId: $tid, groupId: $gid}'
  # print "Exiting build_protection_request function"
}

# submit protection job
submit_protect() {
  # print "Entering submit_protect function"
  local file_path="$1"
  local req_json="$2"
  print "Submitting protection job for $file_path"
  # Use curl form upload
  local resp
  resp=$(curl -sS -X POST -H "Authorization: Bearer $token" \
    -F "file=@${file_path}" \
    -F "appProtectionRequest=${req_json};type=application/json" \
    "$base_url/api/zapp/public/v1/builds/protect") || { err "Submit protect request failed"; return 1; }
  local buildId
  buildId=$(printf '%s' "$resp" | jq -r '.buildId // empty' || true)
  if [[ -z "$buildId" ]]; then
    err "Protect response missing buildId: $resp"; return 2;
  fi
  print "Submitted, buildId=$buildId"
  echo "$buildId"
}

# get build status
get_build() {
  local id="$1"
  curl -sS -H "Authorization: Bearer $token" "$base_url/api/zapp/public/v1/builds/$id"
}

# poll until ready
poll_until_ready() {
  local id="$1"
  local start
  start=$(date +%s)
  local timeout=$(( timeout_minutes * 60 ))
  while true; do
    local now
    now=$(date +%s)
    if (( now - start > timeout )); then
      err "Timed out waiting for protected artifact after ${timeout_minutes} minutes."; return 2; fi

    local resp
    resp=$(get_build "$id") || { err "Failed to get build $id"; return 1; }
    local state
    state=$(printf '%s' "$resp" | jq -r '.state // empty')
    local protectedUrl
    protectedUrl=$(printf '%s' "$resp" | jq -r '.protectedUrl // empty')
    print "state=$state protectedUrl=${protectedUrl:+present}" 
    if [[ -n "$protectedUrl" && "$protectedUrl" != "null" ]]; then
      printf '%s' "$resp"
      return 0
    fi
    if [[ "$state" == "FAILED" || "$state" == "ERROR" ]]; then
      err "zShield build failed: $resp"; return 2;
    fi
    sleep "$poll_interval_seconds"
  done
}

# get protected signed URL
get_protected_link() {
  local id="$1"
  local resp
  resp=$(curl -sS -H "Authorization: Bearer $token" -H 'Accept: application/json' "$base_url/api/zapp/public/v1/builds/$id/protected") || { err "Failed to /protected"; return 1; }
  local url
  url=$(printf '%s' "$resp" | jq -r '.url // empty')
  if [[ -z "$url" ]]; then err "Unexpected /protected response: $resp"; return 2; fi
  printf '%s' "$resp"
}

# download signed URL
download_signed_url() {
  local signed_url="$1"
  local input_file="$2"
  local server_name="$3"
  local output_file="$4"
  print "Downloading protected artifact to $output_file"
  # download
  curl -sSL -f -o "$output_file" "$signed_url" || { err "Signed URL download failed"; return 2; }
  local size
  if [[ "$OSTYPE" == "darwin"* ]]; then
    size=$(stat -f%z "$output_file")
  else
    size=$(stat -c%s "$output_file")
  fi
  print "Download complete: $output_file ($size bytes)"
  # check magic PK
  local magic
  magic=$(head -c2 "$output_file" | xxd -p || true)
  if [[ "$magic" != "504b" ]]; then
    err "Downloaded file does not start with PK (zip). magic=$magic"
    return 2
  fi
  if (( size < 10000 )); then
    err "Downloaded file is unexpectedly small ($size bytes)"
    return 2
  fi
  echo "$output_file"
}

############################
# Main
############################

trap 'err "Script failed"' ERR

if ! login; then exit 3; fi

# find files
files=($(find_matching_files "$app_file_pattern")) || exit 3
print "Matched input files: ${files[*]}"

# Determine output handling
if (( ${#files[@]} == 1 )); then
  if [[ -n "${output_file_input:-}" ]]; then
    output_file="$output_file_input"
  else
    baseName=$(basename "${files[0]}" | sed 's/\.[^.]*$//')
    output_file="${baseName}_zshield_protected.apk"
  fi
else
  if [[ -n "${output_file_input:-}" ]]; then
    if [[ -d "$output_file_input" || "$output_file_input" =~ /$ ]]; then
      output_dir="${output_file_input%/}"
    else
      err "--output-file must be a directory when processing multiple files"
      exit 2
    fi
  else
    output_dir="."
  fi
fi

print "Resolving team id..."
team_id=$(resolve_team_id) || exit 3
print "Team id: $team_id"
print "Resolving group id..."
group_id=$(resolve_group_id "$group_name" "$team_id") || exit 3
print "Group id: $group_id"

protection_json=$(build_protection_request "$team_id" "$group_id") || exit 3

# Process each file
for file_path in "${files[@]}"; do
  print "Processing file: $file_path"

  if (( ${#files[@]} > 1 )); then
    baseName=$(basename "$file_path" | sed 's/\.[^.]*$//')
    output_file="${output_dir}/${baseName}_zshield_protected.apk"
  fi

  build_id=$(submit_protect "$file_path" "$protection_json") || exit 3
  print "Build id: $build_id"

  poll_resp=$(poll_until_ready "$build_id") || exit 3
  print "Build ready"

  protected_resp=$(get_protected_link "$build_id") || exit 3
  protected_url=$(printf '%s' "$protected_resp" | jq -r '.url')
  protected_name=$(printf '%s' "$protected_resp" | jq -r '.name // empty')

  print "Protected artifact name: ${protected_name:-<unknown>}"
  print "Protected artifact signed URL: ${protected_url:0:80}..."

  downloaded_path=$(download_signed_url "$protected_url" "$file_path" "$protected_name" "$output_file") || exit 3

  print "Finished processing $file_path. Protected file: $downloaded_path"

  # Outputs: print as KEY=VALUE lines for CI to capture
  echo "BUILD_ID=$build_id"
  echo "PROTECTED_URL=$protected_url"
  echo "PROTECTED_FILE=$downloaded_path"
done

exit 0
