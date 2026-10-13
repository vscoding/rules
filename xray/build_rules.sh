#!/bin/bash
# shellcheck disable=SC2164,SC1090,SC2086,SC2288,SC2016,SC2215
set -euo pipefail

SHELL_FOLDER=$(cd "$(dirname "$0")" && pwd) && cd "$SHELL_FOLDER"
[ -z $ROOT_URI ] && source <(curl -sSL https://dev.kubectl.org/init)
echo -e "\033[0;32mROOT_URI=$ROOT_URI\033[0m"

source <(curl -sSL $ROOT_URI/func/log.sh)
source <(curl -sSL $ROOT_URI/func/ostype.sh)

if is_windows; then
  log_info "build" "build in windows"
  export MSYS_NO_PATHCONV=1
fi

BLACKLIST_TPL_JSON="tpl/blacklist_tpl.json"
WHITELIST_TPL_JSON="tpl/whitelist_tpl.json"
BLACKLIST_HK_TPL_JSON="tpl/blacklist_hk_tpl.json"

BLACKLIST_JSON="blacklist.json"
WHITELIST_JSON="whitelist.json"
BLACKLIST_HK_JSON="blacklist_hk.json"

DEVOPS_TXT="proxy_devops/final_rules.txt"
SPEEDUP_TXT="proxy_speedup/final_rules.txt"
DIRECT_CUSTOM_TXT="direct_custom/final_rules.txt"
OPENAI_TXT="proxy_devops/jsons/openai.txt"

build_domains_json() {
  local txt_file="$1"
  [ ! -f "$txt_file" ] && echo "[]" && return 0

  jq -Rn '[
      inputs
      | gsub("^\\s+|\\s+$"; "")
      | select(length > 0 and (test("^#") | not) and (test("^//") | not))
  ]' < "$txt_file"
}

run_gen_scripts() {
  local force_choice="$1"
  log_info "proxy" "run gen scripts with choice=$force_choice"

  bash direct_custom/gen-txt.sh "$force_choice"
  bash proxy_devops/gen-txt.sh "$force_choice"
  bash proxy_speedup/gen-txt.sh "$force_choice"
}

generate_main_rules() {
  log_info "proxy" "build domain json from generated final_rules.txt"
  local devops_domains_json
  local speedup_domains_json
  local direct_custom_domains_json

  devops_domains_json=$(build_domains_json "$DEVOPS_TXT")
  speedup_domains_json=$(build_domains_json "$SPEEDUP_TXT")
  direct_custom_domains_json=$(build_domains_json "$DIRECT_CUSTOM_TXT")

  log_info "proxy" "generate $BLACKLIST_JSON from $BLACKLIST_TPL_JSON"
  local tmp_blacklist
  tmp_blacklist=$(mktemp)
  jq \
    --argjson devops "$devops_domains_json" \
    --argjson speedup "$speedup_domains_json" \
    --argjson direct_custom "$direct_custom_domains_json" \
    '
      map(
        if .remarks == "Proxy|DevOps" then
          .domain = ((.domain // []) + $devops | unique)
        elif .remarks == "Proxy|SpeedUP" then
          .domain = ((.domain // []) + $speedup | unique)
        elif .remarks == "Direct|Custom" then
          .domain = ((.domain // []) + $direct_custom | unique)
        else
          .
        end
      )
    ' "$BLACKLIST_TPL_JSON" > "$tmp_blacklist" && mv "$tmp_blacklist" "$BLACKLIST_JSON"

  log_info "proxy" "generate $WHITELIST_JSON from $WHITELIST_TPL_JSON"
  local tmp_whitelist
  tmp_whitelist=$(mktemp)
  jq \
    --argjson devops "$devops_domains_json" \
    --argjson speedup "$speedup_domains_json" \
    --argjson direct_custom "$direct_custom_domains_json" \
    '
      map(
        if .remarks == "Proxy|DevOps" then
          .domain = ((.domain // []) + $devops | unique)
        elif .remarks == "Proxy|SpeedUP" then
          .domain = ((.domain // []) + $speedup | unique)
        elif .remarks == "Direct|Custom" then
          .domain = ((.domain // []) + $direct_custom | unique)
        else
          .
        end
      )
    ' "$WHITELIST_TPL_JSON" > "$tmp_whitelist" && mv "$tmp_whitelist" "$WHITELIST_JSON"
}

generate_hk_blacklist() {
  log_info "proxy" "build openai domains for hk blacklist from $OPENAI_TXT"
  local openai_domains_json
  openai_domains_json=$(build_domains_json "$OPENAI_TXT")

  log_info "proxy" "generate $BLACKLIST_HK_JSON from $BLACKLIST_HK_TPL_JSON"
  local tmp_blacklist_hk
  tmp_blacklist_hk=$(mktemp)
  jq \
    --argjson openai "$openai_domains_json" \
    '
      map(
        if .remarks == "Proxy|OpenAI" then
          .domain = ((.domain // []) + $openai | unique)
        else
          .
        end
      )
    ' "$BLACKLIST_HK_TPL_JSON" > "$tmp_blacklist_hk" && mv "$tmp_blacklist_hk" "$BLACKLIST_HK_JSON"
}

final_commit_and_push() {
  local commit_choice
  read -r -p "commit and push changes? [y/N] " commit_choice || true
  commit_choice=${commit_choice:-n}
  commit_choice=${commit_choice,,}

  if [ "$commit_choice" = "y" ] || [ "$commit_choice" = "yes" ]; then
    log_info "proxy" "commit flow: confirmed, start git add/commit/push"
    git add -A
    git commit -m "chore(rules): update"
    git push origin main
    log_info "proxy" "commit flow: done"
  else
    log_info "proxy" "commit flow: skipped by user, generated files kept locally"
  fi
}

force_choice="n"
read -r -p "force update generated json? [y/N] " force_input || true
force_input=${force_input:-n}
force_input=${force_input,,}
if [ "$force_input" = "y" ] || [ "$force_input" = "yes" ]; then
  force_choice="y"
fi

run_gen_scripts "$force_choice"
generate_main_rules
generate_hk_blacklist
log_info "proxy" "all rules generated"
log_info "proxy" "generated files: $BLACKLIST_JSON, $WHITELIST_JSON, $BLACKLIST_HK_JSON"

final_commit_and_push
