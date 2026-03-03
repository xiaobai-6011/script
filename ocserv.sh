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

# 检测系统
detect_sys(){
    echo "========================================"
    echo "========== 步骤1: 检测系统 =========="
    echo "========================================"
    
    if [[ -f /etc/almalinux-release ]]; then
        ver=$(cat /etc/almalinux-release | grep -oP '\d+' | head -1)
        echo -e "\033[32m[信息]\033[0m 检测到: AlmaLinux $ver"
        [[ "$ver" == "10" ]] && release="almalinux10" || release="centos"
    elif [[ -f /etc/centos-stream-release ]]; then
        echo -e "\033[32m[信息]\033[0m 检测到: CentOS Stream"
        release="centos-stream"
    elif [[ -f /etc/redhat-release ]]; then
        echo -e "\033[32m[信息]\033[0m 检测到: CentOS/RHEL"
        release="centos"
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
    echo -e "\033[32m[信息]\033[0m 开始安装依赖..."
    
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
    
    # 源1: Copr
    echo -e "\033[32m[信息]\033[0m 尝试源1: Copr..."
    dnf install -y dnf-plugins-core 2>/dev/null
    dnf copr enable -y @ocserv/ocserv 2>/dev/null
    dnf install -y ocserv 2>/dev/null
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 源1(Copr) 成功"
        return
    fi
    
    # 源2: EPEL
    echo -e "\033[33m[警告]\033[0m 源1失败，尝试源2: EPEL..."
    dnf install -y epel-release 2>/dev/null
    dnf install -y ocserv 2>/dev/null
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 源2(EPEL) 成功"
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

# YUM安装 (CentOS 7/8)
install_ocserv_yum(){
    echo -e "\033[32m[信息]\033[0m 使用 YUM 安装..."
    
    # 源1: 阿里云
    echo -e "\033[32m[信息]\033[0m 尝试源1: 阿里云..."
    cat > /etc/yum.repos.d/CentOS-Base.repo << 'EOF'
[base]
name=CentOS-$releasever - Base
baseurl=https://mirrors.aliyun.com/centos/$releasever/os/$basearch/
gpgcheck=0
[updates]
name=CentOS-$releasever - Updates
baseurl=https://mirrors.aliyun.com/centos/$releasever/updates/$basearch/
gpgcheck=0
[extras]
name=CentOS-$releasever - Extras
baseurl=https://mirrors.aliyun.com/centos/$releasever/extras/$basearch/
gpgcheck=0
EOF
    yum clean all 2>/dev/null
    yum install -y epel-release 2>/dev/null
    yum install -y ocserv 2>/dev/null
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 源1(阿里云) 成功"
        return
    fi
    
    # 源2: 清华
    echo -e "\033[33m[警告]\033[0m 源1失败，尝试源2: 清华..."
    cat > /etc/yum.repos.d/CentOS-Base.repo << 'EOF'
[base]
name=CentOS-$releasever - Base
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos/$releasever/os/$basearch/
gpgcheck=0
[updates]
name=CentOS-$releasever - Updates
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos/$releasever/updates/$basearch/
gpgcheck=0
EOF
    yum clean all 2>/dev/null
    yum install -y epel-release 2>/dev/null
    yum install -y ocserv 2>/dev/null
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 源2(清华) 成功"
        return
    fi
    
    # 源3: 网易
    echo -e "\033[33m[警告]\033[0m 源2失败，尝试源3: 网易..."
    cat > /etc/yum.repos.d/CentOS-Base.repo << 'EOF'
[base]
name=CentOS-$releasever - Base
baseurl=http://mirrors.163.com/centos/$releasever/os/$basearch/
gpgcheck=0
[updates]
name=CentOS-$releasever - Updates
baseurl=http://mirrors.163.com/centos/$releasever/updates/$basearch/
gpgcheck=0
EOF
    yum clean all 2>/dev/null
    yum install -y ocserv 2>/dev/null
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 源3(网易) 成功"
        return
    fi
    
    echo -e "\033[31m[错误]\033[0m 安装失败"
    exit 1
}

# APT安装 (Debian/Ubuntu)
install_ocserv_apt(){
    echo -e "\033[32m[信息]\033[0m 使用 APT 安装..."
    
    # 源1: 阿里云
    echo -e "\033[32m[信息]\033[0m 尝试源1: 阿里云..."
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
        echo -e "\033[32m[√]\033[0m 源1(阿里云) 成功"
        return
    fi
    
    # 源2: 清华
    echo -e "\033[33m[警告]\033[0m 源1失败，尝试源2: 清华..."
    if [[ "${release}" == "ubuntu" ]]; then
        cat > /etc/apt/sources.list << 'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
EOF
    else
        cat > /etc/apt/sources.list << 'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security/ bookworm-security main contrib non-free
EOF
    fi
    apt-get update 2>/dev/null
    apt-get install -y ocserv 2>/dev/null
    if command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 源2(清华) 成功"
        return
    fi
    
    # 源3: 官方
    echo -e "\033[33m[警告]\033[0m 源2失败，尝试源3: 官方..."
    if command -v apt >/dev/null 2>&1; then
        apt-get update 2>/dev/null
        apt-get install -y ocserv 2>/dev/null
        if command -v ocserv >/dev/null 2>&1; then
            echo -e "\033[32m[√]\033[0m 源3(官方) 成功"
            return
        fi
    fi
    
    echo -e "\033[31m[错误]\033[0m 安装失败"
    exit 1
}

# 安装防火墙
install_firewall(){
    echo -e "\033[32m[信息]\033[0m 检查防火墙..."
    
    # 检查已安装
    if command -v nft >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 已有 nftables"
        FIREWALL="nft"
        return
    elif command -v firewall-cmd >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 已有 firewalld"
        FIREWALL="firewall"
        return
    elif command -v iptables >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 已有 iptables"
        FIREWALL="iptables"
        return
    fi
    
    # 尝试安装
    echo -e "\033[33m[警告]\033[0m 无防火墙，正在安装..."
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y nftables iptables-services firewalld 2>/dev/null
    elif command -v yum >/dev/null 2>&1; then
        yum install -y iptables-services 2>/dev/null
    elif command -v apt >/dev/null 2>&1; then
        apt install -y iptables 2>/dev/null
    fi
    
    # 最终确认
    if command -v nft >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 安装 nftables 成功"
        FIREWALL="nft"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 安装 firewalld 成功"
        FIREWALL="firewall"
    elif command -v iptables >/dev/null 2>&1; then
        echo -e "\033[32m[√]\033[0m 安装 iptables 成功"
        FIREWALL="iptables"
    else
        echo -e "\033[31m[错误]\033[0m 无法安装防火墙"
        exit 1
    fi
}

# 配置防火墙
config_firewall(){
    echo "========================================"
    echo "========== 步骤4: 配置防火墙 =========="
    echo "========================================"
    echo -e "\033[32m[信息]\033[0m 配置防火墙..."
    
    # 开启IP转发
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf 2>/dev/null
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf 2>/dev/null
    
    # 根据安装的防火墙类型配置
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

# 配置nftables
config_nftables(){
    echo -e "\033[32m[信息]\033[0m 配置 nftables..."
    nft add table ip nat 2>/dev/null
    nft add chain ip nat postrouting '{ type nat hook postrouting priority srcnat; }' 2>/dev/null
    nft add rule ip nat postrouting ip saddr 172.16.0.0/22 masquerade 2>/dev/null
    nft add table ip filter 2>/dev/null
    nft add chain ip filter forward '{ type filter hook forward priority filter; }' 2>/dev/null
    nft add rule ip filter forward iifname vpns0 accept 2>/dev/null
    nft add rule ip filter forward oifname vpns0 accept 2>/dev/null
    nft add rule ip filter input tcp dport 443 accept 2>/dev/null
    nft add rule ip filter input udp dport 443 accept 2>/dev/null
    nft list ruleset > /etc/nftables.conf 2>/dev/null
    echo -e "\033[32m[√]\033[0m nftables 规则已配置"
}

# 配置firewalld
config_firewalld(){
    echo -e "\033[32m[信息]\033[0m 配置 firewalld..."
    firewall-cmd --permanent --add-port=443/tcp 2>/dev/null
    firewall-cmd --permanent --add-port=443/udp 2>/dev/null
    firewall-cmd --permanent --add-masquerade 2>/dev/null
    firewall-cmd --add-masquerade 2>/dev/null
    firewall-cmd --reload 2>/dev/null
    echo -e "\033[32m[√]\033[0m firewalld 规则已配置"
}

# 配置iptables
config_iptables(){
    echo -e "\033[32m[信息]\033[0m 配置 iptables..."
    iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
    iptables -I INPUT -p udp --dport 443 -j ACCEPT 2>/dev/null
    iptables -t nat -A POSTROUTING -s 172.16.0.0/22 -j MASQUERADE 2>/dev/null
    iptables -A FORWARD -i vpns0 -j ACCEPT 2>/dev/null
    iptables -A FORWARD -o vpns0 -j ACCEPT 2>/dev/null
    iptables-save > /etc/sysconfig/iptables 2>/dev/null
    echo -e "\033[32m[√]\033[0m iptables 规则已配置"
}

# 配置ocserv
config_ocserv(){
    echo "========================================"
    echo "========== 步骤3: 配置 ocserv =========="
    echo "========================================"
    echo -e "\033[32m[信息]\033[0m 配置 ocserv..."
    mkdir -p ${conf_file}
    
    cat > ${conf} << EOF
auth = "plain[${passwd_file}]"
tcp-port = 443
udp-port = 443
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
    
    # 生成证书
    cd ${conf_file}
    if [[ ! -f server-cert.pem ]]; then
        SERVER_IP=$(curl -s https://api.ip.sb 2>/dev/null || curl -s https://ipinfo.io/ip 2>/dev/null)
        openssl req -newkey rsa:2048 -nodes -keyout server-key.pem -x509 -days 3650 -out server-cert.pem -subj "/CN=${SERVER_IP}/O=小白" 2>/dev/null
        chmod 600 server-key.pem
    fi
    
    echo -e "\033[32m[√]\033[0m 配置完成"
}

# 启动
start_ocserv(){
    echo "========================================"
    echo "========== 启动 VPN =========="
    echo "========================================"
    
    # 检查ocserv是否存在
    echo -e "\033[32m[步骤]\033[0m 检查 ocserv 命令..."
    if ! command -v ocserv >/dev/null 2>&1; then
        echo -e "\033[31m[错误]\033[0m ocserv 命令不存在!"
        echo -e "\033[33m[提示]\033[0m 请先运行: 1 (安装 VPN)"
        return
    fi
    echo -e "\033[32m[√]\033[0m ocserv 命令存在"
    
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

# 停止
stop_ocserv(){
    [[ -f /var/run/ocserv.pid ]] && kill $(cat /var/run/ocserv.pid) 2>/dev/null
    rm -f /var/run/ocserv.pid
    echo -e "\033[32m[√]\033[0m 已停止"
}

# 添加用户
add_user(){
    read -p "用户名: " u
    read -p "密码: " p
    echo -e "${p}\n${p}" | ocpasswd -c ${passwd_file} $u 2>/dev/null
    echo -e "\033[32m[√]\033[0m 用户添加成功"
}

# 卸载
uninstall_ocserv(){
    echo "将删除: ocserv、配置、证书、日志、防火墙规则"
    read -p "确定卸载? (y/n): " c
    [[ $c != "y" ]] && return
    
    stop_ocserv
    rm -rf ${conf_file} /var/run/ocserv.socket ${log_file}
    
    # 清理防火墙
    if [[ "$FIREWALL" == "nft" ]]; then
        nft delete table ip nat 2>/dev/null
        nft delete table ip filter 2>/dev/null
    elif [[ "$FIREWALL" == "firewall" ]]; then
        firewall-cmd --permanent --remove-port=443/tcp 2>/dev/null
        firewall-cmd --permanent --remove-port=443/udp 2>/dev/null
        firewall-cmd --permanent --remove-masquerade 2>/dev/null
        firewall-cmd --reload 2>/dev/null
    elif [[ "$FIREWALL" == "iptables" ]]; then
        iptables -t nat -D POSTROUTING -s 172.16.0.0/22 -j MASQUERADE 2>/dev/null
        iptables -D FORWARD -i vpns0 -j ACCEPT 2>/dev/null
    fi
    
    # 卸载包
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
    echo "10. 查看流量统计"
    echo "11. 重新生成证书"
    echo "12. 查看日志"
    echo "13. 修复网络"
    echo "14. 卸载 VPN"
    echo "0. 退出"
    read -p "请输入选项 [0-14]: " c
    
    case $c in
        1) detect_sys; install_deps; config_ocserv; config_firewall; start_ocserv ;;
        2) start_ocserv ;;
        3) stop_ocserv ;;
        4) stop_ocserv; sleep 1; start_ocserv ;;
        5) view_status ;;
        6) add_user ;;
        7) del_user ;;
        8) set_port ;;
        9) view_users ;;
        10) view_traffic ;;
        11) regen_cert ;;
        12) view_log ;;
        13) fix_network ;;
        14) uninstall_ocserv ;;
        0) exit 0 ;;
    esac
    read -p "完成"
    menu
}

