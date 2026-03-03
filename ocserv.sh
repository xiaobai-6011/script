#!/bin/bash
# ocserv VPN 管理脚本 v1.4.0
# 支持: AlmaLinux 10, CentOS Stream, CentOS 7/8, Debian, Ubuntu

# 检查root
if [[ $EUID -ne 0 ]]; then
   echo -e "\033[31m[错误] 请使用ROOT用户运行\033[0m"
   exit 1
fi

# 变量
conf_file="/etc/ocserv"
conf="${conf_file}/ocserv.conf"
passwd_file="${conf_file}/ocpasswd"
log_file="/var/log/ocserv.log"

# 全局防火墙变量
FIREWALL=""

# 生成随机字符串
gen_random(){
    tr -dc 'a-zA-Z' </dev/urandom | head -c $1
}

# 检测系统
detect_sys(){
    echo "========================================"
    echo "========== 步骤1: 检测系统 =========="
    echo "========================================"
    
    # 检测系统版本
    if [[ -f /etc/almalinux-release ]]; then
        ver=$(cat /etc/almalinux-release | grep -oP '\d+' | head -1)
        echo -e "\033[32m[信息]\033[0m 检测到: AlmaLinux $ver"
        [[ "$ver" == "10" ]] && release="almalinux10" || release="centos"
    elif [[ -f /etc/centos-stream-release ]]; then
        echo -e "\033[32m[信息]\033[0m 检测到: CentOS Stream"
        release="centos-stream"
    elif [[ -f /etc/redhat-release ]]; then
        ver=$(cat /etc/redhat-release | grep -oP '\d+' | head -1)
        echo -e "\033[32m[信息]\033[0m 检测到: CentOS/RHEL $ver"
        # CentOS 10+ 使用 DNF
        [[ "$ver" == "10" ]] && release="centos-stream" || release="centos"
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "centos" ]]; then
            echo -e "\033[32m[信息]\033[0m 检测到: CentOS $VERSION_ID"
            [[ "$VERSION_ID" == "10" ]] && release="centos-stream" || release="centos"
        fi
    elif [[ -f /etc/debian_version ]]; then
        echo -e "\033[32m[信息]\033[0m 检测到: Debian"
        release="debian"
    elif [[ -f /etc/lsb-release ]]; then
        . /etc/lsb-release
        [[ "$DISTRIB_ID" == "Ubuntu" ]] && echo -e "\033[32m[信息]\033[0m 检测到: Ubuntu" && release="ubuntu"
    fi
    
    echo -e "\033[32m[√]\033[0m 系统: ${release:-unknown}"
}

# 安装依赖
install_deps(){
    echo "========================================"
    echo "========== 步骤2: 安装依赖 =========="
    echo "========================================"
    
    # 检查ocserv是否已安装
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m ocserv 已安装"
    else
        if [[ "${release}" == "almalinux10" ]] || [[ "${release}" == "centos-stream" ]]; then
            install_ocserv_dnf
        elif [[ "${release}" == "centos" ]]; then
            install_ocserv_yum
        else
            install_ocserv_apt
        fi
    fi
    
    # 安装防火墙
    install_firewall
    echo -e "\033[32m[√]\033[0m 依赖安装完成"
}

# DNF安装 (AlmaLinux 10, CentOS Stream)
install_ocserv_dnf(){
    echo -e "\033[32m[信息]\033[0m 使用 DNF 安装..."
    
    # 源1: EPEL
    echo -e "\033[32m[信息]\033[0m 尝试源1: EPEL..."
    dnf install -y epel-release 2>/dev/null
    dnf install -y crb 2>/dev/null
    dnf install -y ocserv 2>/dev/null
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 源1(EPEL) 成功"
        return
    fi
    
    # 源2: Copr
    echo -e "\033[33m[警告]\033[0m 源1失败，尝试源2: Copr..."
    dnf install -y dnf-plugins-core 2>/dev/null
    dnf copr enable -y @ocserv/ocserv 2>/dev/null
    dnf install -y ocserv 2>/dev/null
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 源2(Copr) 成功"
        return
    fi
    
    # 源3: 阿里云
    echo -e "\033[33m[警告]\033[0m 源2失败，尝试源3: 阿里云..."
    cat > /etc/yum.repos.d/almalinux.repo << 'EOF'
[base]
name=AlmaLinux-$releasever - Base
baseurl=https://mirrors.aliyun.com/almalinux/$releasever/BaseOS/$basearch/os/
gpgcheck=0
[appstream]
name=AlmaLinux-$releasever - AppStream
baseurl=https://mirrors.aliyun.com/almalinux/$releasever/AppStream/$basearch/os/
gpgcheck=0
EOF
    dnf clean all 2>/dev/null
    dnf install -y ocserv 2>/dev/null
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 源3(阿里云) 成功"
        return
    fi
    
    # 源4: 清华
    echo -e "\033[33m[警告]\033[0m 源3失败，尝试源4: 清华..."
    cat > /etc/yum.repos.d/almalinux.repo << 'EOF'
[base]
name=AlmaLinux-$releasever - Base
baseurl=https://mirrors.tuna.tsinghua.edu.cn/almalinux/$releasever/BaseOS/$basearch/os/
gpgcheck=0
[appstream]
name=AlmaLinux-$releasever - AppStream
baseurl=https://mirrors.tuna.tsinghua.edu.cn/almalinux/$releasever/AppStream/$basearch/os/
gpgcheck=0
EOF
    dnf clean all 2>/dev/null
    dnf install -y ocserv 2>/dev/null
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 源4(清华) 成功"
        return
    fi
    
    echo -e "\033[31m[错误]\033[0m 安装失败"
    exit 1
}

