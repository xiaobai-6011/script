# Enterprise Networking - ocserv VPN 管理脚本

## 简介
OpenConnect VPN (ocserv) 一键安装管理脚本，支持多种Linux发行版。

## 支持系统
- CentOS 7/8
- RedHat
- Debian
- Ubuntu
- Alibaba Cloud / Aliyun
- Rocky Linux
- AlmaLinux

## 功能特性

### 基础功能
| 功能 | 说明 |
|------|------|
| 自动安装 | 一键安装ocserv及依赖 |
| 自动配置 | 生成配置文件和自签名证书 |
| 多用户管理 | 添加/删除VPN用户 |
| 开机自启 | 自动启动VPN服务 |

### 高级功能
| 功能 | 说明 |
|------|------|
| 自签名证书 | 自动获取服务器IP作为CN，组织：创泓度网络 |
| 流量统计 | 实时查看在线用户和流量使用 |
| 用户限速 | 可对单个用户进行带宽限制 |
| SSH Bypass | 全局模式下也能SSH连接服务器 |
| 防火墙配置 | 自动配置NAT和端口转发 |

## 使用方法

### 安装
```bash
wget https://raw.githubusercontent.com/xiaobai-6011/script/main/ocserv.sh
chmod +x ocserv.sh
./ocserv.sh
```

### 菜单选项
```
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
13. 设置限速
14. 重新生成证书
15. SSH bypass
16. 查看日志
17. 卸载 VPN
0. 退出
```

## 默认配置
- 端口：443 (TCP/UDP)
- 网段：172.16.0.0/22
- 认证：密码文件 (plain)

## 证书说明
默认使用自签名证书：
- CN = 服务器公网IP
- O = 创泓度网络
- 有效期：10年

## 更新日志
- v1.3.1: 优化用户限速和完全卸载
- v1.3.0: 添加流量统计和限速
- v1.2.0: 添加SSH Bypass功能
- v1.1.0: 全面兼容多系统

## 作者
- Author: XZ
- URL: https://chuanghongdu.com
