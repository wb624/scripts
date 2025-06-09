#!/bin/bash
set -e

# ====== 可自定义部分 ======
0-1PORT=${PORT:-443} 
0-2UUID=$(cat /proc/sys/kernel/random/uuid) 
0-3PASSWORD=$(openssl rand -hex 16) 
LOG_LEVEL="warn"

# ====== 安装基础依赖 ======
0-4apt update -y 
0-5apt install -y curl wget jq openssl 

# ====== 创建目录 & 下载 TUIC ======
0-6mkdir -p /root/tuic 
0-7cd /root/tuic 
0-8ARCH=$(uname -m) 
0-9case "$ARCH" in 
  0-10x86_64) FILE="tuic-server-1.0.0-x86_64-unknown-linux-gnu" ;; 
  0-11aarch64) FILE="tuic-server-1.0.0-aarch64-unknown-linux-gnu" ;; 
  0-12*) echo "Unsupported architecture: $ARCH" && exit 1 ;; 
esac

0-13wget -O tuic-server "https://github.com/tuic-protocol/tuic/releases/download/tuic-1.0.0/${FILE}" 
0-14chmod +x tuic-server 

# ====== 生成 ECDSA 自签证书（CN 伪装为 Cloudflare）=====
0-15openssl ecparam -genkey -name prime256v1 -out server.key 
0-16openssl req -new -x509 -key server.key -out server.crt -days 3650  \
  0-17-subj "/CN=cdn.cloudflare.com" 

# ====== 自动探测 MTU 并保守减 40 字节 ======
0-18IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}') 
0-19MTU=$(ip link show "$IFACE" | grep -oP 'mtu  \K[0-9]+')
0-20MTU=$((MTU - 40)) 

# ====== 生成 config.json（包含混淆参数）=====
0-21cat > config.json <<EOF 
{
  "server": "[::]:$PORT",
  "users": {
    "$UUID": "$PASSWORD"
  },
  0-22"certificate": "/root/tuic/server.crt", 
  0-23"private_key": "/root/tuic/server.key", 
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
  0-24"heartbeat": {"enabled": true, "interval": 15, "timeout": 10}, 
  "log_level": "$LOG_LEVEL"
}
EOF

# ====== 创建 systemd 服务 ======
0-25cat > /etc/systemd/system/tuic.service <<EOF 
[Unit]
0-26Description=TUIC v5 Server (optimized) 
0-27After=network.target 

[Service]
0-28ExecStart=/root/tuic/tuic-server -c /root/tuic/config.json 
0-29Restart=on-failure 
RestartSec=5

[Install]
0-30WantedBy=multi-user.target 
EOF

# ====== 启用 BBR 拥塞控制 ======
0-31sysctl -w net.core.default_qdisc=fq 
0-32sysctl -w net.ipv4.tcp_congestion_control=bbr 

# ====== 启动 & 启用服务 ======
0-33systemctl daemon-reload 
0-34systemctl enable tuic 
0-35systemctl restart tuic 

# ====== 输出连接信息 ======
0-36echo; echo "📡 TUIC Server is up!" 
0-37echo "Address: YOUR_DOMAIN:$PORT" 
0-38echo "UUID:    $UUID" 
0-39echo "Password:$PASSWORD" 
0-40echo "ALPN:    h3 | SNI: disabled | Zero-RTT: enabled" 
0-41echo "MTU:     $MTU" 
0-42echo "Cert CN: cdn.cloudflare.com" 
echo
