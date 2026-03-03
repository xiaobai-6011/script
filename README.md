# ocserv VPN 管理脚本

## 简介
OpenConnect VPN (ocserv) 一键安装管理脚本，支持多种Linux发行版的企业级VPN解决方案。

## 支持系统
| 系统 | 版本 | 包管理器 | 源配置 |
|------|------|----------|---------|
| AlmaLinux | 9/10 | DNF | EPEL → Copr → 阿里云 → 清华 |
| CentOS Stream | 9/10 | DNF | EPEL → Copr → 阿里云 → 清华 |
| CentOS | 7/8 | YUM | Vault源 → EPEL → 阿里云 → 清华 |
| Debian | 11/12/13 | APT | 官方 → 阿里云 → 清华 |
| Ubuntu | 22.04/24.04 | APT | 官方 → 阿里云 → 清华 |

## 功能特性

### 核心功能
- ✅ 自动检测系统并匹配安装方式
- ✅ 多源自动切换（源失败自动尝试下一个）
- ✅ 自签名证书（随机CN+随机组织，有效期1年）
- ✅ 防火墙自动配置（nftables/firewalld/iptables）
- ✅ 多用户管理
- ✅ NAT流量转发

### 菜单功能
| 选项 | 功能 |
|------|------|
| 1 | 安装VPN |
| 2 | 启动VPN |
| 3 | 停止VPN |
| 4 | 重启VPN |
| 5 | 查看状态 |
| 6 | 添加用户 |
| 7 | 删除用户 |
| 8 | 修改端口 |
| 9 | 查看在线用户 |
| 10 | 重新生成证书 |
| 11 | 查看日志 |
| 12 | 修复网络 |
| 13 | 卸载VPN |
| 0 | 退出 |

## 安装方法

```bash
# 下载脚本
wget -N https://raw.githubusercontent.com/xiaobai-6011/script/main/ocserv.sh
chmod +x ocserv.sh

# 运行脚本
./ocserv.sh
```

## 默认配置
| 配置项 | 默认值 |
|--------|--------|
| 端口 | 443 (TCP/UDP) |
| VPN网段 | 172.16.0.0/22 |
| DNS | 8.8.8.8, 114.114.114.114 |
| 认证方式 | 密码文件 (plain) |
| 证书有效期 | 1年 |

## 证书说明
- 生成方式: 随机8位字母作为CN + 随机5位字母作为组织
- 可选自定义: 生成证书时可自定义CN和组织名称
- 有效期: 365天（1年）

## 防火墙支持
脚本自动检测并配置：
1. **nftables** (AlmaLinux 10, CentOS Stream 10)
2. **firewalld** (CentOS 7/8, RHEL)
3. **iptables** (Debian, Ubuntu, 兼容模式)

## 安装源优先级
- 优先使用官方源
- 失败则自动切换备用源
- 支持: 官方、EPEL、Copr、阿里云、清华、网易、腾讯云、华为云

## 常见问题

### Q: 连接后无法上网
A: 检查防火墙NAT规则，确保已开启IP转发

### Q: 证书安全警告
A: 自签名证书，客户端需要接受或安装证书

### Q: CentOS 7安装失败
A: 确保EPEL仓库已启用，尝试: yum install -y epel-release

## 更新日志
- v1.4.0: 优化源配置，CentOS 7/8使用Vault源，证书随机生成
- v1.3.x: 添加流量统计、用户限速、SSH bypass
- v1.2.x: 完善多系统兼容

## 下载
- 主版本: https://raw.githubusercontent.com/xiaobai-6011/script/main/ocserv.sh
- 测试版: https://raw.githubusercontent.com/xiaobai-6011/script/dev/ocserv.sh

## 作者
- GitHub: https://github.com/xiaobai-6011/script
