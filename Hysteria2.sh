#!/bin/bash

# 一键安装 hysteria2 服务端 for Debian
set -e

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

# 安装依赖
apt update
apt install -y curl wget unzip socat cron

# 下载 hysteria2 最新版本
latest_ver=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep "tag_name" | cut -d '"' -f 4)
wget -O hysteria-linux-amd64.tar.gz https://github.com/apernet/hysteria/releases/download/${latest_ver}/hysteria-linux-amd64.tar.gz
tar -xzf hysteria-linux-amd64.tar.gz
mv hysteria /usr/local/bin/hysteria
chmod +x /usr/local/bin/hysteria

# 创建目录
mkdir -p /etc/hysteria

# 自签 TLS 证书（仅测试用）
openssl req -newkey rsa:2048 -x509 -sha256 -days 3650 -nodes \
  -out /etc/hysteria/fullchain.crt \
  -keyout /etc/hysteria/privkey.key \
  -subj "/CN=hy.example.com"

# 创建配置文件（默认端口 443，密码 abc123）
cat > /etc/hysteria/config.yaml <<EOF
listen: :443
tls:
  cert: /etc/hysteria/fullchain.crt
  key: /etc/hysteria/privkey.key
auth:
  password: abc123
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
EOF

# 创建 systemd 服务
cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now hysteria

echo "hysteria2 安装完成，配置如下："
echo "端口: 443"
echo "密码: abc123"
echo "伪装地址: https://www.bing.com"
