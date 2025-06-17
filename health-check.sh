#!/bin/bash
# 代理链健康检查和自动恢复脚本
# 可配置为 cron 定时任务运行

set -e

# 配置
WORK_DIR="/opt/proxy-chain"
LOG_FILE="/var/log/proxy-health-check.log"
MAX_LOG_SIZE=10485760  # 10MB
TELEGRAM_BOT_TOKEN=""  # 可选：Telegram 通知
TELEGRAM_CHAT_ID=""    # 可选：Telegram 通知

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
    
    # 日志轮转
    if [[ -f $LOG_FILE ]] && [[ $(stat -c%s "$LOG_FILE") -gt $MAX_LOG_SIZE ]]; then
        mv $LOG_FILE $LOG_FILE.old
        touch $LOG_FILE
    fi
}

# 发送通知（可选）
send_notification() {
    local message=$1
    
    # Telegram 通知
    if [[ -n "$TELEGRAM_BOT_TOKEN" ]] && [[ -n "$TELEGRAM_CHAT_ID" ]]; then
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d chat_id="$TELEGRAM_CHAT_ID" \
            -d text="🚨 代理链告警\n\n$message" \
            -d parse_mode="HTML" > /dev/null 2>&1
    fi
}

# 检查服务状态
check_service() {
    local service=$1
    
    if ! systemctl is-active --quiet $service; then
        log "错误: $service 服务未运行，尝试重启..."
        systemctl restart $service
        sleep 5
        
        if systemctl is-active --quiet $service; then
            log "成功: $service 服务已恢复"
            send_notification "服务 $service 已自动恢复运行"
        else
            log "失败: $service 服务重启失败"
            send_notification "⚠️ 服务 $service 重启失败，需要人工介入"
            return 1
        fi
    fi
    
    return 0
}

# 检查端口监听
check_port() {
    local port=$1
    local service=$2
    
    if ! ss -tlnp | grep -q ":$port "; then
        log "错误: 端口 $port ($service) 未监听"
        return 1
    fi
    
    return 0
}

# 检查网络连通性（中转机和落地机）
check_connectivity() {
    local target=$1
    local port=$2
    local service=$3
    
    if ! timeout 5 bash -c "echo >/dev/tcp/$target/$port" 2>/dev/null; then
        log "错误: 无法连接到 $target:$port ($service)"
        send_notification "⚠️ 无法连接到上游服务器 $target:$port ($service)"
        return 1
    fi
    
    return 0
}

# 检查系统资源
check_system_resources() {
    # 检查 CPU 使用率
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    cpu_usage=${cpu_usage%.*}
    
    if [[ $cpu_usage -gt 90 ]]; then
        log "警告: CPU 使用率过高: $cpu_usage%"
        send_notification "⚠️ CPU 使用率过高: $cpu_usage%"
    fi
    
    # 检查内存使用率
    local mem_total=$(free -m | grep Mem | awk '{print $2}')
    local mem_used=$(free -m | grep Mem | awk '{print $3}')
    local mem_usage=$((mem_used * 100 / mem_total))
    
    if [[ $mem_usage -gt 90 ]]; then
        log "警告: 内存使用率过高: $mem_usage%"
        send_notification "⚠️ 内存使用率过高: $mem_usage%"
    fi
    
    # 检查磁盘使用率
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [[ $disk_usage -gt 90 ]]; then
        log "警告: 磁盘使用率过高: $disk_usage%"
        send_notification "⚠️ 磁盘使用率过高: $disk_usage%"
    fi
}

