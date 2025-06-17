#!/bin/bash
# 代理链快速安装脚本
# 一键下载和执行主部署脚本

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# GitHub项目地址（需要修改为实际地址）
GITHUB_RAW_URL="https://raw.githubusercontent.com/Colorfulshadow/proxy-chain-deploy/main"
INSTALL_DIR="/opt/proxy-chain-scripts"

echo -e "${GREEN}=== 代理链部署系统快速安装 ===${NC}"
echo -e "${YELLOW}开始下载部署脚本...${NC}"

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}此脚本需要root权限运行${NC}"
    echo "请使用: sudo bash $0"
    exit 1
fi

# 创建脚本目录
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# 下载脚本
echo -e "${YELLOW}正在下载主部署脚本...${NC}"
wget -O deploy-proxy-chain.sh "$GITHUB_RAW_URL/deploy-proxy-chain.sh" || \
    curl -o deploy-proxy-chain.sh "$GITHUB_RAW_URL/deploy-proxy-chain.sh"

echo -e "${YELLOW}正在下载管理脚本...${NC}"
wget -O proxy-manager.sh "$GITHUB_RAW_URL/proxy-manager.sh" || \
    curl -o proxy-manager.sh "$GITHUB_RAW_URL/proxy-manager.sh"

# 赋予执行权限
chmod +x deploy-proxy-chain.sh proxy-manager.sh

# 创建软链接
ln -sf $INSTALL_DIR/deploy-proxy-chain.sh /usr/local/bin/proxy-deploy
ln -sf $INSTALL_DIR/proxy-manager.sh /usr/local/bin/proxy-manager

echo -e "${GREEN}安装完成！${NC}"
echo -e "${YELLOW}使用方法:${NC}"
echo "  部署服务: proxy-deploy"
echo "  管理服务: proxy-manager"
echo ""
echo -e "${GREEN}现在开始部署? (y/n)${NC}"
read -p "> " start_deploy

if [[ "$start_deploy" == "y" || "$start_deploy" == "Y" ]]; then
    /usr/local/bin/proxy-deploy
else
    echo -e "${YELLOW}您可以随时运行 'proxy-deploy' 开始部署${NC}"
fi