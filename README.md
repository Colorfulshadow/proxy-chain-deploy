# Reality + Hysteria2 代理链部署系统

一个完整的代理链自动化部署解决方案，支持 Reality + Hysteria2 + SOCKS5 三层架构。

## 🌟 特性

- **三层架构设计**
  - 国内机：Reality + Hysteria2 客户端
  - 中转机：Hysteria2 服务端
  - 落地机：SOCKS5 代理
- **自动化部署**：一键安装配置所有组件
- **网络优化**：自动优化系统网络参数，启用 BBR
- **服务管理**：完善的 systemd 服务配置，支持开机自启
- **监控工具**：配套的管理脚本，方便日常维护

## 📋 系统要求

- 操作系统：Ubuntu 18.04+ / Debian 10+
- 权限要求：root 权限
- 网络要求：服务器需要有公网 IP

## 🚀 快速开始

### 方法一：在线安装（推荐）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/proxy-chain-deploy/main/install.sh)
```

### 方法二：手动安装

1. 下载项目文件
```bash
git clone https://github.com/YOUR_USERNAME/proxy-chain-deploy.git
cd proxy-chain-deploy
chmod +x *.sh
```

2. 运行部署脚本
```bash
./deploy-proxy-chain.sh
```

## 📖 使用说明

### 部署流程

1. **部署落地机**（最先部署）
   - 选择菜单选项 3
   - 记录 SOCKS5 地址和端口

2. **部署中转机**
   - 选择菜单选项 2
   - 输入落地机的 SOCKS5 信息
   - 记录 Hysteria2 服务信息

3. **部署国内机**
   - 选择菜单选项 1
   - 输入中转机的 Hysteria2 信息
   - 获取 Reality 连接配置

### 客户端配置

部署完成后，使用支持 VLESS + Reality 的客户端，配置信息如下：

```
协议：VLESS
地址：国内机 IP
端口：443（或自定义端口）
UUID：部署时生成的 UUID
Flow：xtls-rprx-vision
传输协议：TCP
安全：Reality
SNI：apple.com
Public Key：部署时显示的公钥
Short ID：部署时生成的 ID
```

## 🛠️ 管理工具

部署完成后，使用管理工具进行日常维护：

```bash
proxy-manager
```

功能包括：
- 查看服务状态
- 查看实时日志
- 重启服务
- 查看/备份配置
- 流量统计
- 性能监控
- 更新服务

## 📁 文件结构

```
/opt/proxy-chain/
├── xray/              # Xray 程序文件
├── hysteria2/         # Hysteria2 程序文件
├── config/            # 配置文件目录
│   ├── xray.json
│   ├── hysteria2-client.yaml
│   ├── hysteria2-server.yaml
│   └── certs/        # 证书文件
├── logs/             # 日志文件
└── backups/          # 配置备份

/opt/proxy-chain-scripts/
├── deploy-proxy-chain.sh    # 主部署脚本
├── proxy-manager.sh         # 管理工具
└── install.sh              # 快速安装脚本
```

## 🔧 技术细节

### 网络优化参数

脚本会自动优化以下系统参数：
- TCP 缓冲区大小
- 启用 BBR 拥塞控制
- 优化连接数限制
- 调整 TIME_WAIT 参数
- 启用 TCP Fast Open

### 安全配置

- 自动配置 UFW 防火墙规则
- 仅开放必要端口
- Reality 协议提供强大的抗检测能力
- Hysteria2 使用 QUIC 协议，UDP 传输更难被识别

## ❓ 常见问题

### 1. 部署失败怎么办？

检查：
- 是否有 root 权限
- 服务器网络是否正常
- 防火墙是否阻止了必要端口

### 2. 如何查看服务日志？

```bash
# 使用管理工具
proxy-manager
# 选择选项 2 查看日志

# 或直接使用 journalctl
journalctl -u xray -f
journalctl -u hysteria2-client -f
journalctl -u hysteria2-server -f
journalctl -u 3proxy -f
```

### 3. 如何更新配置？

1. 编辑配置文件：
```bash
nano /opt/proxy-chain/config/xray.json
nano /opt/proxy-chain/config/hysteria2-client.yaml
```

2. 重启服务：
```bash
proxy-manager
# 选择选项 3 重启服务
```

### 4. 如何卸载？

```bash
# 停止并禁用服务
systemctl stop xray hysteria2-client hysteria2-server 3proxy
systemctl disable xray hysteria2-client hysteria2-server 3proxy

# 删除文件
rm -rf /opt/proxy-chain
rm -rf /opt/proxy-chain-scripts
rm -f /usr/local/bin/proxy-deploy
rm -f /usr/local/bin/proxy-manager

# 删除服务文件
rm -f /etc/systemd/system/xray.service
rm -f /etc/systemd/system/hysteria2-*.service
rm -f /etc/systemd/system/3proxy.service
```

## 🔐 安全建议

1. **定期更新**：使用管理工具的更新功能保持程序最新
2. **备份配置**：定期备份重要配置文件
3. **监控日志**：定期检查服务日志，发现异常及时处理
4. **限制访问**：考虑使用防火墙限制管理端口的访问来源

## 📝 注意事项

1. **部署顺序**：必须按照 落地机 → 中转机 → 国内机 的顺序部署
2. **端口选择**：建议使用高位端口（20000-50000），避免常用端口
3. **密码安全**：Hysteria2 密码建议使用强密码
4. **备份重要信息**：部署完成后及时保存连接信息

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## ⚖️ 免责声明

本项目仅供学习和研究使用，请遵守当地法律法规。作者不对使用本项目造成的任何后果负责。

## 📄 许可证

MIT License