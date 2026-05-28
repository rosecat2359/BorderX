#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# BorderX DNS 修复脚本
# 修复 Xray DNS 配置，解决外网访问问题
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CONFIG="/usr/local/etc/xray/config.json"

if [[ ! -f "$CONFIG" ]]; then
    echo "配置文件 $CONFIG 不存在"
    exit 1
fi

# 备份
cp "$CONFIG" "${CONFIG}.bak.$(date +%s)"
echo -e "${GREEN}[1/4] 已备份配置${NC}"

# 修复 DNS：localhost 优先，UDP DNS 和国内 DoH 备用
echo -e "${GREEN}[2/4] 注入可靠 DNS 配置...${NC}"
jq '
    .dns = {
        "servers": [
            "localhost",
            "tcp+local://8.8.8.8",
            "tcp+local://1.1.1.1",
            "https+local://dns.alidns.com/dns-query",
            "https+local://doh.pub/dns-query"
        ],
        "queryStrategy": "UseIPv4",
        "disableFallback": false
    }
' "$CONFIG" > "${CONFIG}.new" && mv "${CONFIG}.new" "$CONFIG"
echo "  localhost → TCP 8.8.8.8 / 1.1.1.1 → DoH 阿里 / DNSPod"

# 修复 outbound domainStrategy
echo -e "${GREEN}[3/4] 确保 IPv4 优先...${NC}"
jq '(.outbounds[] | select(.tag == "direct") | .settings) |= . + {"domainStrategy": "UseIPv4"}' \
    "$CONFIG" > "${CONFIG}.new" && mv "${CONFIG}.new" "$CONFIG"

# 修复日志级别（none → warning）
echo -e "${GREEN}[4/4] 修复日志级别...${NC}"
CURRENT_LOG=$(jq -r '.log.loglevel' "$CONFIG")
if [[ "$CURRENT_LOG" == "none" ]]; then
    jq '.log.loglevel = "warning"' "$CONFIG" > "${CONFIG}.new" && mv "${CONFIG}.new" "$CONFIG"
    echo "  日志: none → warning"
else
    echo "  日志: $CURRENT_LOG (无需修改)"
fi

systemctl restart xray && echo -e "${GREEN}完成，Xray 已重启${NC}" || echo -e "${YELLOW}重启失败，请检查: journalctl -u xray${NC}"
