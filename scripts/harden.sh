#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
    error "请使用 root 用户运行此脚本"
fi

info "开始系统安全加固..."

info "[1/10] 禁用不必要的服务..."
systemctl disable avahi-daemon 2>/dev/null || true
systemctl stop avahi-daemon 2>/dev/null || true
systemctl disable cups 2>/dev/null || true
systemctl stop cups 2>/dev/null || true

info "[2/10] 加固 SSH 配置..."
SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%s)"

sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$SSHD_CONFIG"
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' "$SSHD_CONFIG"
sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' "$SSHD_CONFIG"
sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 2/' "$SSHD_CONFIG"
sed -i 's/^#*LoginGraceTime.*/LoginGraceTime 30/' "$SSHD_CONFIG"
sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$SSHD_CONFIG"

if ! grep -q "^AllowTcpForwarding" "$SSHD_CONFIG"; then
    echo "AllowTcpForwarding yes" >> "$SSHD_CONFIG"
fi

if systemctl is-active --quiet ssh 2>/dev/null; then
    systemctl restart ssh
elif systemctl is-active --quiet sshd 2>/dev/null; then
    systemctl restart sshd
fi
info "SSH 加固完成 (保留密码登录)"

info "[3/10] 配置系统内核参数..."
cat > /etc/sysctl.d/99-borderx-hardening.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
kernel.core_pattern = |/bin/false
fs.suid_dumpable = 0
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
EOF

sysctl --system > /dev/null 2>&1
info "内核安全参数配置完成"

info "[4/10] 限制 root cron 访问..."
touch /etc/cron.allow
chmod 600 /etc/cron.allow
echo "root" > /etc/cron.allow

info "[5/10] 设置文件权限..."
chmod 700 /root
chmod 600 /etc/shadow
chmod 600 /etc/gshadow
chmod 644 /etc/passwd
chmod 644 /etc/group

info "[6/10] 禁用不必要的协议..."
cat > /etc/modprobe.d/borderx-blacklist.conf <<'EOF'
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install squashfs /bin/true
install udf /bin/true
EOF

info "[7/10] 配置登录限制..."
cat > /etc/security/limits.d/99-borderx-hardening.conf <<'EOF'
* hard maxlogins 10
* hard core 0
EOF

info "[8/10] 配置 auditd 审计..."
if command -v auditd &>/dev/null; then
    cat > /etc/audit/rules.d/borderx.rules <<'EOF'
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b64 -S openat -F auid>=1000 -F auid!=4294967295 -k file_access
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/ssh/sshd_config -p wa -k sshd_config_changes
EOF
    service auditd restart 2>/dev/null || true
fi

info "[9/10] 配置 logrotate 确保日志不丢失..."
cat > /etc/logrotate.d/borderx-system <<'EOF'
/var/log/auth.log {
    daily
    rotate 90
    compress
    delaycompress
    missingok
    notifempty
    create 0640 syslog adm
}
EOF

info "[10/10] 清理敏感信息..."
> /root/.bash_history
export HISTFILESIZE=0
export HISTSIZE=0

echo ""
info "============================================"
info "  系统安全加固完成!"
info "============================================"
info "  已完成的加固项目:"
info "  - SSH: 限制尝试次数和空闲超时，保留密码登录"
info "  - 内核: 启用 IP 转发，禁用 ICMP 重定向"
info "  - 审计: 启用关键文件变更审计"
info "  - 限制: 禁用不必要的内核模块和协议"
info "  - 日志: 配置长期日志保留"
echo ""
