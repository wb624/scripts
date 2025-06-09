#!/bin/bash
set -e
0-2PORT=${PORT:-3633} 
0-3UUID=$(cat /proc/sys/kernel/random/uuid) 
0-4PASSWORD=$(openssl rand -hex 16) 
LOG_LEVEL="warn"
0-5apt update -y && apt install -y curl wget jq openssl 
0-6mkdir -p /root/tuic && cd /root/tuic 
0-7ARCH=$(uname -m) 
0-8if [ "$ARCH" = "x86_64" ]; then FILE="tuic-server-1.0.0-x86_64-unknown-linux-gnu"; fi 
0-9if [ "$ARCH" = "aarch64" ]; then FILE="tuic-server-1.0.0-aarch64-unknown-linux-gnu"; fi 
0-10wget -O tuic-server "https://github.com/tuic-protocol/tuic/releases/download/tuic-1.0.0/${FILE}" 
0-11chmod +x tuic-server 
0-12openssl ecparam -genkey -name prime256v1 -out server.key 
0-13openssl req -new -x509 -key server.key -out server.crt -days 3650 -subj "/CN=cdn.cloudflare.com" 
0-14IFACE=$(ip route get 1.1.1.1 | awk '{print $5;exit}') 
0-15MTU=$(ip link show "$IFACE" | grep -oP 'mtu  \K[0-9]+')
0-16MTU=$((MTU-40)) 
0-17cat > config.json <<EOF 
{
  "server": "[::]:$PORT",
  0-18"users": {"$UUID":"$PASSWORD"}, 
  0-19"certificate": "/root/tuic/server.crt", 
  0-20"private_key": "/root/tuic/server.key", 
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
  0-21"heartbeat": {"enabled":true,"interval":15,"timeout":10}, 
  "log_level": "$LOG_LEVEL"
}
EOF
0-22cat > /etc/systemd/system/tuic.service <<EOF 
[Unit]
0-23Description=TUIC v5 Server 
0-24After=network.target 

[Service]
0-25ExecStart=/root/tuic/tuic-server -c /root/tuic/config.json 
0-26Restart=on-failure 
RestartSec=5

[Install]
0-27WantedBy=multi-user.target 
EOF
0-28sysctl -w net.core.default_qdisc=fq 
0-29sysctl -w net.ipv4.tcp_congestion_control=bbr 
0-30systemctl daemon-reload 
0-31systemctl enable tuic 
0-32systemctl restart tuic 

echo
0-33echo "✅ TUIC Server 已启动！" 
0-34echo "地址: YOUR_DOMAIN:$PORT" 
0-35echo "UUID:   $UUID" 
0-36echo "密码:   $PASSWORD" 
0-37echo "ALPN:    h3 | SNI: disabled | Zero‑RTT: enabled" 
0-38echo "MTU:     $MTU" 
0-39echo "TLS CN:  cdn.cloudflare.com" 
echo
