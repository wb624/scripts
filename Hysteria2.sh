#!/bin/bash

# 随机生成端口和密码
[ -z "$HY2_PORT" ] && HY2_PORT=$(shuf -i 2000-65000 -n 1)
[ -z "$PASSWD" ] && PASSWD=$(cat /proc/sys/kernel/random/uuid)

# 检查是否为root下运行
[[ $EUID -ne 0 ]] && echo -e '\033[1;35m请在root用户下运行脚本\033[0m' && exit 1

# 判断系统并安装依赖
SYSTEM=$(cat /etc/os-release | grep '^ID=' | awk -F '=' '{print $2}' | tr -d '"')
case $SYSTEM in
  "debian"|"ubuntu")
    package_install="apt-get install -y"
    ;;
  "centos"|"oracle"|"rhel")
    package_install="yum install -y"
    ;;
  "fedora"|"rocky"|"almalinux")
    package_install="dnf install -y"
    ;;
  "alpine")
    package_install="apk add"
    ;;
  *)
    echo -e '\033[1;35m暂不支持的系统！\033[0m'
    exit 1
    ;;
esac
$package_install openssl unzip wget curl

# 安装Hysteria2
bash <(curl -fsSL https://get.hy2.sh/)

# 生成自签证书
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=bing.com" -days 36500 && sudo chown hysteria /etc/hysteria/server.key && sudo chown hysteria /etc/hysteria/server.crt

# 生成hy2配置文件
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

# 启动Hysteria2
systemctl start hysteria-server.service
systemctl restart hysteria-server.service

# 设置开机自启
systemctl enable hysteria-server.service

# 获取本机IP地址
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
echo -e "\e[1;32m本机IP: $HOST_IP\033[0m"

# 获取ipinfo
ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')

# 输出hy2信息
echo -e "\e[1;32mHysteria2安装成功\033[0m"
echo ""
echo -e "\e[1;33mV2rayN 或 Nekobox\033[0m"
echo -e "\e[1;32mhysteria2://$PASSWD@$HOST_IP:$HY2_PORT/?sni=www.bing.com&alpn=h3&insecure=1#$ISP\033[0m"
echo ""
echo -e "\e[1;33mSurge\033[0m"
echo -e "\e[1;32m$ISP = hysteria2, $HOST_IP, $HY2_PORT, password = $PASSWD, skip-cert-verify=true, sni=www.bing.com\033[0m"
echo ""
echo -e "\e[1;33mClash\033[0m"
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
  #!/bin/bash

set -e

echo "=== 自动修复 Hysteria2 安装问题 ==="

# 下载 Hysteria2 可执行文件
echo "[1/4] 正在下载 Hysteria2 可执行文件..."
wget -O hysteria.tar.gz https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64.tar.gz

echo "[2/4] 解压并移动到 /usr/local/bin..."
tar -xvzf hysteria.tar.gz
mv -f hysteria /usr/local/bin/hysteria
chmod +x /usr/local/bin/hysteria
rm -f hysteria.tar.gz

# 修复 /etc/hosts 主机名解析问题
echo "[3/4] 修复 /etc/hosts 主机名解析..."
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo "127.0.0.1    $HOSTNAME" >> /etc/hosts
    echo "已添加主机名 $HOSTNAME 到 /etc/hosts"
else
    echo "/etc/hosts 中已存在主机名 $HOSTNAME，无需修改"
fi

# 重新启动服务
echo "[4/4] 重启 hysteria-server 服务..."
systemctl daemon-reexec
systemctl restart hysteria-server.service

echo "=== 修复完成，Hysteria2 应已正常运行 ==="
EOF
