#!/bin/bash
set -e

echo "=== Hysteria2 一键安装脚本（含自动修复）==="

# 设置默认端口
HY2_PORT=${HY2_PORT:-8880}
echo "使用端口: $HY2_PORT"

# 下载并安装 Hysteria2 可执行文件
echo "[1/6] 下载 Hysteria2 可执行文件..."
wget -O /usr/local/bin/hysteria https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64
chmod +x /usr/local/bin/hysteria

# 创建 systemd 服务文件（如果不存在）
echo "[2/6] 创建 systemd 服务文件..."
cat <<EOF > /etc/systemd/system/hysteria-server.service
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 创建配置文件目录和示例配置
echo "[3/6] 创建默认配置文件..."
mkdir -p /etc/hysteria
cat <<EOF > /etc/hysteria/config.yaml
listen: :$HY2_PORT
tls:
  cert: /etc/hysteria/cert.pem
  key: /etc/hysteria/key.pem
auth:
  type: password
  password: your_password
EOF

# 修复 /etc/hosts 主机名解析问题
echo "[4/6] 修复 /etc/hosts 主机名解析..."
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo "127.0.0.1    $HOSTNAME" >> /etc/hosts
    echo "已添加主机名 $HOSTNAME 到 /etc/hosts"
else
    echo "/etc/hosts 中已存在主机名 $HOSTNAME，无需修改"
fi

# 启用并重启服务
echo "[5/6] 启用并启动 hysteria-server 服务..."
systemctl daemon-reexec
systemctl enable hysteria-server.service
systemctl restart hysteria-server.service

echo "=== 安装与修复完成，Hysteria2 应已正常运行在端口 $HY2_PORT ==="