# 查看状态
view_status(){
    echo "========================================"
    echo "  VPN 状态"
    echo "========================================"
    if [[ -f /var/run/ocserv.pid ]]; then
        echo -e "\033[32m[√]\033[0m VPN 服务: 运行中 (PID: $(cat /var/run/ocserv.pid))"
    else
        echo -e "\033[31m[×]\033[0m VPN 服务: 未运行"
    fi
    
    # 检查防火墙
    if command -v nft >/dev/null 2>&1; then
        if nft list table ip nat 2>/dev/null | grep -q "masquerade"; then
            echo -e "\033[32m[√]\033[0m NAT: 已配置"
        else
            echo -e "\033[31m[×]\033[0m NAT: 未配置"
        fi
    elif command -v iptables >/dev/null 2>&1; then
        if iptables -t nat -L -n 2>/dev/null | grep -q "MASQUERADE"; then
            echo -e "\033[32m[√]\033[0m NAT: 已配置"
        else
            echo -e "\033[31m[×]\033[0m NAT: 未配置"
        fi
    fi
    
    # 检查IP转发
    if [[ $(cat /proc/sys/net/ipv4/ip_forward) == "1" ]]; then
        echo -e "\033[32m[√]\033[0m IP转发: 已开启"
    else
        echo -e "\033[31m[×]\033[0m IP转发: 未开启"
    fi
}

