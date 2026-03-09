# ocserv VPN 一键安装管理脚本

## 版本

- **ocserv-v1.sh** - 基础版本 (精简版)
- **ocserv-v2.sh** - 增强版本 (支持多系统)
- **ocserv-v3.sh** - 最新版本 (法律声明版)

## 功能特性

- 支持 AlmaLinux、CentOS、Debian、Ubuntu
- 支持密码认证
- 流量统计
- 用户管理 (添加/删除)
- 防火墙自动配置
- 证书自动生成

## 安装

```bash
wget https://raw.githubusercontent.com/xiaobai-6011/script/main/ocserv-v3.sh
chmod +x ocserv-v3.sh
./ocserv-v3.sh
```

## 配置说明

### 配置文件

- 证书位置: `/etc/ocserv/`
- 密码文件: `/etc/ocserv/ocpasswd`
- 日志文件: `/var/log/ocserv.log`

### 主要配置项

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| dns | 9.9.9.9, 223.5.5.5 | DNS服务器 |
| max-same-clients | 1 | 单账号最大连接数 |
| idle-timeout | 0 | 空闲超时(0=无限) |
| dpd | 60 | 死亡检测间隔(秒) |
| banner | 法律声明 | 登录提示 |

## 使用

```bash
# 安装
./ocserv-v3.sh
# 输入 1 安装

# 启动
./ocserv-v3.sh
# 输入 2 启动

# 添加用户
./ocserv-v3.sh
# 输入 3 添加用户

# 查看用户
./ocserv-v3.sh
# 输入 10 查看用户

# 卸载
./ocserv-v3.sh
# 输入 16 卸载
```

## 注意事项

1. 请使用ROOT用户运行
2. 首次安装会自动生成证书
3. 添加用户后即可使用AnyConnect客户端连接

## 客户端下载

- Windows: https://itunes.apple.com/us/app/anyconnect/id543506249
- iOS: App Store 搜索 "Cisco AnyConnect"
- Android: Google Play 搜索 "AnyConnect"

## 许可证

See LICENSE file

## 作者

chuanghongdu.com
