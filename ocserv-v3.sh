#!/bin/bash
# ocserv VPN 管理脚本 v1.3.6
# 支持: CentOS 7/8/10, Rocky, AlmaLinux, Debian, Ubuntu

# 检查root
if [[ $EUID -ne 0 ]]; then
   echo "[错误] 请使用ROOT用户运行"
   exit 1
fi

# 变量
log_file="/tmp/ocserv.log"
PID_FILE="/var/run/ocserv.pid"

# 检测系统
detect_sys(){
    if [[ -f /etc/centos-stream-release ]]; then
        echo "[信息] 检测到: CentOS Stream"
        release="centos-stream"
    elif [[ -f /etc/redhat-release ]]; then
        echo "[信息] 检测到: CentOS/RHEL"
        release="centos"
    elif [[ -f /etc/os-release ]]; then
        grep -q "CentOS Stream" /etc/os-release && echo "[信息] 检测到: CentOS Stream" && release="centos-stream"
        grep -q "ID=\"centos\"" /etc/os-release && echo "[信息] 检测到: CentOS" && release="centos"
    fi
}

detect_sys

# 菜单
menu(){
    echo "========================================"
    echo "  ocserv VPN 管理脚本"
    echo "  版本: 1.3.6"
    echo "========================================"
    echo "1. 安装 VPN"
    echo "2. 启动 VPN"
    echo "3. 停止 VPN"
    echo "4. 查看状态"
    echo "0. 退出"
    echo "========================================"
    read -p "请输入选项 [0-4]: " choice
    
    case $choice in
        1) echo "安装功能..." ;;
        2) echo "启动功能..." ;;
        3) echo "停止功能..." ;;
        4) echo "状态功能..." ;;
        0) exit 0 ;;
    esac
    
    read -p "按回车继续..."
    menu
}

menu
