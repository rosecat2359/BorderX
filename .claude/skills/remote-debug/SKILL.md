# Remote SSH Debug

通过 SSH 在远程服务器上直接执行诊断命令，无需用户手动复制粘贴。

## 触发条件

当以下任一情况发生时调用此技能：
- 用户说"帮我排查服务器问题"、"远程调试"、"服务器上有 bug"
- 之前给出的命令需要用户在服务器上执行，但往返多轮效率低
- 用户在远程服务器上部署了 BorderX 或相关服务

## 流程

### 1. 收集 SSH 信息

向用户一次性获取（如果尚未提供）：

```
我需要以下信息来 SSH 到你的服务器：
- IP 地址：?
- 端口：22（默认）
- 用户名：root（默认）
- 认证方式：密码 / SSH 密钥路径
```

### 2. 建立连接

使用 Bash 工具通过 sshpass 或原生 ssh 连接：

```bash
# 密码方式
sshpass -p '<password>' ssh -o StrictHostKeyChecking=no -p <port> <user>@<host> '<command>'

# 密钥方式
ssh -i <key_path> -o StrictHostKeyChecking=no -p <port> <user>@<host> '<command>'
```

### 3. 远程诊断

直接在远程服务器上执行命令，收集信息：

```bash
# 服务状态
systemctl status borderx-panel --no-pager -l
systemctl status nginx --no-pager -l
systemctl status postgresql --no-pager -l

# 日志
journalctl -u borderx-panel --no-pager -n 50

# 端口
ss -tlnp | grep -E ':80|:443|:8080|:5432'

# 进程
ps aux | grep borderx

# 系统资源
free -h && df -h / && uptime

# 配置
cat /etc/borderx/config.yml

# 直接测试 API
curl -s http://127.0.0.1:8080/
curl -s http://127.0.0.1:8080/api/admin/dashboard
```

### 4. 修复

在远程服务器上直接执行修复命令（拉取最新代码、重新编译、重启服务等）：

```bash
# 更新源码
cd /tmp && rm -rf BorderX && git clone --depth 1 https://github.com/<repo>.git BorderX

# 编译并替换
cd /tmp/BorderX/server && go build -o /opt/borderx/borderx-panel ./cmd/panel/

# 重启
systemctl restart borderx-panel
```

## 安全注意事项

- 每次执行命令前展示给用户确认
- 密码不会记录到日志中
- 避免执行破坏性命令（rm -rf /、DROP DATABASE 等）除非用户明确要求
- 连接结束后建议用户修改密码（如果使用了密码认证）
