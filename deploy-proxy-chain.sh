#!/bin/bash
# 代理链部署脚本 - Reality + Hysteria2 + SOCKS5
# Author: ProxyChain Deploy Script
# Version: 1.0

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全局变量
WORK_DIR="/opt/proxy-chain"
XRAY_URL="https://download.colorduck.me/Xray-linux-64.zip"
HYSTERIA_URL="https://download.colorduck.me/hysteria-linux-amd64"

# 打印带颜色的消息
print_msg() {
    echo -e "${2}${1}${NC}"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_msg "此脚本需要root权限运行" "$RED"
        exit 1
    fi
}

# 检测系统
check_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_msg "无法检测系统版本" "$RED"
        exit 1
    fi
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_msg "此脚本仅支持Ubuntu和Debian系统" "$RED"
        exit 1
    fi
    
    print_msg "检测到系统: $OS $VER" "$GREEN"
}

# 安装基础依赖
install_dependencies() {
    print_msg "正在更新系统包..." "$YELLOW"
    apt-get update -y
    apt-get upgrade -y
    
    print_msg "正在安装依赖..." "$YELLOW"
    apt-get install -y wget curl unzip ufw net-tools htop iftop vnstat
}

# 优化系统网络
optimize_network() {
    print_msg "正在优化网络设置..." "$YELLOW"
    
    # 备份原配置
    cp /etc/sysctl.conf /etc/sysctl.conf.bak
    
    # 网络优化配置
    cat >> /etc/sysctl.conf << EOF

# Proxy Chain Network Optimization
# 核心网络参数
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.netdev_max_backlog = 10000
net.core.somaxconn = 10000

# TCP参数优化
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_mem = 88560 118080 177120
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 2
net.ipv4.tcp_ecn_fallback = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 55000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 8192

# IP参数
net.ipv4.ip_forward = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.conf.all.route_localnet = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1

# UDP参数优化
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# 其他优化
fs.file-max = 1000000
fs.inotify.max_user_instances = 8192
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

    # 应用配置
    sysctl -p
    
    # 优化文件描述符限制
    cat >> /etc/security/limits.conf << EOF
* soft nofile 1000000
* hard nofile 1000000
* soft nproc 1000000
* hard nproc 1000000
EOF

    # 启用BBR
    if ! lsmod | grep -q bbr; then
        modprobe tcp_bbr
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    fi
    
    print_msg "网络优化完成" "$GREEN"
}

# 创建工作目录
create_work_dir() {
    mkdir -p $WORK_DIR/{xray,hysteria2,config,logs}
    cd $WORK_DIR
}

# 生成随机端口
generate_port() {
    echo $((RANDOM % 10000 + 20000))
}

# 生成UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 部署国内机（Reality + Hysteria2客户端）
deploy_domestic() {
    print_msg "开始部署国内机服务..." "$BLUE"
    
    # 下载Xray
    print_msg "正在下载Xray..." "$YELLOW"
    wget -O xray.zip $XRAY_URL
    unzip -o xray.zip -d $WORK_DIR/xray/
    chmod +x $WORK_DIR/xray/xray
    
    # 下载Hysteria2
    print_msg "正在下载Hysteria2..." "$YELLOW"
    wget -O $WORK_DIR/hysteria2/hysteria $HYSTERIA_URL
    chmod +x $WORK_DIR/hysteria2/hysteria
    
    # 获取配置信息
    read -p "请输入Reality监听端口 (默认443): " REALITY_PORT
    REALITY_PORT=${REALITY_PORT:-443}
    
    read -p "请输入中转服务器地址: " RELAY_SERVER
    read -p "请输入中转服务器Hysteria2端口: " RELAY_PORT
    read -p "请输入Hysteria2密码: " HY2_PASSWORD
    
    # 生成Reality密钥对
    print_msg "正在生成Reality密钥对..." "$YELLOW"
    KEYS=$($WORK_DIR/xray/xray x25519)
    PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
    PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
    SHORT_ID=$(openssl rand -hex 8)
    UUID=$(generate_uuid)
    LOCAL_HY2_PORT=$(generate_port)
    
    # 生成Xray配置
    cat > $WORK_DIR/config/xray.json << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$WORK_DIR/logs/xray-access.log",
    "error": "$WORK_DIR/logs/xray-error.log"
  },
  "inbounds": [
    {
      "port": $REALITY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "apple.com:443",
          "serverNames": [
            "apple.com",
            "www.apple.com"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": $LOCAL_HY2_PORT
          }
        ]
      }
    }
  ]
}
EOF

    # 生成Hysteria2客户端配置
    cat > $WORK_DIR/config/hysteria2-client.yaml << EOF
