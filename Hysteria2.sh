#!/bin/bash
set -e

echo "=== Hysteria2 Auto Install & Repair Script ==="

# Set default port
HY2_PORT=${HY2_PORT:-8880}
echo "Using port: $HY2_PORT"

# Step 1: Download Hysteria binary
echo "[1/5] Downloading Hysteria2 binary..."
wget -O /usr/local/bin/hysteria https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64
chmod +x /usr/local/bin/hysteria

# Step 2: Create systemd service
echo "[2/5] Creating systemd service..."
cat > /etc/systemd/system/hysteria-server.service << 'EOF'
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

# Step 3: Create default config
echo "[3/5] Creating default config..."
mkdir -p /etc/hysteria
cat > /etc/hysteria/config.yaml << EOF
listen: :$HY2_PORT
tls:
  cert: /etc/hysteria/cert.pem
  key: /etc/hysteria/key.pem
auth:
  type: password
  password: your_password
EOF

# Step 4: Fix /etc/hosts
echo "[4/5] Fixing /etc/hosts..."
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
  echo "127.0.0.1    $HOSTNAME" >> /etc/hosts
  echo "Added $HOSTNAME to /etc/hosts"
else
  echo "$HOSTNAME already exists in /etc/hosts"
fi

# Step 5: Enable and restart service
echo "[5/5] Starting hysteria-server..."
systemctl daemon-reexec
systemctl enable hysteria-server.service
systemctl restart hysteria-server.service

echo "=== Hysteria2 is installed and running on port $HY2_PORT ==="
