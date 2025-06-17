#!/bin/bash
# 代理链监控和管理脚本
# 用于监控服务状态、查看日志、重启服务等

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WORK_DIR="/opt/proxy-chain"

# 检查服务类型
check_server_type() {
    if systemctl list-units --type=service | grep -q "xray.service"; then
        SERVER_TYPE="domestic"
        SERVICES=("xray" "hysteria2-client")
    elif systemctl list-units --type=service | grep -q "hysteria2-server.service"; then
        SERVER_TYPE="relay"
        SERVICES=("hysteria2-server")
    elif systemctl list-units --type=service | grep -q "3proxy.service"; then
        SERVER_TYPE="exit"
        SERVICES=("3proxy")
    else
        echo -e "${RED}未检测到已部署的服务${NC}"
        exit 1
    fi
}

# 显示服务状态
show_status() {
    echo -e "\n${BLUE}=== 服务状态 ===${NC}"
    for service in "${SERVICES[@]}"; do
        if systemctl is-active --quiet $service; then
            echo -e "$service: ${GREEN}运行中${NC}"
        else
            echo -e "$service: ${RED}已停止${NC}"
        fi
    done
}

# 查看日志
view_logs() {
    echo -e "\n${BLUE}=== 选择要查看的日志 ===${NC}"
    echo "1) 实时日志"
    echo "2) 最近100行日志"
    echo "3) 错误日志"
    read -p "请选择 [1-3]: " log_choice
    
    case $log_choice in
        1)
            if [[ "$SERVER_TYPE" == "domestic" ]]; then
                echo -e "${YELLOW}按Ctrl+C退出实时日志${NC}"
                journalctl -u xray -u hysteria2-client -f
            elif [[ "$SERVER_TYPE" == "relay" ]]; then
                journalctl -u hysteria2-server -f
            else
                journalctl -u 3proxy -f
            fi
            ;;
        2)
            if [[ "$SERVER_TYPE" == "domestic" ]]; then
                journalctl -u xray -u hysteria2-client -n 100
            elif [[ "$SERVER_TYPE" == "relay" ]]; then
                journalctl -u hysteria2-server -n 100
            else
                journalctl -u 3proxy -n 100
            fi
            ;;
        3)
            if [[ "$SERVER_TYPE" == "domestic" && -f "$WORK_DIR/logs/xray-error.log" ]]; then
                tail -n 50 $WORK_DIR/logs/xray-error.log
            else
                echo "使用journalctl查看错误"
                journalctl -p err -n 50
            fi
            ;;
    esac
}

# 重启服务
restart_services() {
    echo -e "\n${YELLOW}正在重启服务...${NC}"
    for service in "${SERVICES[@]}"; do
        systemctl restart $service
        sleep 2
    done
    show_status
}

# 查看配置
view_config() {
    echo -e "\n${BLUE}=== 当前配置文件 ===${NC}"
    case $SERVER_TYPE in
        domestic)
            echo -e "${YELLOW}Xray配置:${NC}"
            cat $WORK_DIR/config/xray.json | jq . 2>/dev/null || cat $WORK_DIR/config/xray.json
            echo -e "\n${YELLOW}Hysteria2客户端配置:${NC}"
            cat $WORK_DIR/config/hysteria2-client.yaml
            ;;
        relay)
            echo -e "${YELLOW}Hysteria2服务端配置:${NC}"
            cat $WORK_DIR/config/hysteria2-server.yaml
            ;;
        exit)
            echo -e "${YELLOW}3proxy配置:${NC}"
            cat /etc/3proxy/3proxy.cfg
            ;;
    esac
}

# 流量统计
show_traffic() {
    echo -e "\n${BLUE}=== 流量统计 ===${NC}"
    
    # 显示网络接口流量
    echo -e "${YELLOW}实时网络流量:${NC}"
    timeout 10 iftop -t -B -n -N -P || vnstat -l -i eth0
}

# 性能监控
show_performance() {
    echo -e "\n${BLUE}=== 系统性能 ===${NC}"
    
    # CPU和内存使用
    echo -e "${YELLOW}CPU和内存使用:${NC}"
    top -bn1 | head -n 5
    
    # 连接数统计
    echo -e "\n${YELLOW}网络连接统计:${NC}"
    ss -s
    
    # 端口监听状态
    echo -e "\n${YELLOW}监听端口:${NC}"
    ss -tlnp | grep -E "(xray|hysteria|3proxy)" || ss -tlnp
}

