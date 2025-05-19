#!/bin/bash
set -e

[ -z "$HY2_PORT" ] && HY2_PORT=23333
[ -z "$PASSWD" ] && PASSWD=$(cat /proc/sys/kernel/random/uuid)

if [[ $EUID -ne 0 ]]; then
  echo -e '\033[1;35m请以root权限运行脚本\033[0m'
  exit 1
fi

if [ -f /etc/alpine-release ]; then
  SYS="alpine"
else
  SYS=$(source /etc/os-release && echo $ID)
fi

case $SYS in
  debian|ubuntu) apt-get update && apt-get install -y curl wget openssl unzip ;;
  centos|rhel|oracle) yum install -y curl wget openssl unzip ;;
  fedora|rocky|almalinux) dnf install -y curl wget openssl unzip ;;
  alpine) apk add --no-cache curl wget openssl unzip ;;
  *) echo -e '\033[1;35m不支持的系统：'$SYS'\033[0m'; exit 1 ;;
esac

mkdir -p /etc/hysteria
ARCH=$(uname -m)
BIN_PATH="/usr/local/bin/hysteria"
[ ! -f "$BIN_PATH" ] && wget -O "$BIN_PATH" https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64 && chmod +x "$BIN_PATH"

openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
  -keyout /etc/hysteria/server.key \
  -out /etc/hysteria/server.crt \
  -subj "/CN=cloudflare.com" -days 36500

cat << EOF > /etc/hysteria/config.yaml
listen: :$HY2_PORT

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: "$PASSWD"

fastOpen: true

masquerade:
  type: proxy
  proxy:
    url: https://www.cloudflare.com
    rewriteHost: true

transport:
  udp:
    hopInterval: 30s
EOF

# 忽略sysctl失败避免脚本退出
sysctl -w net.core.rmem_max=16777216 2>/dev/null || true
sysctl -w net.core.wmem_max=16777216 2>/dev/null || true
sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null || true

# 创建 systemd 服务
if command -v systemctl >/dev/null 2>&1; then
cat << EOF > /etc/systemd/system/hysteria-server.service
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=$BIN_PATH server -c /etc/hysteria/config.yaml
Restart=always
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable hysteria-server || true
  systemctl restart hysteria-server
  sleep 1
else
  nohup $BIN_PATH server -c /etc/hysteria/config.yaml >/dev/null 2>&1 &
fi

# 获取IPv6优先地址
ipv6=$(curl -s --max-time 2 ipv6.ip.sb)
[ -n "$ipv6" ] && HOST_IP="[$ipv6]" || HOST_IP=$(curl -s --max-time 2 ipv4.ip.sb)
[ -z "$HOST_IP" ] && echo -e "\e[1;35m无法获取IP地址\033[0m" && exit 1

# 获取运营商信息
ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed 's/ /_/g')

# 输出节点信息
echo -e "\e[1;32mHysteria2 已启动，信息如下：\033[0m"
echo -e "\e[1;33mV2rayN / Nekobox:\033[0m"
echo -e "\e[1;32mhysteria2://$PASSWD@$HOST_IP:$HY2_PORT/?sni=www.cloudflare.com&alpn=h3&insecure=1#$ISP\033[0m"
echo ""
echo -e "\e[1;33mSurge:\033[0m"
echo -e "\e[1;32m$ISP = hysteria2, $HOST_IP, $HY2_PORT, password = $PASSWD, skip-cert-verify=true, sni=www.cloudflare.com\033[0m"
echo ""
echo -e "\e[1;33mClash:\033[0m"
cat << EOF
- name: $ISP
  type: hysteria2
  server: $HOST_IP
  port: $HY2_PORT
  password: $PASSWD
  alpn:
    - h3
  sni: www.cloudflare.com
  skip-cert-verify: true
  fast-open: true
EOF