# YUM安装 (CentOS 7/8) - 先配置源再装EPEL
install_ocserv_yum(){
    echo -e "\033[32m[信息]\033[0m 使用 YUM 安装..."
    
    # 检测版本
    if [[ -f /etc/redhat-release ]]; then
        ver=$(cat /etc/redhat-release | grep -oP '\d+' | head -1)
        
        # CentOS 7/8 用Vault源
        if [[ "$ver" == "7" ]] || [[ "$ver" == "8" ]]; then
            echo -e "\033[32m[信息]\033[0m 检测到 CentOS $ver，配置Vault源..."
            cat > /etc/yum.repos.d/CentOS-Vault.repo << EOF
[base]
name=CentOS-$ver - Base
baseurl=http://vault.centos.org/${ver}.9/BaseOS/x86_64/os/
gpgcheck=0
enabled=1
[appstream]
name=CentOS-$ver - AppStream
baseurl=http://vault.centos.org/${ver}.9/AppStream/x86_64/os/
gpgcheck=0
enabled=1
EOF
            yum clean all 2>/dev/null
        fi
    fi
    
    # 安装EPEL
    echo -e "\033[32m[信息]\033[0m 安装EPEL..."
    yum install -y epel-release 2>/dev/null
    yum install -y ocserv 2>/dev/null
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m EPEL安装成功"
        return
    fi
    
    # 阿里云
    echo -e "\033[33m[警告]\033[0m 失败，尝试阿里云..."
    cat > /etc/yum.repos.d/CentOS-Base.repo << 'EOF'
[base]
name=CentOS-$releasever - Base
baseurl=https://mirrors.aliyun.com/centos/$releasever/os/$basearch/
gpgcheck=0
enabled=1
[updates]
name=CentOS-$releasever - Updates
baseurl=https://mirrors.aliyun.com/centos/$releasever/updates/$basearch/
gpgcheck=0
enabled=1
EOF
    yum clean all 2>/dev/null
    yum install -y ocserv 2>/dev/null
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 阿里云成功"
        return
    fi
    
    echo -e "\033[31m[错误]\033[0m 安装失败"
    exit 1
}

# APT安装 (Debian/Ubuntu)
install_ocserv_apt(){
    echo -e "\033[32m[信息]\033[0m 使用 APT 安装..."
    
    # 官方源
    echo -e "\033[32m[信息]\033[0m 尝试官方源..."
    if [[ -f /etc/apt/sources.list.bak ]]; then
        cp /etc/apt/sources.list.bak /etc/apt/sources.list 2>/dev/null
    fi
    apt-get update 2>/dev/null
    apt-get install -y ocserv 2>/dev/null
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 官方源成功"
        return
    fi
    
    # 阿里云
    echo -e "\033[33m[警告]\033[0m 失败，尝试阿里云..."
    if [[ "${release}" == "ubuntu" ]]; then
        cat > /etc/apt/sources.list << 'EOF'
deb https://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse
EOF
    else
        cat > /etc/apt/sources.list << 'EOF'
deb https://mirrors.aliyun.com/debian/ bookworm main contrib non-free
deb https://mirrors.aliyun.com/debian/ bookworm-updates main contrib non-free
deb https://mirrors.aliyun.com/debian-security/ bookworm-security main contrib non-free
EOF
    fi
    apt-get update 2>/dev/null
    apt-get install -y ocserv 2>/dev/null
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 阿里云成功"
        return
    fi
    
    echo -e "\033[31m[错误]\033[0m 安装失败"
    exit 1
}

