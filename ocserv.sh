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
conf_file="/etc/ocserv"
conf="${conf_file}/ocserv.conf"
passwd_file="${conf_file}/ocpasswd"

Green='\033[32m' && Red='\033[31m' && Yellow='\033[33m' && NC='\033[0m'
Info="${Green}[信息]${NC}"
Error="${Red}[错误]${NC}"
Warn="${Yellow}[警告]${NC}"

# 检测系统
detect_sys(){
    if [[ -f /etc/centos-stream-release ]]; then
        echo "${Info} 检测到: CentOS Stream"
        release="centos-stream"
    elif [[ -f /etc/redhat-release ]]; then
        echo "${Info} 检测到: CentOS/RHEL"
        release="centos"
    elif [[ -f /etc/os-release ]]; then
        grep -q "CentOS Stream" /etc/os-release && echo "${Info} 检测到: CentOS Stream" && release="centos-stream"
        grep -q "ID=\"centos\"" /etc/os-release && echo "${Info} 检测到: CentOS" && release="centos"
    fi
    echo "${Info} 系统: ${release:-unknown}"
}

# 安装依赖
install_deps(){
    echo "${Info} 开始安装依赖..."
    
    if [[ "${release}" == "centos-stream" ]]; then
        echo "${Info} 使用 Copr 源安装..."
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
    
    echo "${Info} 安装完成"
}

# 配置
config_ocserv(){
    echo "${Info} 配置 ocserv..."
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
tunnel-all-dns = true
EOF
    
    # 生成证书
    if [[ ! -f "${conf_file}/server-cert.pem" ]]; then
        echo "${Info} 生成证书..."
        cd ${conf_file}
        openssl req -newkey rsa:2048 -nodes -keyout server-key.pem -x509 -days 3650 -out server-cert.pem -subj "/CN=VPN/O=小白" 2>/dev/null
    fi
    
    echo "${Info} 配置完成"
}

# 防火墙
config_firewall(){
    echo "${Info} 配置防火墙..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    if command -v firewall-cmd &>/dev/null; then
        # CentOS 7+ 使用 firewalld
        firewall-cmd --permanent --add-port=443/tcp 2>/dev/null
        firewall-cmd --permanent --add-port=443/udp 2>/dev/null
        # 开启NAT转发
        firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s 172.16.0.0/22 -j MASQUERADE 2>/dev/null
        firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -s 172.16.0.0/22 -j ACCEPT 2>/dev/null
        firewall-cmd --reload 2>/dev/null
    elif command -v iptables &>/dev/null; then
        # CentOS 6 或手动安装 iptables
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
        iptables -I INPUT -p udp --dport 443 -j ACCEPT 2>/dev/null
        iptables -t nat -A POSTROUTING -s 172.16.0.0/22 -j MASQUERADE 2>/dev/null
        iptables -I FORWARD -s 172.16.0.0/22 -j ACCEPT 2>/dev/null
        iptables -I FORWARD -d 172.16.0.0/22 -j ACCEPT 2>/dev/null
    fi
    echo "${Info} 防火墙配置完成"
}

# 启动
start_ocserv(){
    if [[ -f /var/run/ocserv.pid ]]; then
        echo "${Warn} ocserv 已在运行"
        return
    fi
    
    ocserv -f -c ${conf} &
    sleep 2
    
    if [[ -f /var/run/ocserv.pid ]]; then
        echo "${Info} ocserv 启动成功"
    else
        echo "${Error} ocserv 启动失败"
    fi
}

# 停止
stop_ocserv(){
    if [[ ! -f /var/run/ocserv.pid ]]; then
        echo "${Info} ocserv 未运行"
        return
    fi
    
    kill $(cat /var/run/ocserv.pid) 2>/dev/null
    rm -f /var/run/ocserv.pid
    echo "${Info} ocserv 已停止"
}

# 重启
restart_ocserv(){
    stop_ocserv
    sleep 1
    start_ocserv
}

# 状态
status_ocserv(){
    if [[ -f /var/run/ocserv.pid ]]; then
        echo "${Info} ocserv 运行中 (PID: $(cat /var/run/ocserv.pid))"
    else
        echo "${Info} ocserv 未运行"
    fi
}

# 添加用户
add_user(){
    read -p "用户名: " u
    read -p "密码: " p
    echo -e "${p}\n${p}" | ocpasswd -c ${passwd_file} $u 2>/dev/null
    echo "${Info} 用户 $u 添加成功"
}

# 删除用户
del_user(){
    read -p "用户名: " u
    ocpasswd -c ${passwd_file} -d $u 2>/dev/null
    echo "${Info} 用户 $u 已删除"
}

# 修改端口
set_port(){
    read -p "请输入端口 (默认443): " port
    port=${port:-443}
    sed -i "s/^tcp-port = .*/tcp-port = ${port}/" ${conf}
    sed -i "s/^udp-port = .*/udp-port = ${port}/" ${conf}
    echo "${Info} 端口已修改为: ${port}"
}

# 查看在线用户
view_users(){
    echo "========================================"
    echo "  在线用户"
    echo "========================================"
    
    if [[ ! -f /var/run/ocserv.pid ]]; then
        echo "${Info} ocserv 未运行"
        return
    fi
    
    # 使用ss检查连接
    connections=$(ss -tn | grep ":443 " | grep ESTABLISHED | wc -l)
    if [[ $connections -gt 0 ]]; then
        echo "当前在线用户数: $connections"
        ss -tn | grep ":443 " | grep ESTABLISHED
    else
        echo "当前无用户在线"
    fi
}

# 重新生成证书
regen_cert(){
    echo "${Info} 重新生成证书..."
    cd ${conf_file}
    rm -f server-cert.pem server-key.pem
    openssl req -newkey rsa:2048 -nodes -keyout server-key.pem -x509 -days 3650 -out server-cert.pem -subj "/CN=VPN/O=小白" 2>/dev/null
    echo "${Info} 证书已重新生成，请重启VPN"
}

# 卸载
uninstall_ocserv(){
    read -p "确定要卸载吗? (y/n): " c
    [[ $c != "y" ]] && return
    
    stop_ocserv
    rm -rf ${conf_file}
    rm -f /var/run/ocserv.pid
    echo "${Info} ocserv 已卸载"
}

# 菜单
menu(){
    clear
    echo "========================================"
    echo "  ocserv VPN 管理脚本"
    echo "  版本: 1.3.6"
    echo "========================================"
    echo "1.  安装 VPN"
    echo "2.  配置 VPN"
    echo "3.  启动 VPN"
    echo "4.  停止 VPN"
    echo "5.  重启 VPN"
    echo "6.  查看状态"
    echo "7.  添加用户"
    echo "8.  删除用户"
    echo "9.  修改端口"
    echo "10. 查看在线用户"
    echo "11. 重新生成证书"
    echo "12. 卸载 VPN"
    echo "0.  退出"
    echo "========================================"
    read -p "请输入选项 [0-12]: " choice
    
    case $choice in
        1)
            detect_sys
            install_deps
            config_ocserv
            config_firewall
            start_ocserv
            ;;
        2) config_ocserv ;;
        3) start_ocserv ;;
        4) stop_ocserv ;;
        5) restart_ocserv ;;
        6) status_ocserv ;;
        7) add_user ;;
        8) del_user ;;
        9) set_port ;;
        10) view_users ;;
        11) regen_cert ;;
        12) uninstall_ocserv ;;
        0) exit 0 ;;
    esac
    
    echo ""
    read -p "按回车继续..."
    menu
}

# 主程序
detect_sys
menu
