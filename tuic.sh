cat > deploy-tuic.sh << 'EOF'
#!/bin/bash
set -e

# —— 可自定义 —— 
PORT=${PORT:-3633}
UUID=$(cat /proc/sys/kernel/random/uuid)
PASSWORD=$(openssl rand -hex 16)
LOG_LEVEL="warn"

# —— 安装依赖 —— 
apt update -y
apt install -y curl wget jq openssl

# —— 下载 TUIC 执行文件 —— 
mkdir -p /root/tuic && cd /root/tuic
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
  FILE="tuic-server-1.0.0-x86_64-unknown-linux-gnu"
elif [ "$ARCH" = "aarch64" ]; then
  FILE="tuic-server-1.0.0-aarch64-unknown-linux-gnu"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi
wget -O tuic-server "https://github.com/tuic-protocol/tuic/releases/download/tuic-1.0.0/${FILE}"
chmod +x tuic-server

# —— 生成伪装 TLS 证书 —— 
openssl ecparam -genkey -name prime256v1 -out server.key
openssl req -new -x509 -key server.key -out server.crt -days 3650 \
  -subj "/CN=cdn.cloudflare.com"

# —— 自动探测 MTU —— 
IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
MTU=$(ip link show "$IFACE" | grep -oP 'mtu \K[0-9]+')
MTU=$((MTU - 40))

# —— 生成 config.json —— 
cat > config.json <<JSON
{
  "server": "[::]:$PORT",
  "users": {"$UUID":"$PASSWORD"},
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
  "heartbeat": {"enabled":true,"interval":15,"timeout":10},
  "log_level": "$LOG_LEVEL"
}
JSON

# —— 创建 systemd 服务 —— 
cat > /etc/systemd/system/tuic.service <<SERVICE
[Unit]
Description=TUIC v5 Server
After=network.target

[Service]
ExecStart=/root/tuic/tuic-server -c /root/tuic/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
SERVICE

# —— 启用 BBR 拥塞控制 —— 
sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr

# —— 启动服务 —— 
systemctl daemon-reload
systemctl enable tuic
systemctl restart tuic

# —— 输出结果 —— 
echo
echo "✅ TUIC Server 已启动！"
echo "地址: YOUR_DOMAIN:$PORT"
echo "UUID:   $UUID"
echo "密码:   $PASSWORD"
echo "ALPN:    h3 | SNI: disabled | Zero-RTT: enabled"
echo "MTU:     $MTU"
echo "TLS CN:  cdn.cloudflare.com"
echo
EOF
