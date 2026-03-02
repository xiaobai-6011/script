# 脚本说明

## ocserv VPN 安装脚本

### 功能特性
- 支持系统：Debian/Ubuntu/CentOS/RedHat/AlibabaCloud
- 支持最多1017个并发连接 (/22网段)
- 内网分流模式
- 自动配置开机自启
- 中文菜单操作

### 使用方法

```bash
# 下载脚本
wget https://raw.githubusercontent.com/xiaobai-6011/script/main/ocserv.sh

# 添加执行权限
chmod +x ocserv.sh

# 运行安装
sudo ./ocserv.sh
```

### 菜单功能
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
sudo ./ocserv.sh install     # 安装
sudo ./ocserv.sh start      # 启动
sudo ./ocserv.sh stop       # 停止
sudo ./ocserv.sh restart    # 重启
sudo ./ocserv.sh status     # 状态
sudo ./ocserv.sh add user pass   # 添加用户
sudo ./ocserv.sh del user        # 删除用户
sudo ./ocserv.sh set-welcome     # 修改欢迎信息
sudo ./ocserv.sh users          # 查看在线用户
sudo ./ocserv.sh port           # 修改端口
sudo ./ocserv.sh regen-cert     # 重新生成证书
sudo ./ocserv.sh log           # 查看日志
sudo ./ocserv.sh uninstall     # 卸载
```

### 默认配置
- 端口：443
- 网段：172.16.0.0/22 (1017个IP)
- DNS：8.8.8.8, 114.114.114.114

### 客户端下载
- Windows: Cisco AnyConnect
- macOS: Cisco AnyConnect
- iOS: Cisco AnyConnect
- Android: Cisco AnyConnect

### 联系作者
- 网站: https://chuanghongdu.com
