#!/bin/bash

set -e

# ===== 可自定义部分 =====
PORT=443
UUID=$(cat /proc/sys/kernel/random/uuid)
PASSWORD=$(openssl rand -hex 16)
LOG_LEVEL="warn"

# ===== 系统准备 =====
apt update -y && apt install -y curl wget unzip tar jq openssl

# ===== 下载 TUIC 可执行文件 =====
mkdir -p /root/tuic
cd /root/tuic

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_NAME="x86_64" ;;
  aarch64) ARCH_NAME="aarch64" ;;
  *) echo "Unsupported architecture: $ARCH" && exit 1 ;;
esac

LATEST_URL=$(curl -s https://api.github.com/repos/EAimTY/tuic/releases/latest | \
  jq -r '.assets[] | select(.name | test("linux-'$ARCH_NAME'.tar.gz$")) | .browser_download_url')

wget -O tuic.tar.gz "$LATEST_URL"
tar -xzf tuic.tar.gz
chmod +x tuic-server
rm tuic.tar.gz

# ===== 生成 ECDSA 证书（伪造为 cloudflare）=====
openssl ecparam -genkey -name prime256v1 -out server.key
openssl req -new -x509 -key server.key -out server.crt -days 3650 -subj "/CN=cdn.cloudflare.com"

# ===== 获取当前网卡 MTU 值并调整 =====
IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
MTU=$(ip link show "$IFACE" | grep -oP 'mtu \K[0-9]+')
MTU=$((MTU - 40))  # IPv6 常规头部开销

# ===== 写入 TUIC 配置文件 =====
cat > config.json <<EOF
{
  "server": "[::]:$PORT",
  "users": {
    "$UUID": "$PASSWORD"
  },
  "certificate": "/root/tuic/server.crt",
  "private_key": "/root/tuic/server.key",
  "congestion_control": "bbr",
  "alpn": ["h3"],
  "udp_relay_ipv6": true,
  "zero_rtt_handshake": true,
  "disable_sni": true,
  "dual_stack": true,
  "auth_timeout": "2s",
  "task_negotiation_timeout": "2s",
  "max_idle_time": "8s",
  "max_external_packet_size": $MTU,
  "gc_interval": "3s",
  "gc_lifetime": "10s",
  "heartbeat": {
    "enabled": true,
    "interval": 15,
    "timeout": 10
  },
  "log_level": "$LOG_LEVEL"
}
EOF

# ===== 写入 systemd 启动服务配置 =====
cat > /etc/systemd/system/tuic.service <<EOF
[Unit]
Description=TUIC Server
After=network.target

[Service]
Type=simple
ExecStart=/root/tuic/tuic-server -c /root/tuic/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# ===== 启用 BBR 拥塞控制器 =====
sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr

# ===== 启动 TUIC 服务 =====
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable tuic
systemctl start tuic

sleep 1
if systemctl is-active --quiet tuic; then
    echo -e "\e[1;32mTUIC 启动成功！\e[0m"
else
    echo -e "\e[1;31m启动失败，请运行 journalctl -u tuic 查看日志。\e[0m"
    exit 1
fi

# ===== 显示配置信息 =====
echo -e "\n====== TUIC 配置信息 ======"
echo "地址: YOUR_DOMAIN:$PORT"
echo "UUID: $UUID"
echo "密码: $PASSWORD"
echo "拥塞控制: bbr"
echo "ALPN: h3"
echo "Zero-RTT: 已启用"
echo "SNI: 已禁用"
echo "模拟 CN: cdn.cloudflare.com"
echo "最大MTU: $MTU"
echo "================================"
