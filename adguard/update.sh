#!/bin/bash
# shellcheck disable=SC1090 disable=SC2086 disable=SC2155 disable=SC2128 disable=SC2028 disable=SC2164
SHELL_FOLDER=$(cd "$(dirname "$0")" && pwd) && cd "$SHELL_FOLDER"
export ROOT_URI=https://dev.kubectl.org

source <(curl -sSL $ROOT_URI/func/log.sh)

export HTTP_PROXY=$(cat http_proxy.txt)

log_warn "prepare" "准备工作，清理临时目录 tmp"
rm -rf tmp

log_info "prepare" "创建临时目录 tmp"
mkdir -p tmp

log_info "dowload" "下载 AdGuard DNS 过滤规则 filter_1.txt"
curl -sSL https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt \
-x "$HTTP_PROXY" \
-o tmp/filter_1.txt

if [ -f tmp/filter_1.txt ]; then
  log_info "copy" "复制过滤规则到当前目录"
  cp -f tmp/filter_1.txt filter_1.txt
fi

log_info "dowload" "下载 AdGuard DNS 过滤规则 filter_2.txt"
curl -sSL https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt \
-x "$HTTP_PROXY" \
-o tmp/filter_2.txt

if [ -f tmp/filter_2.txt ]; then
  log_info "copy" "复制过滤规则到当前目录"
  cp -f tmp/filter_2.txt filter_2.txt
fi