# 删除用户
del_user(){
    echo "========================================"
    echo "  删除用户"
    echo "========================================"
    ls -la ${conf_file}/ocpasswd 2>/dev/null
    read -p "输入要删除的用户名: " u
    if [[ -f ${passwd_file} ]]; then
        ocpasswd -d $u -c ${passwd_file} 2>/dev/null
        echo -e "\033[32m[√]\033[0m 用户 $u 已删除"
    else
        echo -e "\033[31m[错误]\033[0m 用户文件不存在"
    fi
}

# 修改端口
set_port(){
    echo "========================================"
    echo "  修改端口"
    echo "========================================"
    read -p "输入新端口(默认443): " port
    port=${port:-443}
    
    sed -i "s/tcp-port = .*/tcp-port = $port/" ${conf}
    sed -i "s/udp-port = .*/udp-port = $port/" ${conf}
    
    echo -e "\033[32m[√]\033[0m 端口已改为: $port"
    echo -e "\033[33m[提示]\033[0m 请重启VPN使配置生效"
}

# 查看在线用户
view_users(){
    echo "========================================"
    echo "  在线用户"
    echo "========================================"
    if command -v ss >/dev/null 2>&1; then
        ss -tn | grep ':443 ' | grep -v LISTEN | wc -l
    else
        netstat -tn | grep ':443 ' | grep -v LISTEN | wc -l
    fi
    echo "用户在线"
}

