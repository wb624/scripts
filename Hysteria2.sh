#!/bin/bash

set -e

# 随机生成端口和密码
[ -z "$HY2_PORT" ] && HY2_PORT=$(shuf -i 2000-65000 -n 1)
[ -z "$PASSWD" ] && PASSWD=$(cat /proc/sys/kernel/random/uuid)

# 检查是否为root
if [[ $EUID -ne 0 ]]; then
  echo -e '\033[1;35m请以root权限运行脚本\033[0m'
  exit 1
fi

# 检测系统类型
if [ -f /etc/alpine-release ]; then
  SYSTEM="alpine"
else
  SYSTEM=$(source /etc/os-release && echo $ID)
fi

case $SYSTEM in
  debian|ubuntu)
    apt-get update && apt-get install -y curl wget openssl unzip
    ;;
  centos|rhel|oracle)
    yum install -y curl wget openssl unzip
    ;;
  fedora|rocky|almalinux)
    dnf install -y curl wget openssl unzip
    ;;
  alpine)
    apk add --no-cache curl wget openssl unzip
    ;;
  *)
    echo -e '\033[1;35m暂不支持的系统类型：'$SYSTEM'\033[0m'
    exit 1
    ;;
esac

# 创建配置目录
mkdir -p /etc/hysteria

# 下载 Hysteria2 可执行文件（适用于 x86_64）
ARCH=$(uname -m)
BIN_PATH="/usr/local/bin/hysteria"

if [ ! -f "$BIN_PATH" ]; then
  echo -e "\033[1;33m正在下载 Hysteria 可执行文件...\033[0m"
  wget -O "$BIN_PATH" https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64
  chmod +x "$BIN_PATH"
fi

# 创建自签证书
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
  -keyout /etc/hysteria/server.key \
  -out /etc/hysteria/server.crt \
  -subj "/CN=bing.com" -days 36500

chown root:root /etc/hysteria/server.key /etc/hysteria/server.crt

# 写入配置文件
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
    url: https://bing.com
    rewriteHost: true

transport:
  udp:
    hopInterval: 30s
EOF

# 写入 systemd 服务文件
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

# 重新加载并启动服务
systemctl daemon-reload
systemctl enable hysteria-server
systemctl restart hysteria-server

# 验证是否成功运行
sleep 1
if ! systemctl is-active --quiet hysteria-server; then
  echo -e "\033[1;31m服务启动失败，请检查配置或日志。\033[0m"
  journalctl -u hysteria-server --no-pager | tail -n 20
  exit 1
fi

# 获取公网IP
ipv4=$(curl -s ipv4.ip.sb)
if [ -n "$ipv4" ]; then
    HOST_IP="$ipv4"
else
    ipv6=$(curl -s --max-time 1 ipv6.ip.sb)
    if [ -n "$ipv6" ]; then
        HOST_IP="$ipv6"
    else
        echo -e "\e[1;35m无法获取IPv4或IPv6地址\033[0m"
        exit 1
    fi
fi

# 获取ISP信息
ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')

# 输出连接信息
echo -e "\e[1;32mHysteria2 安装并启动成功\033[0m"
echo ""
echo -e "\e[1;33mV2rayN / Nekobox:\033[0m"
echo -e "\e[1;32mhysteria2://$PASSWD@$HOST_IP:$HY2_PORT/?sni=www.bing.com&alpn=h3&insecure=1#$ISP\033[0m"
echo ""
echo -e "\e[1;33mSurge:\033[0m"
echo -e "\e[1;32m$ISP = hysteria2, $HOST_IP, $HY2_PORT, password = $PASSWD, skip-cert-verify=true, sni=www.bing.com\033[0m"
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
  sni: www.bing.com
  skip-cert-verify: true
  fast-open: true
EOF
