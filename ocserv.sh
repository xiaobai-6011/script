#!/bin/bash
# ocserv VPN 管理脚本 v1.4.0

if [[ $EUID -ne 0 ]]; then
   echo -e "\033[31m[错误] 请使用ROOT用户运行\033[0m"
   exit 1
fi

log_file="/tmp/ocserv.log"
PID_FILE="/var/run/ocserv.pid"
conf_file="/etc/ocserv"
conf="${conf_file}/ocserv.conf"
passwd_file="${conf_file}/ocpasswd"

detect_sys(){
    if [[ -f /etc/almalinux-release ]]; then
        ver=$(cat /etc/almalinux-release | grep -oP '\d+' | head -1)
        echo -e "\033[32m[信息]\033[0m 检测到: AlmaLinux $ver"
        [[ "$ver" == "10" ]] && release="almalinux10" || release="centos"
    elif [[ -f /etc/centos-stream-release ]]; then
        echo -e "\033[32m[信息]\033[0m 检测到: CentOS Stream"
        release="centos-stream"
    elif [[ -f /etc/debian_version ]]; then
        echo -e "\033[32m[信息]\033[0m 检测到: Debian"
        release="debian"
    elif [[ -f /etc/lsb-release ]]; then
        . /etc/lsb-release
        [[ "$DISTRIB_ID" == "Ubuntu" ]] && echo -e "\033[32m[信息]\033[0m 检测到: Ubuntu" && release="ubuntu"
    fi
    echo -e "\033[32m[信息]\033[0m 系统: ${release:-unknown}"
}

install_deps(){
    echo -e "\033[32m[信息]\033[0m 开始安装..."
    
    if [[ "${release}" == "centos-stream" ]] || [[ "${release}" == "almalinux10" ]]; then
        dnf install -y dnf-plugins-core 2>/dev/null
        dnf copr enable -y @ocserv/ocserv 2>/dev/null
        dnf install -y ocserv 2>/dev/null
    elif [[ "${release}" == "centos" ]]; then
        yum install -y epel-release 2>/dev/null
        yum install -y ocserv 2>/dev/null || dnf install -y ocserv 2>/dev/null
    else
        apt-get update
        apt-get install -y ocserv
    fi
    echo -e "\033[32m[信息]\033[0m 安装完成"
}

config_ocserv(){
    echo -e "\033[32m[信息]\033[0m 配置..."
    mkdir -p ${conf_file}
    cat > ${conf} << EOF
auth = "plain[${passwd_file}]"
tcp-port = 443
udp-port = 443
socket-file = /var/run/ocserv.socket
pid-file = /var/run/ocserv.pid
server-cert = /etc/ocserv/server-cert.pem
server-key = /etc/ocserv/server-key.pem
device = vpns
ipv4-network = 172.16.0.0
ipv4-netmask = 255.255.252.0
dns = 8.8.8.8
dns = 114.114.114.114
keepalive = 990
mtu = 1400
max-clients = 0
EOF
    cd ${conf_file}
    openssl req -newkey rsa:2048 -nodes -keyout server-key.pem -x509 -days 3650 -out server-cert.pem -subj "/CN=VPN/O=小白" 2>/dev/null
    chmod 600 server-key.pem
    echo -e "\033[32m[信息]\033[0m 配置完成"
}

config_firewall(){
    echo -e "\033[32m[信息]\033[0m 防火墙..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    if command -v iptables >/dev/null 2>&1; then
        iptables -t nat -A POSTROUTING -s 172.16.0.0/22 -j MASQUERADE
        iptables -A FORWARD -i vpns0 -j ACCEPT
        iptables -A FORWARD -o vpns0 -j ACCEPT
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT
        iptables -A INPUT -p udp --dport 443 -j ACCEPT
    elif command -v nft >/dev/null 2>&1; then
        nft add table ip nat 2>/dev/null
        nft add chain ip nat postrouting type nat hook postrouting priority srcnat 2>/dev/null
        nft add rule ip nat postrouting ip saddr 172.16.0.0/22 masquerade 2>/dev/null
        nft add table ip filter 2>/dev/null
        nft add chain ip filter forward type filter hook forward priority filter 2>/dev/null
        nft add rule ip filter forward iifname vpns0 accept 2>/dev/null
        nft add rule ip filter forward oifname vpns0 accept 2>/dev/null
    fi
    echo -e "\033[32m[信息]\033[0m 防火墙完成"
}

start_ocserv(){
    if [[ -f /var/run/ocserv.pid ]]; then
        echo -e "\033[33m[警告]\033[0m 已在运行"
        return
    fi
    ocserv -f -c ${conf} &
    sleep 2
    if [[ -f /var/run/ocserv.pid ]]; then
        echo -e "\033[32m[信息]\033[0m 启动成功"
    else
        echo -e "\033[31m[错误]\033[0m 启动失败"
    fi
}

stop_ocserv(){
    [[ -f /var/run/ocserv.pid ]] && kill $(cat /var/run/ocserv.pid) 2>/dev/null
    rm -f /var/run/ocserv.pid
    echo -e "\033[32m[信息]\033[0m 已停止"
}

add_user(){
    read -p "用户名: " u
    read -p "密码: " p
    echo -e "${p}\n${p}" | ocpasswd -c ${passwd_file} $u 2>/dev/null
    echo -e "\033[32m[信息]\033[0m 用户添加成功"
}

uninstall_ocserv(){
    echo "将删除: ocserv软件 用户 证书 日志 防火墙规则"
    read -p "确定卸载? (y/n): " c
    [[ $c != "y" ]] && return
    
    stop_ocserv
    rm -rf ${conf_file} /var/run/ocserv.socket ${log_file}
    
    if command -v iptables >/dev/null 2>&1; then
        iptables -t nat -D POSTROUTING -s 172.16.0.0/22 -j MASQUERADE 2>/dev/null
        iptables -D FORWARD -i vpns0 -j ACCEPT 2>/dev/null
    fi
    
    if command -v dnf >/dev/null; then
        dnf remove -y ocserv 2>/dev/null
    elif command -v yum >/dev/null; then
        yum remove -y ocserv 2>/dev/null
    elif command -v apt >/dev/null; then
        apt remove -y ocserv 2>/dev/null
    fi
    echo -e "\033[32m[信息]\033[0m 已卸载"
}

menu(){
    clear
    echo "========================================"
    echo "  ocserv VPN 管理脚本 v1.4.0"
    echo "========================================"
    echo "1. 安装 VPN"
    echo "2. 启动 VPN"
    echo "3. 停止 VPN"
    echo "4. 添加用户"
    echo "5. 卸载 VPN"
    echo "0. 退出"
    read -p "选择: " c
    case $c in
        1) detect_sys; install_deps; config_ocserv; config_firewall; start_ocserv ;;
        2) start_ocserv ;;
        3) stop_ocserv ;;
        4) add_user ;;
        5) uninstall_ocserv ;;
        0) exit 0 ;;
    esac
    read -p "完成"
    menu
}

detect_sys
menu
