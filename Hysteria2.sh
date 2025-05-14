#!/bin/bash

# 随机生成端口和密码
[ -z "$HY2_PORT" ] && HY2_PORT=$(shuf -i 2000-65000 -n 1)
[ -z "$PASSWD" ] && PASSWD=$(cat /proc/sys/kernel/random/uuid)

# 检查是否为root下运行
if [[ $EUID -ne 0 ]]; then
  echo -e '\033[1;35m请以root权限运行脚本\033[0m'
  exit 1
fi

# 判断系统并安装依赖
SYSTEM=$(source /etc/os-release && echo $ID)
case $SYSTEM in
  debian|ubuntu)
    package_install="apt-get update && apt-get install -y"
    ;;
  centos|rhel|oracle)
    package_install="yum install -y"
    ;;
  fedora|rocky|almalinux)
    package_install="dnf install -y"
    ;;
  alpine)
    package_install="apk add --no-cache"
    ;;
  *)
    echo -e '\033[1;35m暂不支持的系统！\033[0m'
    exit 1
    ;;
esac
$package_install openssl unzip wget curl

# 安装Hysteria2
bash <(curl -fsSL https://get.hy2.sh/)

# 创建配置目录
mkdir -p /etc/hysteria

# 生成自签证书
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
  -keyout /etc/hysteria/server.key \
  -out /etc/hysteria/server.crt \
  -subj "/CN=bing.com" -days 36500

chown hysteria:hysteria /etc/hysteria/server.key /etc/hysteria/server.crt

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

# 启动Hysteria2
systemctl restart hysteria-server
systemctl enable hysteria-server

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

# 获取ISP信息
ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')

# 输出连接信息
echo -e "\e[1;32mHysteria2安装成功\033[0m"
echo ""
echo -e "\e[1;33mV2rayN / Nekobox 配置:\033[0m"
echo -e "\e[1;32mhysteria2://$PASSWD@$HOST_IP:$HY2_PORT/?sni=www.bing.com&alpn=h3&insecure=1#$ISP\033[0m"
echo ""
echo -e "\e[1;33mSurge 配置:\033[0m"
echo -e "\e[1;32m$ISP = hysteria2, $HOST_IP, $HY2_PORT, password = $PASSWD, skip-cert-verify=true, sni=www.bing.com\033[0m"
echo ""
echo -e "\e[1;33mClash 配置:\033[0m"
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