server: $RELAY_SERVER:$RELAY_PORT

auth: $HY2_PASSWORD

socks5:
  listen: 127.0.0.1:$LOCAL_HY2_PORT

transport:
  udp:
    hopInterval: 30s

quic:
  initStreamReceiveWindow: 26843545
  maxStreamReceiveWindow: 26843545
  initConnReceiveWindow: 67108864
  maxConnReceiveWindow: 67108864

bandwidth:
  up: 1 gbps
  down: 1 gbps

fastOpen: true

lazy: true
EOF

    # 创建systemd服务
    cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=$WORK_DIR/xray/xray run -config $WORK_DIR/config/xray.json
Restart=on-failure
RestartSec=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/hysteria2-client.service << EOF
[Unit]
Description=Hysteria2 Client Service
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=$WORK_DIR/hysteria2/hysteria client -c $WORK_DIR/config/hysteria2-client.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable xray hysteria2-client
    systemctl start xray hysteria2-client
    
    # 配置防火墙
    ufw allow $REALITY_PORT/tcp
    ufw --force enable
    
    # 打印连接信息
    print_msg "\n=== 国内机部署完成 ===" "$GREEN"
    print_msg "Reality连接信息:" "$YELLOW"
    print_msg "地址: $(curl -s ip.sb)" "$NC"
    print_msg "端口: $REALITY_PORT" "$NC"
    print_msg "UUID: $UUID" "$NC"
    print_msg "Flow: xtls-rprx-vision" "$NC"
    print_msg "Public Key: $PUBLIC_KEY" "$NC"
    print_msg "Short ID: $SHORT_ID" "$NC"
    print_msg "SNI: apple.com" "$NC"
}

# 部署中转机（Hysteria2服务端）
deploy_relay() {
    print_msg "开始部署中转机服务..." "$BLUE"
    
    # 下载Hysteria2
    print_msg "正在下载Hysteria2..." "$YELLOW"
    wget -O $WORK_DIR/hysteria2/hysteria $HYSTERIA_URL
    chmod +x $WORK_DIR/hysteria2/hysteria
    
    # 获取配置信息
    read -p "请输入Hysteria2监听端口 (默认随机): " HY2_PORT
    HY2_PORT=${HY2_PORT:-$(generate_port)}
    
    read -p "请输入Hysteria2密码: " HY2_PASSWORD
    read -p "请输入落地机SOCKS5地址 (IP:端口): " SOCKS_ADDR
    
    # 生成自签名证书
    print_msg "正在生成自签名证书..." "$YELLOW"
    mkdir -p $WORK_DIR/config/certs
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout $WORK_DIR/config/certs/server.key \
        -out $WORK_DIR/config/certs/server.crt \
        -subj "/CN=example.com" -days 36500
    
    # 生成Hysteria2服务端配置
    cat > $WORK_DIR/config/hysteria2-server.yaml << EOF
listen: :$HY2_PORT

tls:
  cert: $WORK_DIR/config/certs/server.crt
  key: $WORK_DIR/config/certs/server.key

auth:
  type: password
  password: $HY2_PASSWORD

quic:
  initStreamReceiveWindow: 26843545
  maxStreamReceiveWindow: 26843545
  initConnReceiveWindow: 67108864
  maxConnReceiveWindow: 67108864

bandwidth:
  up: 1 gbps
  down: 1 gbps

resolver:
  type: udp
  udp:
    addr: 8.8.8.8:53
    timeout: 4s

outbounds:
  - name: socks5
    type: socks5
    socks5:
      addr: $SOCKS_ADDR
EOF

    # 创建systemd服务
    cat > /etc/systemd/system/hysteria2-server.service << EOF
[Unit]
Description=Hysteria2 Server Service
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=$WORK_DIR/hysteria2/hysteria server -c $WORK_DIR/config/hysteria2-server.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable hysteria2-server
    systemctl start hysteria2-server
    
    # 配置防火墙
    ufw allow $HY2_PORT/udp
    ufw --force enable
    
    # 打印连接信息
    print_msg "\n=== 中转机部署完成 ===" "$GREEN"
    print_msg "Hysteria2服务信息:" "$YELLOW"
    print_msg "地址: $(curl -s ip.sb)" "$NC"
    print_msg "端口: $HY2_PORT" "$NC"
    print_msg "密码: $HY2_PASSWORD" "$NC"
}

