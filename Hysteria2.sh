#!/bin/bash

# Hysteria2 一键安装脚本（适用于 Debian）

set -e

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 用户运行本脚本"
  exit 1
fi

# 安装依赖
apt update
apt install -y curl wget unzip openssl

# 下载 hysteria2 最新版本
latest_ver=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -O hysteria.tar.gz https://github.com/apernet/hysteria/releases/download/${latest_ver}/hysteria-linux-amd64.tar.gz
tar -xzf hysteria.tar.gz
mv hysteria /usr/local/bin/hysteria
chmod +x /usr/local/bin/hysteria

# 创建配置目录
mkdir -p /etc/hysteria

# 生成自签 TLS 证书（仅供测试用）
openssl req -new -x509 -days 3650 -nodes -out /etc/hysteria/fullchain.crt -keyout /etc/hysteria/privkey.key -subj "/CN=localhost"

# 生成配置文件
cat << EOF > /etc/hysteria/config.yaml
listen: :443
tls:
  cert: /etc/hysteria/fullchain.crt
  key: /etc/hysteria/privkey.key
auth:
  password: yourpassword
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
EOF

# 创建 systemd 服务文件
cat << EOF > /etc/systemd/system/hysteria.service
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
systemctl daemon-reload
systemctl enable --now hysteria

echo "Hysteria2 安装并启动成功！"
echo "监听端口: 443"
echo "密码: yourpassword"
echo "伪装站: https://www.bing.com"