# 查看流量统计
view_traffic(){
    echo "========================================"
    echo "  流量统计"
    echo "========================================"
    echo "注: 需要启用流量统计功能"
}

# 重新生成证书
regen_cert(){
    echo "========================================"
    echo "  重新生成证书"
    echo "========================================"
    read -p "确定重新生成证书? (y/n): " c
    [[ $c != "y" ]] && return
    
    cd ${conf_file}
    rm -f server-cert.pem server-key.pem
    
    SERVER_IP=$(curl -s https://api.ip.sb 2>/dev/null || curl -s https://ipinfo.io/ip 2>/dev/null)
    openssl req -newkey rsa:2048 -nodes -keyout server-key.pem -x509 -days 3650 -out server-cert.pem -subj "/CN=${SERVER_IP}/O=小白" 2>/dev/null
    chmod 600 server-key.pem
    
    echo -e "\033[32m[√]\033[0m 证书已重新生成"
    echo -e "\033[33m[提示]\033[0m 请重启VPN使新证书生效"
}

# 查看日志
view_log(){
    echo "========================================"
    echo "  查看日志"
    echo "========================================"
    if [[ -f ${log_file} ]]; then
        tail -50 ${log_file}
    else
        echo -e "\033[33m[警告]\033[0m 日志文件不存在"
        journalctl -u ocserv --no-pager -n 20 2>/dev/null
    fi
}

# 修复网络
fix_network(){
    echo "========================================"
    echo "  修复网络"
    echo "========================================"
    
    # 开启IP转发
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    
    # 重新配置防火墙
    config_firewall
    
    # 重启VPN
    stop_ocserv
    sleep 1
    start_ocserv
    
    echo -e "\033[32m[√]\033[0m 网络修复完成"
}

detect_sys
menu