# 部署落地机（SOCKS5代理）
deploy_exit() {
    print_msg "开始部署落地机服务..." "$BLUE"
    
    # 安装3proxy作为SOCKS5服务器
    print_msg "正在编译安装3proxy..." "$YELLOW"
    apt-get install -y build-essential
    cd /tmp
    wget https://github.com/3proxy/3proxy/archive/0.9.4.tar.gz
    tar xzf 0.9.4.tar.gz
    cd 3proxy-0.9.4
    make -f Makefile.Linux
    make -f Makefile.Linux install
    
    # 获取配置信息
    read -p "请输入SOCKS5监听端口 (默认随机): " SOCKS_PORT
    SOCKS_PORT=${SOCKS_PORT:-$(generate_port)}
    
    read -p "是否需要认证? (y/n, 默认n): " NEED_AUTH
    NEED_AUTH=${NEED_AUTH:-n}
    
    if [[ "$NEED_AUTH" == "y" ]]; then
        read -p "请输入用户名: " SOCKS_USER
        read -p "请输入密码: " SOCKS_PASS
        AUTH_CONFIG="users $SOCKS_USER:CL:$SOCKS_PASS"
        AUTH_RULE="auth strong"
    else
        AUTH_CONFIG=""
        AUTH_RULE="auth none"
    fi
    
    # 生成3proxy配置
    mkdir -p /etc/3proxy
    cat > /etc/3proxy/3proxy.cfg << EOF
daemon
maxconn 10000
nserver 8.8.8.8
nserver 8.8.4.4
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
log /var/log/3proxy/3proxy.log D
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"
archiver gz /usr/bin/gzip %F
rotate 30

$AUTH_CONFIG
$AUTH_RULE

allow *
socks -p$SOCKS_PORT
EOF

    # 创建日志目录
    mkdir -p /var/log/3proxy
    
    # 创建systemd服务
    cat > /etc/systemd/system/3proxy.service << EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=on-failure
RestartSec=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable 3proxy
    systemctl start 3proxy
    
    # 配置防火墙
    ufw allow $SOCKS_PORT/tcp
    ufw --force enable
    
    # 打印连接信息
    print_msg "\n=== 落地机部署完成 ===" "$GREEN"
    print_msg "SOCKS5服务信息:" "$YELLOW"
    print_msg "地址: $(curl -s ip.sb)" "$NC"
    print_msg "端口: $SOCKS_PORT" "$NC"
    if [[ "$NEED_AUTH" == "y" ]]; then
        print_msg "用户名: $SOCKS_USER" "$NC"
        print_msg "密码: $SOCKS_PASS" "$NC"
    else
        print_msg "认证: 无需认证" "$NC"
    fi
}

# 显示菜单
show_menu() {
    echo -e "\n${BLUE}=== Reality + Hysteria2 代理链部署脚本 ===${NC}"
    echo -e "${YELLOW}请选择服务器类型:${NC}"
    echo "1) 国内机 (Reality + Hysteria2客户端)"
    echo "2) 中转机 (Hysteria2服务端)"
    echo "3) 落地机 (SOCKS5代理)"
    echo "4) 退出"
}

# 主函数
main() {
    check_root
    check_system
    
    show_menu
    read -p "请输入选择 [1-4]: " choice
    
    case $choice in
        1)
            install_dependencies
            optimize_network
            create_work_dir
            deploy_domestic
            ;;
        2)
            install_dependencies
            optimize_network
            create_work_dir
            deploy_relay
            ;;
        3)
            install_dependencies
            optimize_network
            deploy_exit
            ;;
        4)
            print_msg "退出脚本" "$GREEN"
            exit 0
            ;;
        *)
            print_msg "无效选择" "$RED"
            exit 1
            ;;
    esac
    
    print_msg "\n部署完成！" "$GREEN"
    print_msg "日志位置: $WORK_DIR/logs/" "$YELLOW"
    print_msg "配置位置: $WORK_DIR/config/" "$YELLOW"
    
    # 显示服务状态
    echo -e "\n${BLUE}=== 服务状态 ===${NC}"
    case $choice in
        1)
            systemctl status xray --no-pager
            systemctl status hysteria2-client --no-pager
            ;;
        2)
            systemctl status hysteria2-server --no-pager
            ;;
        3)
            systemctl status 3proxy --no-pager
            ;;
    esac
}

# 执行主函数
main