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

BLACKLIST_JSON="blacklist.json"
WHITELIST_JSON="whitelist.json"
DEVOPS_TXT="proxy_devops.txt"
SPEEDUP_TXT="proxy_speedup.txt"

update_domains() {
    local json_file="$1"
    local remarks="$2"
    local domains_json="$3"

    # 如果没有需要追加的域名则跳过
    [ -z "$domains_json" ] && return 0

    local tmp
    tmp=$(mktemp)
    jq --arg remarks "$remarks" --argjson newDomains "$domains_json" '
        map(
            if .remarks == $remarks then
                .domain = ((.domain // []) + $newDomains | unique)
            else
                .
            end
        )
    ' "$json_file" >"$tmp" && mv "$tmp" "$json_file"
}

build_domains_json() {
    local txt_file="$1"
    [ ! -f "$txt_file" ] && echo "[]" && return 0

    # 读取非空行，生成 JSON 数组
    jq -Rn '[inputs | select(length > 0)]' <"$txt_file"
}

log_info "proxy" "update DevOps domains from $DEVOPS_TXT"
DEVOPS_DOMAINS_JSON=$(build_domains_json "$DEVOPS_TXT")

log_info "proxy" "update SpeedUP domains from $SPEEDUP_TXT"
SPEEDUP_DOMAINS_JSON=$(build_domains_json "$SPEEDUP_TXT")

# 1. 读取 proxy_devops.txt 的内容
# 2. 将 读取的内容，每一行不为空的情况下，利用jq，追加到 blacklist.json 和 whitelist.json 中 的 remarks 为 "Proxy|DevOps" 的 domain 列表中
update_domains "$BLACKLIST_JSON" "Proxy|DevOps" "$DEVOPS_DOMAINS_JSON"
update_domains "$WHITELIST_JSON" "Proxy|DevOps" "$DEVOPS_DOMAINS_JSON"

# 1. 读取 proxy_speedup.txt 的内容
# 2. 将 读取的内容，每一行不为空的情况下，利用jq，追加到 blacklist.json 和 whitelist.json 中 的 remarks 为 "Proxy|SpeedUP" 的 domain 列表中
update_domains "$BLACKLIST_JSON" "Proxy|SpeedUP" "$SPEEDUP_DOMAINS_JSON"
update_domains "$WHITELIST_JSON" "Proxy|SpeedUP" "$SPEEDUP_DOMAINS_JSON"

log_info "proxy" "done"
