#!/bin/bash
set -e

# ========== 配置 ==========
PORT=3633
ARGO_DOMAIN="jp.wboo.qzz.io"
ARGO_TOKEN="eyJhIjoiMmI5NmIx...MzNeSJ9"
# UUID 和 WS 路径
VLESS_UUID=$(cat /proc/sys/kernel/random/uuid)
WS_PATH="/vless"

# ========== 安装依赖 ==========
apt update && apt install -y curl wget unzip tar xz-utils

# ========== 安装 Hysteria2 ==========
curl -L -o /usr/local/bin/hysteria \
  https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64
chmod +x /usr/local/bin/hysteria

# 下载并安装 sing-box,cloudflared
install_singbox() {
    clear
    purple "正在安装sing-box中，请稍后..."
    # 判断系统架构
    ARCH_RAW=$(uname -m)
    case "${ARCH_RAW}" in
        'x86_64') ARCH='amd64' ;;
        'x86' | 'i686' | 'i386') ARCH='386' ;;
        'aarch64' | 'arm64') ARCH='arm64' ;;
        'armv7l') ARCH='armv7' ;;
        's390x') ARCH='s390x' ;;
        *) red "不支持的架构: ${ARCH_RAW}"; exit 1 ;;
    esac

# ========== 配置 systemd 服务 =========#
## cloudflared (Argo) ##
cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=Cloudflare Argo Tunnel (固定)
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --edge-ip-version auto --no-autoupdate \\
  --hostname ${ARGO_DOMAIN} \\
  --token ${ARGO_TOKEN} \\
  --url http://127.0.0.1:8443
Restart=always
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

## Sing‑box ##
mkdir -p /etc/sing-box && cat > /etc/sing-box/config.json <<EOF
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "127.0.0.1",
      "listen_port": 8443,
      "users": [
        { "uuid": "${VLESS_UUID}", "flow": "" }
      ],
      "tls": { "enabled": false },
      "transport": {
        "type": "ws",
        "path": "${WS_PATH}"
      }
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ]
}
EOF

cat > /etc/systemd/system/sing-box.service <<EOF
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

## Hysteria2 ##
mkdir -p /etc/hysteria && cat > /etc/hysteria/config.yaml <<EOF
listen: :${PORT}

tls:
  disable: true

auth:
  type: password
  password: "pass1234"

protocol: udp
obfs: "mysecret"

forward:
  - "127.0.0.1:8443"
EOF

cat > /etc/systemd/system/hysteria.service <<EOF
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

# ========== 启动服务 ==========
systemctl daemon-reload
systemctl enable argo sing-box hysteria
systemctl restart argo sing-box hysteria

# ========== 输出信息 ==========
echo -e "\n✅ 部署完成！"
echo -e "Argo 隧道 地址：${ARGO_DOMAIN}"
echo -e "Hysteria2 端口：${PORT}, 密码：pass1234, obfs：mysecret"
echo -e "Sing-box VLESS + WS：ws://${ARGO_DOMAIN}/${WS_PATH}"
echo -e "UUID：${VLESS_UUID}"