# 备份配置
backup_config() {
    BACKUP_DIR="$WORK_DIR/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p $BACKUP_DIR
    
    echo -e "\n${YELLOW}正在备份配置...${NC}"
    cp -r $WORK_DIR/config/* $BACKUP_DIR/
    
    echo -e "${GREEN}配置已备份到: $BACKUP_DIR${NC}"
}

# 更新服务
update_services() {
    echo -e "\n${YELLOW}正在检查更新...${NC}"
    
    case $SERVER_TYPE in
        domestic)
            # 备份当前版本
            cp $WORK_DIR/xray/xray $WORK_DIR/xray/xray.bak
            cp $WORK_DIR/hysteria2/hysteria $WORK_DIR/hysteria2/hysteria.bak
            
            # 下载新版本
            wget -O /tmp/xray.zip https://download.colorduck.me/Xray-linux-64.zip
            unzip -o /tmp/xray.zip -d /tmp/xray_new/
            
            wget -O /tmp/hysteria_new https://download.colorduck.me/hysteria-linux-amd64
            
            # 停止服务
            systemctl stop xray hysteria2-client
            
            # 替换文件
            cp /tmp/xray_new/xray $WORK_DIR/xray/
            cp /tmp/hysteria_new $WORK_DIR/hysteria2/hysteria
            chmod +x $WORK_DIR/xray/xray $WORK_DIR/hysteria2/hysteria
            
            # 启动服务
            systemctl start xray hysteria2-client
            ;;
        relay)
            cp $WORK_DIR/hysteria2/hysteria $WORK_DIR/hysteria2/hysteria.bak
            wget -O /tmp/hysteria_new https://download.colorduck.me/hysteria-linux-amd64
            systemctl stop hysteria2-server
            cp /tmp/hysteria_new $WORK_DIR/hysteria2/hysteria
            chmod +x $WORK_DIR/hysteria2/hysteria
            systemctl start hysteria2-server
            ;;
    esac
    
    echo -e "${GREEN}更新完成${NC}"
    show_status
}

# 显示连接信息
show_connection_info() {
    echo -e "\n${BLUE}=== 连接信息 ===${NC}"
    SERVER_IP=$(curl -s ip.sb)
    
    case $SERVER_TYPE in
        domestic)
            if [[ -f "$WORK_DIR/config/xray.json" ]]; then
                REALITY_PORT=$(jq -r '.inbounds[0].port' $WORK_DIR/config/xray.json 2>/dev/null || grep -oP '"port":\s*\K\d+' $WORK_DIR/config/xray.json | head -1)
                UUID=$(jq -r '.inbounds[0].settings.clients[0].id' $WORK_DIR/config/xray.json 2>/dev/null || grep -oP '"id":\s*"\K[^"]+' $WORK_DIR/config/xray.json | head -1)
                PUBLIC_KEY=$(grep -oP '"publicKey":\s*"\K[^"]+' $WORK_DIR/config/xray.json || echo "需要从部署日志查看")
                SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' $WORK_DIR/config/xray.json 2>/dev/null || grep -oP '"shortIds":\s*\[\s*"\K[^"]+' $WORK_DIR/config/xray.json)
                
                echo -e "${YELLOW}Reality连接信息:${NC}"
                echo "地址: $SERVER_IP"
                echo "端口: $REALITY_PORT"
                echo "UUID: $UUID"
                echo "Public Key: $PUBLIC_KEY"
                echo "Short ID: $SHORT_ID"
                echo "SNI: apple.com"
                echo "Flow: xtls-rprx-vision"
            fi
            ;;
        relay)
            if [[ -f "$WORK_DIR/config/hysteria2-server.yaml" ]]; then
                HY2_PORT=$(grep -oP 'listen:\s*:\K\d+' $WORK_DIR/config/hysteria2-server.yaml)
                echo -e "${YELLOW}Hysteria2服务信息:${NC}"
                echo "地址: $SERVER_IP"
                echo "端口: $HY2_PORT"
                echo "请查看配置文件获取密码"
            fi
            ;;
        exit)
            SOCKS_PORT=$(grep -oP 'socks -p\K\d+' /etc/3proxy/3proxy.cfg)
            echo -e "${YELLOW}SOCKS5服务信息:${NC}"
            echo "地址: $SERVER_IP"
            echo "端口: $SOCKS_PORT"
            ;;
    esac
}

# 主菜单
show_menu() {
    clear
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}   代理链监控和管理工具${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${YELLOW}检测到服务器类型: $SERVER_TYPE${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo "1) 查看服务状态"
    echo "2) 查看日志"
    echo "3) 重启服务"
    echo "4) 查看配置"
    echo "5) 流量统计"
    echo "6) 性能监控"
    echo "7) 备份配置"
    echo "8) 更新服务"
    echo "9) 显示连接信息"
    echo "0) 退出"
    echo -e "${BLUE}=====================================${NC}"
}

# 主函数
main() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}此脚本需要root权限运行${NC}"
        exit 1
    fi
    
    check_server_type
    
    while true; do
        show_menu
        read -p "请选择操作 [0-9]: " choice
        
        case $choice in
            1) show_status ;;
            2) view_logs ;;
            3) restart_services ;;
            4) view_config ;;
            5) show_traffic ;;
            6) show_performance ;;
            7) backup_config ;;
            8) update_services ;;
            9) show_connection_info ;;
            0) 
                echo -e "${GREEN}退出管理工具${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                sleep 2
                ;;
        esac
        
        echo -e "\n${YELLOW}按Enter键继续...${NC}"
        read
    done
}

# 运行主函数
main