#!/bin/bash
# shellcheck disable=SC2164,SC1090,SC2086
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
BLACKLIST_JSON="blacklist.json"
WHITELIST_JSON="whitelist.json"
DEVOPS_TXT="proxy_devops.txt"
SPEEDUP_TXT="proxy_speedup.txt"
DIRECT_CUSTOM_TXT="direct_custom.txt"

build_domains_json() {
  local txt_file="$1"
  [ ! -f "$txt_file" ] && echo "[]" && return 0

  # 读取非空行，去除首尾空白，并过滤掉以 # 或 // 开头的行，生成 JSON 数组
  jq -Rn '[
        inputs
        | gsub("^\\s+|\\s+$"; "")        # trim
        | select(
                length > 0                        # 非空
                and (test("^#") | not)          # 不以 # 开头
                and (test("^//") | not)         # 不以 // 开头
            )
    ]' <"$txt_file"
}

log_info "proxy" "update DevOps domains from $DEVOPS_TXT"
DEVOPS_DOMAINS_JSON=$(build_domains_json "$DEVOPS_TXT")

log_info "proxy" "update SpeedUP domains from $SPEEDUP_TXT"
SPEEDUP_DOMAINS_JSON=$(build_domains_json "$SPEEDUP_TXT")

log_info "proxy" "update Direct Custom domains from $DIRECT_CUSTOM_TXT"
DIRECT_CUSTOM_DOMAINS_JSON=$(build_domains_json "$DIRECT_CUSTOM_TXT")

# 基于模板 blacklist_tpl.json / whitelist_tpl.json 生成新的 JSON
# 不直接在原 JSON 上就地修改

log_info "proxy" "generate $BLACKLIST_JSON from $BLACKLIST_TPL_JSON"
tmp_blacklist=$(mktemp)
jq \
  --argjson devops "$DEVOPS_DOMAINS_JSON" \
  --argjson speedup "$SPEEDUP_DOMAINS_JSON" \
  --argjson direct_custom "$DIRECT_CUSTOM_DOMAINS_JSON" \
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
    ' "$BLACKLIST_TPL_JSON" >"$tmp_blacklist" && mv "$tmp_blacklist" "$BLACKLIST_JSON"

log_info "proxy" "generate $WHITELIST_JSON from $WHITELIST_TPL_JSON"
tmp_whitelist=$(mktemp)
jq \
  --argjson devops "$DEVOPS_DOMAINS_JSON" \
  --argjson speedup "$SPEEDUP_DOMAINS_JSON" \
  --argjson direct_custom "$DIRECT_CUSTOM_DOMAINS_JSON" \
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
    ' "$WHITELIST_TPL_JSON" >"$tmp_whitelist" && mv "$tmp_whitelist" "$WHITELIST_JSON"

log_info "proxy" "done"
