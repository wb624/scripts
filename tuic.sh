#!/bin/bash
set -e

PORT=${PORT:-3633}
UUID=$(cat /proc/sys/kernel/random/uuid)
PASSWORD=$(openssl rand -hex 16)
LOG_LEVEL="warn"

apt update -y
apt install -y curl wget jq openssl

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

wget -q -O tuic-server "https://github.com/tuic-protocol/tuic/releases/download/tuic-1.0.0/${FILE}"
chmod +x tuic-server

openssl ecparam -genkey -name prime256v1 -out server.key
openssl req -new -x509 -key server.key -out server.crt -days 3650 -subj "/CN=cdn.cloudflare.com"

IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
MTU=$(ip link show "$IFACE" | grep -oP 'mtu \K[0-9]+'; echo 0)
MTU=$((MTU - 40))

cat > config.json <<EOF
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
EOF

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

sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr

systemctl daemon-reload
systemctl enable tuic
systemctl restart tuic

echo
echo "✅ TUIC Server 已启动！"
echo "地址: YOUR_DOMAIN:$PORT"
echo "UUID:   $UUID"
echo "密码:   $PASSWORD"
echo "ALPN:    h3 | SNI: disabled | Zero‑RTT: enabled"
echo "MTU:     $MTU"
echo "TLS CN:  cdn.cloudflare.com"
echo