# 主检查函数
main_check() {
    log "开始健康检查..."
    
    # 检查系统资源
    check_system_resources
    
    # 检测服务器类型并执行相应检查
    if systemctl list-units --type=service | grep -q "xray.service"; then
        # 国内机检查
        log "检测到国内机配置"
        
        # 检查服务状态
        check_service "xray"
        check_service "hysteria2-client"
        
        # 检查端口
        if [[ -f "$WORK_DIR/config/xray.json" ]]; then
            REALITY_PORT=$(grep -oP '"port":\s*\K\d+' $WORK_DIR/config/xray.json | head -1)
            check_port $REALITY_PORT "Reality"
        fi
        
        # 检查上游连接
        if [[ -f "$WORK_DIR/config/hysteria2-client.yaml" ]]; then
            RELAY_SERVER=$(grep -oP 'server:\s*\K[^:]+' $WORK_DIR/config/hysteria2-client.yaml)
            RELAY_PORT=$(grep -oP 'server:\s*[^:]+:\K\d+' $WORK_DIR/config/hysteria2-client.yaml)
            check_connectivity $RELAY_SERVER $RELAY_PORT "Hysteria2中转"
        fi
        
    elif systemctl list-units --type=service | grep -q "hysteria2-server.service"; then
        # 中转机检查
        log "检测到中转机配置"
        
        # 检查服务状态
        check_service "hysteria2-server"
        
        # 检查端口
        if [[ -f "$WORK_DIR/config/hysteria2-server.yaml" ]]; then
            HY2_PORT=$(grep -oP 'listen:\s*:\K\d+' $WORK_DIR/config/hysteria2-server.yaml)
            check_port $HY2_PORT "Hysteria2"
            
            # 检查上游SOCKS5连接
            SOCKS_ADDR=$(grep -oP 'addr:\s*\K[^:]+:[0-9]+' $WORK_DIR/config/hysteria2-server.yaml | head -1)
            if [[ -n "$SOCKS_ADDR" ]]; then
                SOCKS_IP=$(echo $SOCKS_ADDR | cut -d: -f1)
                SOCKS_PORT=$(echo $SOCKS_ADDR | cut -d: -f2)
                check_connectivity $SOCKS_IP $SOCKS_PORT "SOCKS5落地"
            fi
        fi
        
    elif systemctl list-units --type=service | grep -q "3proxy.service"; then
        # 落地机检查
        log "检测到落地机配置"
        
        # 检查服务状态
        check_service "3proxy"
        
        # 检查端口
        SOCKS_PORT=$(grep -oP 'socks -p\K\d+' /etc/3proxy/3proxy.cfg 2>/dev/null || echo "")
        if [[ -n "$SOCKS_PORT" ]]; then
            check_port $SOCKS_PORT "SOCKS5"
        fi
        
        # 检查外网连通性
        if ! timeout 5 curl -s https://www.google.com > /dev/null; then
            log "警告: 外网连接可能存在问题"
        fi
    fi
    
    log "健康检查完成"
}

# 设置定时任务
setup_cron() {
    local cron_schedule=${1:-"*/5 * * * *"}  # 默认每5分钟运行一次
    
    # 获取脚本完整路径
    SCRIPT_PATH=$(readlink -f "$0")
    
    # 检查是否已存在
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
        echo "定时任务已存在"
        return
    fi
    
    # 添加定时任务
    (crontab -l 2>/dev/null; echo "$cron_schedule $SCRIPT_PATH check") | crontab -
    echo "已添加定时任务: $cron_schedule"
}

# 命令行参数处理
case "${1:-}" in
    check)
        main_check
        ;;
    setup)
        setup_cron "${2:-}"
        echo "健康检查定时任务已设置"
        echo "查看定时任务: crontab -l"
        echo "查看日志: tail -f $LOG_FILE"
        ;;
    test)
        echo "测试运行健康检查..."
        main_check
        echo "检查完成，查看日志: $LOG_FILE"
        ;;
    *)
        echo "使用方法:"
        echo "  $0 check              - 执行一次健康检查"
        echo "  $0 setup [schedule]   - 设置定时任务 (默认每5分钟)"
        echo "  $0 test               - 测试运行"
        echo ""
        echo "定时任务格式示例:"
        echo "  '*/5 * * * *'    - 每5分钟"
        echo "  '*/10 * * * *'   - 每10分钟"
        echo "  '0 * * * *'      - 每小时"
        exit 1
        ;;
esac