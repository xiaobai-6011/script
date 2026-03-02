# 脚本合集

## ocserv.sh - OpenConnect VPN 管理脚本

### 功能
- 支持系统：Debian/Ubuntu/CentOS/RedHat/AlibabaCloud/Rocky/Alma
- 自动化安装配置
- 多用户管理
- 防火墙自动配置
- 开机自启

### 支持的Linux发行版
- CentOS 6/7/8
- RedHat
- Debian
- Ubuntu
- Alibaba Cloud / Aliyun
- Rocky Linux
- AlmaLinux

### 安装
```bash
wget https://raw.githubusercontent.com/xiaobai-6011/script/main/ocserv.sh
chmod +x ocserv.sh
./ocserv.sh
```

### 菜单选项
1. 安装 VPN
2. 配置 VPN
3. 启动 VPN
4. 停止 VPN
5. 重启 VPN
6. 查看状态
7. 添加用户
8. 删除用户
9. 修改欢迎信息
10. 查看在线用户
11. 流量统计
12. 修改端口
13. 重新生成证书
14. 查看日志
15. 卸载 VPN

### 命令行用法
```bash
./ocserv.sh install    # 安装
./ocserv.sh start      # 启动
./ocserv.sh stop       # 停止
./ocserv.sh restart    # 重启
./ocserv.sh status     # 状态
./ocserv.sh add user password  # 添加用户
./ocserv.sh del user   # 删除用户
```

### 默认配置
- 端口：443
- 网段：172.16.0.0/22
- 欢迎信息：创泓度网络
- 自动检测系统并配置防火墙

### 版本
- v1.0.3 - 恢复15个菜单选项，增强系统兼容性
- v1.0.2 - 全面兼容所有系统
- v1.0.1 - 修复语法错误
- v1.0.0 - 初始版本
