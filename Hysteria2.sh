#!/bin/bash
set -e

# ======== 环境变量初始化 ========
[ -z "$HY2_PORT" ] && HY2_PORT=23333
[ -z "$PASSWD" ] && PASSWD=$(cat /proc/sys/kernel/random/uuid)
[ -z "$VLESS_UUID" ] && VLESS_UUID=$(cat /proc/sys/kernel/random/uuid)
[ -z "$VLESS_WSPATH" ] && VLESS_WSPATH="/websocket"
ARGO_HOSTNAME="jp.wboo.qzz.io"
ARGO_TOKEN="eyJhIjoiMmI5NmIxMzY0MDI1ZDQ4NmNiYTIyOWViN2JkYmEzZmEiLCJ0IjoiMTM4YzdjNmItOTMzOS00M2FhLWE4OWQtNWVlNWUyNDM3MDY0IiwicyI6Ik9EVXdNemhtTURNdFl6STJaUzAwT1RJMUxXSmxaREV0WldFeU9ETm1aRGd3TWpNeSJ9"

# ======== 权限检测 ========
if [[ $EUID -ne 0 ]]; then
  echo -e '\033[1;35m请以root权限运行脚本\033[0m'
  exit 1
fi

# ======== 系统依赖 ========
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

# ======== 安装 Hysteria2 ========
mkdir -p /etc/hysteria
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

# ======== 调整内核参数 ========
sysctl -w net.core.rmem_max=16777216 || true
sysctl -w net.core.wmem_max=16777216 || true
sysctl -w net.ipv4.tcp_fastopen=3 || true

# ======== Hysteria2 systemd ========
cat << EOF > /etc/systemd/system/hysteria-server.service
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=always
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# ======== 安装 Sing-box + cloudflared ========
mkdir -p /etc/sing-box

if [ ! -f "/usr/local/bin/sing-box" ]; then
  curl -Ls -o singbox.tar.gz https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.tar.gz
  mkdir -p /tmp/sb && tar -xzf singbox.tar.gz -C /tmp/sb
  mv /tmp/sb/sing-box /usr/local/bin/sing-box
  chmod +x /usr/local/bin/sing-box
  rm -rf /tmp/sb singbox.tar.gz
fi

if [ ! -f "/usr/local/bin/cloudflared" ]; then
  wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x /usr/local/bin/cloudflared
fi

# ======== Sing-box 配置 (VLESS+WS) ========
cat << EOF > /etc/sing-box/config.json
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "vless",
      "listen": "127.0.0.1",
      "listen_port": 8080,
      "users": [
        { "uuid": "$VLESS_UUID" }
      ],
      "tls": { "enabled": false },
      "transport": {
        "type": "ws",
        "path": "$VLESS_WSPATH"
      }
    }
  ],
  "outbounds": [ { "type": "direct" } ]
}
EOF

# ======== systemd: sing-box ========
cat << EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-box VLESS+WS
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# ======== systemd: cloudflared ========
cat << EOF > /etc/systemd/system/cloudflared.service
[Unit]
Description=Cloudflared Argo Tunnel (固定)
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --edge-ip-version auto --protocol h2mux --no-autoupdate \
--hostname $ARGO_HOSTNAME \
--token $ARGO_TOKEN \
--url http://127.0.0.1:8080
Restart=always
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# ======== 启动所有服务 ========
systemctl daemon-reload
systemctl enable hysteria-server sing-box cloudflared
systemctl restart hysteria-server sing-box cloudflared

sleep 2
systemctl is-active --quiet hysteria-server || { echo -e "\033[1;31mHysteria 启动失败\033[0m"; journalctl -u hysteria-server --no-pager | tail -n 20; exit 1; }

# ======== 输出信息 ========
ipv4=$(curl -s ipv4.ip.sb)
[ -n "$ipv4" ] && HOST_IP="$ipv4" || HOST_IP=$(curl -s --max-time 1 ipv6.ip.sb)
[ -z "$HOST_IP" ] && echo -e "\e[1;35m无法获取IP地址\033[0m" && exit 1
ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed 's/ /_/g')

echo -e "\n\033[1;32mHysteria2 已启动：\033[0m"
echo -e "V2rayN/Nekobox:\n\033[1;33mhysteria2://$PASSWD@$HOST_IP:$HY2_PORT/?sni=www.cloudflare.com&alpn=h3&insecure=1#$ISP\033[0m"

echo -e "\n\033[1;32mVLESS + WS + Argo（固定隧道）已启动：\033[0m"
echo -e "V2rayN/Neko:\n\033[1;33mvless://$VLESS_UUID@$ARGO_HOSTNAME:443?encryption=none&security=tls&type=ws&host=$ARGO_HOSTNAME&path=$VLESS_WSPATH#Singbox-Argo\033[0m"
