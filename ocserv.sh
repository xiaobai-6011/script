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
    echo "[信息] 系统: ${release:-unknown}"
}

# 安装依赖
install_deps(){
    echo "[信息] 开始安装依赖..."
    
    if [[ "${release}" == "centos-stream" ]]; then
        echo "[信息] 使用 Copr 源安装..."
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
    
    echo "[信息] 安装完成"
}

# 配置
config_ocserv(){
    echo "[信息] 配置 ocserv..."
    mkdir -p ${conf_file}
    
    cat > ${conf} << 'EOF'
auth = "plain[${passwd_file}]"
tcp-port = 443
udp-port = 443
socket-file = /var/run/ocserv.socket
pid-file = /var/run/ocserv.pid
server-cert = ${conf_file}/server-cert.pem
server-key = ${conf_file}/server-key.pem
device = vpns
ipv4-network = 172.16.0.0
ipv4-netmask = 255.255.252.0
dns = 8.8.8.8
keepalive = 990
mtu = 1400
max-clients = 0
EOF
    
    # 生成证书
    if [[ ! -f "${conf_file}/server-cert.pem" ]]; then
        echo "[信息] 生成证书..."
        cd ${conf_file}
        openssl req -newkey rsa:2048 -nodes -keyout server-key.pem -x509 -days 3650 -out server-cert.pem -subj "/CN=VPN/O=小白" 2>/dev/null
    fi
    
    echo "[信息] 配置完成"
}

# 防火墙
config_firewall(){
    echo "[信息] 配置防火墙..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port=443/tcp 2>/dev/null
        firewall-cmd --permanent --add-port=443/udp 2>/dev/null
        firewall-cmd --reload 2>/dev/null
    elif command -v iptables &>/dev/null; then
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
        iptables -I INPUT -p udp --dport 443 -j ACCEPT 2>/dev/null
        iptables -t nat -A POSTROUTING -s 172.16.0.0/22 -j MASQUERADE 2>/dev/null
    fi
    echo "[信息] 防火墙配置完成"
}

# 启动
start_ocserv(){
    if [[ -f /var/run/ocserv.pid ]]; then
        echo "[警告] ocserv 已在运行"
        return
    fi
    
    ocserv -f -c ${conf} &
    sleep 2
    
    if [[ -f /var/run/ocserv.pid ]]; then
        echo "[信息] ocserv 启动成功"
    else
        echo "[错误] ocserv 启动失败"
    fi
}

# 停止
stop_ocserv(){
    if [[ ! -f /var/run/ocserv.pid ]]; then
        echo "[信息] ocserv 未运行"
        return
    fi
    
    kill $(cat /var/run/ocserv.pid) 2>/dev/null
    rm -f /var/run/ocserv.pid
    echo "[信息] ocserv 已停止"
}

# 添加用户
add_user(){
    read -p "用户名: " u
    read -p "密码: " p
    echo -e "${p}\n${p}" | ocpasswd -c ${passwd_file} $u 2>/dev/null
    echo "[信息] 用户 $u 添加成功"
}

# 菜单
menu(){
    echo ""
    echo "========================================"
    echo "  ocserv VPN 管理脚本"
    echo "  版本: 1.3.6"
    echo "========================================"
    echo "1. 安装 VPN (推荐)"
    echo "2. 启动 VPN"
    echo "3. 停止 VPN"
    echo "4. 添加用户"
    echo "5. 查看状态"
    echo "0. 退出"
    echo "========================================"
    read -p "请输入选项 [0-5]: " choice
    
    case $choice in
        1)
            detect_sys
            install_deps
            config_ocserv
            config_firewall
            start_ocserv
            ;;
        2) start_ocserv ;;
        3) stop_ocserv ;;
        4) add_user ;;
        5) 
            if [[ -f /var/run/ocserv.pid ]]; then
                echo "[信息] ocserv 运行中 (PID: $(cat /var/run/ocserv.pid))"
            else
                echo "[信息] ocserv 未运行"
            fi
            ;;
        0) exit 0 ;;
    esac
    
    echo ""
    read -p "按回车继续..."
    menu
}

# 主程序
detect_sys
menu
