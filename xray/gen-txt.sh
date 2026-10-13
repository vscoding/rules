#!/bin/bash
# shellcheck disable=SC2164,SC1090,SC2086
set -euo pipefail

TARGET_DIR=""
FORCE_INPUT_ARG=""
FORCE_BY_FLAG="n"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -f)
      FORCE_BY_FLAG="y"
      shift
      ;;
    y|Y|yes|YES|n|N|no|NO)
      FORCE_INPUT_ARG="$1"
      shift
      ;;
    *)
      if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$1"
      else
        FORCE_INPUT_ARG="$1"
      fi
      shift
      ;;
  esac
done

[ -z "$TARGET_DIR" ] && TARGET_DIR="$(pwd)"
TARGET_DIR=$(cd "$TARGET_DIR" && pwd)
cd "$TARGET_DIR"

[ -z $ROOT_URI ] && source <(curl -sSL https://dev.kubectl.org/init)
echo -e "\033[0;32mROOT_URI=$ROOT_URI\033[0m"

source <(curl -sSL $ROOT_URI/func/log.sh)
source <(curl -sSL $ROOT_URI/func/ostype.sh)

if is_windows; then
  log_info "build" "build in windows"
  export MSYS_NO_PATHCONV=1
fi

CONFIG_FILE="config.json"
JSON_DIR="jsons"
EXTRA_DIR="extra_domain"
FINAL_TXT="final_rules.txt"
PROXY_URL="http://127.0.0.1:10808"
CACHE_TTL_SECONDS=$((12 * 60 * 60))
FORCE_UPDATE="n"
CACHE_STATUS=""

download_rule_json() {
  local key="$1"
  local url="$2"
  local output_file="$3"
  local ts_file="$4"

  log_info "proxy" "download $key from $url"
  curl -fsSL --retry 3 --retry-delay 2 --proxy "$PROXY_URL" --url "$url" -o "$output_file"
  date +%s > "$ts_file"
}

should_download_json() {
  local json_file="$1"
  local ts_file="$2"

  if [ "$FORCE_UPDATE" = "y" ]; then
    CACHE_STATUS="forced"
    return 0
  fi

  if [ ! -s "$json_file" ]; then
    CACHE_STATUS="missing-json"
    return 0
  fi
  if [ ! -s "$ts_file" ]; then
    CACHE_STATUS="missing-timestamp"
    return 0
  fi

  local last_ts
  last_ts=$(tr -d '\r\n[:space:]' < "$ts_file")
  if [[ ! "$last_ts" =~ ^[0-9]+$ ]]; then
    CACHE_STATUS="invalid-timestamp"
    return 0
  fi

  local now_ts age_seconds
  now_ts=$(date +%s)
  age_seconds=$((now_ts - last_ts))
  if [ "$age_seconds" -gt "$CACHE_TTL_SECONDS" ]; then
    CACHE_STATUS="expired"
    return 0
  fi

  CACHE_STATUS="reused"
  return 1
}

generate_txt_from_json() {
  local key="$1"
  local json_file="$2"
  local txt_file="$3"

  log_info "proxy" "generate $txt_file from $json_file"
  {
    jq -r '(.rules // [])[]? | (.domain // [])[]? | "full:\(.)"' "$json_file"
    jq -r '(.rules // [])[]? | (.domain_suffix // [])[]? | "domain:\(.)"' "$json_file"
  } | awk 'NF && !seen[$0]++' > "$txt_file"

  log_info "proxy" "$key entries: $(wc -l < "$txt_file" | tr -d " ")"
}

generate_final_txt() {
  local tmp_file
  tmp_file=$(mktemp)

  local files=()
  for f in "$JSON_DIR"/*.txt; do
    [ -f "$f" ] && files+=("$f")
  done
  for f in "$EXTRA_DIR"/*.txt; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "extra_domains.txt" ] && continue
    files+=("$f")
  done

  if [ "${#files[@]}" -eq 0 ]; then
    : > "$FINAL_TXT"
    log_info "proxy" "no source txt files, generated empty $FINAL_TXT"
    return 0
  fi

  while IFS= read -r f; do
    cat "$f"
    echo
  done < <(printf '%s\n' "${files[@]}" | sort) | awk 'NF && !seen[$0]++' > "$tmp_file"

  mv "$tmp_file" "$FINAL_TXT"
  log_info "proxy" "generated $FINAL_TXT"
}

[ ! -f "$CONFIG_FILE" ] && {
  log_error "proxy" "missing $CONFIG_FILE"
  exit 1
}

mkdir -p "$JSON_DIR"
mkdir -p "$EXTRA_DIR"

if [ "$FORCE_BY_FLAG" = "y" ]; then
  FORCE_UPDATE="y"
  log_info "proxy" "force update enabled by -f"
else
  if [ -n "$FORCE_INPUT_ARG" ]; then
    force_input="$FORCE_INPUT_ARG"
  else
    read -r -p "force update? [y/N] " force_input || true
  fi
  force_input=${force_input:-n}
  force_input=${force_input,,}
  if [ "$force_input" = "y" ] || [ "$force_input" = "yes" ]; then
    FORCE_UPDATE="y"
  fi
fi

while IFS=$'\t' read -r key url; do
  key="${key//$'\r'/}"
  url="${url//$'\r'/}"
  [ -z "$key" ] && continue
  [ -z "$url" ] && {
    log_error "proxy" "empty url for key=$key"
    exit 1
  }

  json_file="$JSON_DIR/$key.json"
  ts_file="$JSON_DIR/$key.timestamp"
  txt_file="$JSON_DIR/$key.txt"

  if should_download_json "$json_file" "$ts_file"; then
    log_info "proxy" "cache status ($key): $CACHE_STATUS"
    download_rule_json "$key" "$url" "$json_file" "$ts_file"
    log_info "proxy" "cache status ($key): downloaded"
  else
    log_info "proxy" "cache status ($key): reused"
  fi

  generate_txt_from_json "$key" "$json_file" "$txt_file"
done < <(jq -r 'to_entries[] | "\(.key|gsub("^\\s+|\\s+$"; ""))\t\(.value|gsub("^\\s+|\\s+$"; ""))"' "$CONFIG_FILE")

generate_final_txt

log_info "proxy" "done ($TARGET_DIR)"