# 安装防火墙
install_firewall(){
    echo -e "\033[32m[信息]\033[0m 检查防火墙..."
    
    if command -v nft >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 已有 nftables"
        FIREWALL="nft"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 已有 firewalld"
        FIREWALL="firewall"
    elif command -v iptables >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 已有 iptables"
        FIREWALL="iptables"
    else
        echo -e "\033[33m[警告]\033[0m 无防火墙，安装..."
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y nftables iptables-services firewalld 2>/dev/null
        elif command -v apt >/dev/null 2>&1; then
            apt install -y iptables 2>/dev/null
        fi
    fi
    
    if command -v nft >/dev/null 2>&1; then FIREWALL="nft"
    elif command -v firewall-cmd >/dev/null 2>&1; then FIREWALL="firewall"
    elif command -v iptables >/dev/null 2>&1; then FIREWALL="iptables"
    fi
}

# 配置防火墙
config_firewall(){
    echo "========================================"
    echo "========== 步骤4: 配置防火墙 =========="
    echo "========================================"
    
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf 2>/dev/null
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf 2>/dev/null
    
    if [[ "$FIREWALL" == "nft" ]]; then
        config_nftables
    elif [[ "$FIREWALL" == "firewall" ]]; then
        config_firewalld
    elif [[ "$FIREWALL" == "iptables" ]]; then
        config_iptables
    else
        echo -e "\033[31m[错误]\033[0m 未找到防火墙"
        exit 1
    fi
    
    echo -e "\033[32m[√]\033[0m 防火墙配置完成"
}

config_nftables(){
    echo -e "\033[32m[信息]\033[0m 配置 nftables..."
    VPN_IFACE=$(ip link show | grep -oP 'vpns[0-9]+' | head -1)
    VPN_IFACE=${VPN_IFACE:-vpns0}
    echo -e "\033[32m[信息]\033[0m VPN接口: $VPN_IFACE"
    
    nft add table ip nat 2>/dev/null
    nft add chain ip nat postrouting '{ type nat hook postrouting priority srcnat; }' 2>/dev/null
    nft add rule ip nat postrouting ip saddr 172.16.0.0/22 masquerade 2>/dev/null
    nft add table ip filter 2>/dev/null
    nft add chain ip filter forward '{ type filter hook forward priority filter; }' 2>/dev/null
    nft add rule ip filter forward iifname $VPN_IFACE accept 2>/dev/null
    nft add rule ip filter forward oifname $VPN_IFACE accept 2>/dev/null
    nft add rule ip filter input tcp dport 443 accept 2>/dev/null
    nft add rule ip filter input udp dport 443 accept 2>/dev/null
    nft list ruleset > /etc/nftables.conf 2>/dev/null
    echo -e "\033[32m[√]\033[0m nftables 规则已配置"
}

config_firewalld(){
    echo -e "\033[32m[信息]\033[0m 配置 firewalld..."
    firewall-cmd --permanent --add-port=443/tcp 2>/dev/null
    firewall-cmd --permanent --add-port=443/udp 2>/dev/null
    firewall-cmd --permanent --add-masquerade 2>/dev/null
    firewall-cmd --reload 2>/dev/null
    echo -e "\033[32m[√]\033[0m firewalld 规则已配置"
}

config_iptables(){
    echo -e "\033[32m[信息]\033[0m 配置 iptables..."
    iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
    iptables -I INPUT -p udp --dport 443 -j ACCEPT 2>/dev/null
    iptables -t nat -A POSTROUTING -s 172.16.0.0/22 -j MASQUERADE 2>/dev/null
    iptables -A FORWARD -i vpns0 -j ACCEPT 2>/dev/null
    iptables -A FORWARD -o vpns0 -j ACCEPT 2>/dev/null
    iptables -A FORWARD -s 172.16.0.0/22 -j ACCEPT 2>/dev/null
    iptables -A FORWARD -d 172.16.0.0/22 -j ACCEPT 2>/dev/null
    iptables-save > /etc/sysconfig/iptables 2>/dev/null
    echo -e "\033[32m[√]\033[0m iptables 规则已配置"
}

# 配置ocserv
config_ocserv(){
    echo "========================================"
    echo "========== 步骤3: 配置 ocserv =========="
    echo "========================================"
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
    if [[ ! -f server-cert.pem ]]; then
        RANDOM_CN=$(gen_random 8)
        RANDOM_ORG=$(gen_random 5)
        openssl req -newkey rsa:2048 -nodes -keyout server-key.pem -x509 -days 365 -out server-cert.pem -subj "/CN=${RANDOM_CN}/O=${RANDOM_ORG}" 2>/dev/null
        chmod 600 server-key.pem
        echo -e "\033[32m[√]\033[0m 证书已生成: CN=${RANDOM_CN}, O=${RANDOM_ORG}"
    fi
    echo -e "\033[32m[√]\033[0m 配置完成"
}

