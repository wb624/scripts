#!/bin/bash set -e

=== CONFIG START ===

DOMAIN="ddj.wuoo.dpdns.org" HY2_UUID="a0578f92-76b5-4006-b237-51333193fc11" TUIC_UUID="400b397b-e572-4efd-a355-48ea3c8aa4ad" TUIC_TOKEN="aDD4qbgGyfTxkMGtO5zyKA" SINGBOX_VERSION="$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep tag_name | cut -d '"' -f4)"

=== CONFIG END ===

安装依赖

apt update && apt install -y curl unzip socat openssl sudo

下载并安装 sing-box

mkdir -p /etc/sing-box cd /tmp curl -L -o sing-box.zip https://github.com/SagerNet/sing-box/releases/download/${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-amd64.zip unzip sing-box.zip install -m 755 sing-box /usr/local/bin/sing-box

生成自签 TLS

mkdir -p /etc/sing-box/certs openssl req -newkey rsa:2048 -x509 -sha256 -days 3650 -nodes 
-out /etc/sing-box/certs/cert.pem 
-keyout /etc/sing-box/certs/private.key 
-subj "/CN=$DOMAIN"

创建配置文件

cat > /etc/sing-box/config.json << EOF { "log": {"level": "info"}, "inbounds": [ { "type": "hysteria2", "tag": "hy2-in", "listen": "0.0.0.0", "listen_port": 443, "tls": { "enabled": true, "certificate_path": "/etc/sing-box/certs/cert.pem", "key_path": "/etc/sing-box/certs/private.key" }, "users": [ {"uuid": "$HY2_UUID"} ] }, { "type": "tuic", "tag": "tuic-in", "listen": "0.0.0.0", "listen_port": 1443, "tls": { "enabled": true, "certificate_path": "/etc/sing-box/certs/cert.pem", "key_path": "/etc/sing-box/certs/private.key" }, "users": [ { "uuid": "$TUIC_UUID", "password": "$TUIC_TOKEN" } ], "congestion_control": "bbr", "zero_rtt_handshake": true } ], "outbounds": [ {"type": "direct", "tag": "direct"}, {"type": "block", "tag": "block"} ] } EOF

创建 systemd 服务

cat > /etc/systemd/system/sing-box.service << EOF [Unit] Description=sing-box service After=network.target

[Service] ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json Restart=always

[Install] WantedBy=multi-user.target EOF

启动服务

systemctl daemon-reexec systemctl daemon-reload systemctl enable sing-box systemctl restart sing-box

开放端口

ufw allow 443/tcp ufw allow 1443/tcp

echo "\n✅ sing-box 已成功部署 (hy2 + tuic)！" echo "  - HY2 端口: 443" echo "  - TUIC v5 端口: 1443" echo "  - 自签 TLS 已生成于 /etc/sing-box/certs/" echo "\n📂 客户端配置将随后提供。"