start_ocserv(){
    echo "========================================"
    echo "========== 启动 VPN =========="
    echo "========================================"
    
    if ! command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[31m[错误]\033[0m ocserv 未安装"
        return
    fi
    
    if [[ -f /var/run/ocserv.pid ]]; then
        echo -e "\033[33m[警告]\033[0m 已在运行"
        return
    fi
    
    ocserv -f -c ${conf} &
    sleep 2
    
    if [[ -f /var/run/ocserv.pid ]]; then
        echo -e "\033[32m[√]\033[0m 启动成功 (PID: $(cat /var/run/ocserv.pid))"
    else
        echo -e "\033[31m[错误]\033[0m 启动失败"
    fi
}

stop_ocserv(){
    [[ -f /var/run/ocserv.pid ]] && kill $(cat /var/run/ocserv.pid) 2>/dev/null
    rm -f /var/run/ocserv.pid
    echo -e "\033[32m[√]\033[0m 已停止"
}

add_user(){
    read -p "用户名: " u
    read -p "密码: " p
    echo -e "${p}\n${p}" | ocpasswd -c ${passwd_file} $u 2>/dev/null
    echo -e "\033[32m[√]\033[0m 用户添加成功"
}

view_status(){
    echo "========================================"
    echo "  VPN 状态"
    echo "========================================"
    if [[ -f /var/run/ocserv.pid ]]; then
        echo -e "\033[32m[√]\033[0m VPN: 运行中 (PID: $(cat /var/run/ocserv.pid))"
    else
        echo -e "\033[31m[×]\033[0m VPN: 未运行"
    fi
    if [[ $(cat /proc/sys/net/ipv4/ip_forward) == "1" ]]; then
        echo -e "\033[32m[√]\033[0m IP转发: 已开启"
    else
        echo -e "\033[31m[×]\033[0m IP转发: 未开启"
    fi
}

uninstall_ocserv(){
    echo "将删除: ocserv、配置、证书、日志、防火墙规则"
    read -p "确定卸载? (y/n): " c
    [[ $c != "y" ]] && return
    
    stop_ocserv
    rm -rf ${conf_file} /var/run/ocserv.socket ${log_file}
    
    if [[ "$FIREWALL" == "nft" ]]; then
        nft delete table ip nat 2>/dev/null
        nft delete table ip filter 2>/dev/null
    elif [[ "$FIREWALL" == "firewall" ]]; then
        firewall-cmd --permanent --remove-port=443/tcp 2>/dev/null
        firewall-cmd --permanent --remove-port=443/udp 2>/dev/null
        firewall-cmd --reload 2>/dev/null
    elif [[ "$FIREWALL" == "iptables" ]]; then
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
    
    echo -e "\033[32m[√]\033[0m 已卸载"
}

# 菜单
menu(){
    clear
    echo "========================================"
    echo "  ocserv VPN 管理脚本 v1.4.0"
    echo "========================================"
    echo "1. 安装 VPN"
    echo "2. 启动 VPN"
    echo "3. 停止 VPN"
    echo "4. 重启 VPN"
    echo "5. 查看状态"
    echo "6. 添加用户"
    echo "7. 删除用户"
    echo "8. 修改端口"
    echo "9. 查看在线用户"
    echo "10. 重新生成证书"
    echo "11. 查看日志"
    echo "12. 修复网络"
    echo "13. 卸载 VPN"
    echo "0. 退出"
    read -p "请输入选项 [0-13]: " c
    
    case $c in
        1) detect_sys; install_deps; config_ocserv; config_firewall; start_ocserv ;;
        2) start_ocserv ;;
        3) stop_ocserv ;;
        4) stop_ocserv; sleep 1; start_ocserv ;;
        5) view_status ;;
        6) add_user ;;
        7) read -p "用户名: " u; ocpasswd -d $u -c ${passwd_file} 2>/dev/null; echo "已删除" ;;
        8) read -p "端口: " p; sed -i "s/tcp-port = .*/tcp-port = $p/" ${conf}; sed -i "s/udp-port = .*/udp-port = $p/" ${conf}; echo "已改" ;;
        9) ss -tn | grep ':443 ' | grep -v LISTEN | wc -l; echo "用户在线" ;;
        10) RANDOM_CN=$(gen_random 8); RANDOM_ORG=$(gen_random 5); cd ${conf_file}; rm -f server-cert.pem server-key.pem; openssl req -newkey rsa:2048 -nodes -keyout server-key.pem -x509 -days 365 -out server-cert.pem -subj "/CN=${RANDOM_CN}/O=${RANDOM_ORG}" 2>/dev/null; echo "已生成" ;;
        11) tail -20 /var/log/ocserv.log 2>/dev/null || journalctl -u ocserv --no-pager -n 20 ;;
        12) config_firewall; stop_ocserv; start_ocserv ;;
        13) uninstall_ocserv ;;
        0) exit 0 ;;
    esac
    read -p "完成"
    menu
}

detect_sys
menu
