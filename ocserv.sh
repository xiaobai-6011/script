#!/bin/bash
# ocserv VPN 管理脚本 v1.3.6
# 支持: CentOS 7/8/10, Rocky, AlmaLinux, Debian, Ubuntu

# 检查root
if [[ $EUID -ne 0 ]]; then
   echo -e "\033[31m[错误] 请使用ROOT用户运行\033[0m"
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
        echo -e "\033[32m[信息]\033[0m 检测到: CentOS Stream"
        release="centos-stream"
    elif [[ -f /etc/redhat-release ]]; then
        echo -e "\033[32m[信息]\033[0m 检测到: CentOS/RHEL"
        release="centos"
    elif [[ -f /etc/os-release ]]; then
        grep -q "CentOS Stream" /etc/os-release && echo -e "\033[32m[信息]\033[0m 检测到: CentOS Stream" && release="centos-stream"
        grep -q "ID=\"centos\"" /etc/os-release && echo -e "\033[32m[信息]\033[0m 检测到: CentOS" && release="centos"
    fi
    echo -e "\033[32m[信息]\033[0m 系统: ${release:-unknown}"
}

# 安装依赖
install_deps(){
    echo -e "\033[32m[信息]\033[0m 开始安装依赖..."
    
    if [[ "${release}" == "centos-stream" ]]; then
        echo -e "\033[32m[信息]\033[0m 使用 Copr 源安装..."
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

# 配置
config_ocserv(){
    echo -e "\033[32m[信息]\033[0m 配置 ocserv..."
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
# 不强制所有流量走VPN，只走配置的路由
# no-split-all-dns = true
EOF
    
    # 生成证书
    echo -e "\033[32m[信息]\033[0m 检查证书..."
    
    # 检查现有证书
    if [[ -s "${conf_file}/server-cert.pem" ]]; then
        echo -e "\033[32m[信息]\033[0m 证书已存在: ${conf_file}/server-cert.pem"
        cert_info=$(openssl x509 -in ${conf_file}/server-cert.pem -noout -subject 2>/dev/null || echo "未知")
        echo -e "\033[32m[信息]\033[0m 证书信息: ${cert_info}"
        read -p "是否重新生成证书? (y/n): " regen
        [[ $regen != "y" ]] && return
    fi
    
    # 获取服务器公网IP
    echo -e "\033[32m[信息]\033[0m 获取服务器公网IP..."
    SERVER_IP=$(curl -s --max-time 5 ip.io 2>/dev/null)
    if [[ -z ${SERVER_IP} ]]; then
        SERVER_IP=$(curl -s --max-time 5 api.ip.sb 2>/dev/null)
    fi
    if [[ -z ${SERVER_IP} ]]; then
        read -p "无法自动获取，请输入服务器公网IP: " SERVER_IP
    fi
    [[ -z ${SERVER_IP} ]] && SERVER_IP="VPN"
    
    echo -e "\033[32m[信息]\033[0m 证书CN: ${SERVER_IP}"
    echo -e "\033[32m[信息]\033[0m 证书组织: 小白"
    
    cd ${conf_file}
    
    # 尝试certtool
    if command -v certtool &>/dev/null; then
        echo -e "\033[32m[信息]\033[0m 使用certtool生成证书..."
        tmpfile=$(mktemp)
        cat > ${tmpfile} << EOFTEMPLATE
cn = "${SERVER_IP}"
organization = "小白"
serial = 1
expiration_days = 3650
ca
signing_key
cert_signing_key
encryption_key
tls_www_server
EOFTEMPLATE
        certtool --generate-privkey --outfile server-key.pem 2>/dev/null
        certtool --generate-self-signed --load-privkey server-key.pem --outfile server-cert.pem --template=${tmpfile} 2>/dev/null
        rm -f ${tmpfile}
        chmod 600 server-key.pem 2>/dev/null
    fi
    
    # 如果certtool失败，用openssl
    if [[ ! -s server-cert.pem ]]; then
        echo -e "\033[32m[信息]\033[0m 使用openssl生成证书..."
        openssl req -newkey rsa:2048 -nodes -keyout server-key.pem -x509 -days 3650 -out server-cert.pem -subj "/CN=${SERVER_IP}/O=小白" 2>/dev/null
    fi
    
    # 如果都失败，使用系统证书
    if [[ ! -s server-cert.pem ]]; then
        echo -e "\033[33m[警告]\033[0m 无法生成自签名证书，尝试使用系统证书..."
    else
        echo -e "\033[32m[信息]\033[0m 证书生成完成"
    fi
    
    # 确保权限正确
    chmod 600 ${conf_file}/server-key.pem 2>/dev/null
    chmod 644 ${conf_file}/server-cert.pem 2>/dev/null
    
    echo -e "\033[32m[信息]\033[0m 配置完成"
}

# 防火墙
config_firewall(){
    echo -e "\033[32m[信息]\033[0m 配置防火墙..."
    
    # 开启IP转发
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf 2>/dev/null
    sysctl -p 2>/dev/null
    
    # 检测防火墙 - 优先firewalld，然后nftables，最后iptables
    if command -v firewall-cmd >/dev/null 2>&1; then
        echo -e "\033[32m[信息]\033[0m 配置 firewalld..."
        
        # 开放端口
        firewall-cmd --permanent --add-port=443/tcp 2>/dev/null
        firewall-cmd --permanent --add-port=443/udp 2>/dev/null
        
        # 开启masquerade (关键！)
        firewall-cmd --permanent --add-masquerade 2>/dev/null
        firewall-cmd --add-masquerade 2>/dev/null
        
        # 允许转发
        firewall-cmd --permanent --add-forward=accept 2>/dev/null
        
        # 允许VPN网段
        firewall-cmd --permanent --add-source=172.16.0.0/22 2>/dev/null
        firewall-cmd --add-source=172.16.0.0/22 2>/dev/null
        
        # 开启IP转发
        firewall-cmd --permanent --set-ip-forward=true 2>/dev/null
        
        # 重载
        firewall-cmd --reload 2>/dev/null
        
        echo -e "\033[32m[信息]\033[0m firewalld 配置完成"
        
    elif command -v nft >/dev/null 2>&1 || [[ -d /sys/kernel/net/netfilter/nft_files ]]; then
        echo -e "\033[32m[信息]\033[0m 配置 nftables (CentOS Stream 10)..."
        
        # 添加NAT table
        nft add table ip nat 2>/dev/null
        nft add chain ip nat postrouting \{type nat hook postrouting priority srcnat\} 2>/dev/null
        nft add rule ip nat postrouting ip saddr 172.16.0.0/22 counter masquerade 2>/dev/null
        
        # 添加filter table
        nft add table ip filter 2>/dev/null
        nft add chain ip filter forward \{type filter hook forward priority filter\} 2>/dev/null
        nft add rule ip filter forward iifname vpns+ accept 2>/dev/null
        nft add rule ip filter forward oifname vpns+ accept 2>/dev/null
        nft add rule ip filter forward ct state established,related accept 2>/dev/null
        
        # 允许443端口
        nft add rule ip filter input tcp dport 443 accept 2>/dev/null
        nft add rule ip filter input udp dport 443 accept 2>/dev/null
        
        # 持久化
        nft list ruleset > /etc/nftables.conf 2>/dev/null
        
        echo -e "\033[32m[信息]\033[0m nftables 配置完成"
        
    elif command -v iptables >/dev/null 2>&1; then
        echo -e "\033[32m[信息]\033[0m 配置 iptables..."
        
        # 开放端口
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT
        iptables -I INPUT -p udp --dport 443 -j ACCEPT
        
        # NAT - masquerade (关键！)
        iptables -t nat -A POSTROUTING -s 172.16.0.0/22 -j MASQUERADE
        
        # 转发
        iptables -A FORWARD -i vpns+ -j ACCEPT
        iptables -A FORWARD -o vpns+ -j ACCEPT
        iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        
        # 允许VPN网段
        iptables -A INPUT -s 172.16.0.0/22 -j ACCEPT
        
        # 持久化
        iptables-save > /etc/sysconfig/iptables 2>/dev/null
        
        echo -e "\033[32m[信息]\033[0m iptables 配置完成"
    else
        echo -e "\033[33m[警告]\033[0m 未找到防火墙工具，尝试使用nftables..."
        # 尝试直接运行nft命令
        nft -f /dev/stdin <<< "add table ip nat; add chain ip nat postrouting type nat hook postrouting priority srcnat; add rule ip nat postrouting ip saddr 172.16.0.0/22 masquerade" 2>/dev/null
        nft -f /dev/stdin <<< "add table ip filter; add chain ip filter forward type filter hook forward priority filter; add rule ip filter forward iifname vpns+ accept; add rule ip filter forward oifname vpns+ accept" 2>/dev/null
        echo -e "\033[32m[信息]\033[0m 防火墙配置完成"
    fi
    echo -e "\033[32m[信息]\033[0m 防火墙配置完成"
}

# 启动
start_ocserv(){
    if [[ -f /var/run/ocserv.pid ]]; then
        echo -e "\033[33m[警告]\033[0m ocserv 已在运行"
        return
    fi
    
    echo -e "\033[32m[信息]\033[0m 启动 ocserv..."
    ocserv -f -c ${conf} &
    sleep 2
    
    if [[ -f /var/run/ocserv.pid ]]; then
        echo -e "\033[32m[信息]\033[0m ocserv 启动成功 (PID: $(cat /var/run/ocserv.pid))"
    else
        echo -e "\033[31m[错误]\033[0m ocserv 启动失败"
    fi
}

# 停止
stop_ocserv(){
    if [[ ! -f /var/run/ocserv.pid ]]; then
        echo -e "\033[32m[信息]\033[0m ocserv 未运行"
        return
    fi
    
    kill $(cat /var/run/ocserv.pid) 2>/dev/null
    rm -f /var/run/ocserv.pid
    echo -e "\033[32m[信息]\033[0m ocserv 已停止"
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
        echo -e "\033[32m[信息]\033[0m ocserv 运行中 (PID: $(cat /var/run/ocserv.pid))"
    else
        echo -e "\033[33m[警告]\033[0m ocserv 未运行"
    fi
}

# 添加用户
add_user(){
    read -p "用户名: " u
    read -p "密码: " p
    echo -e "${p}\n${p}" | ocpasswd -c ${passwd_file} $u 2>/dev/null
    echo -e "\033[32m[信息]\033[0m 用户 $u 添加成功"
}

# 删除用户
del_user(){
    read -p "用户名: " u
    ocpasswd -c ${passwd_file} -d $u 2>/dev/null
    echo -e "\033[32m[信息]\033[0m 用户 $u 已删除"
}

# 修改端口
set_port(){
    read -p "请输入端口 (默认443): " port
    port=${port:-443}
    sed -i "s/^tcp-port = .*/tcp-port = ${port}/" ${conf}
    sed -i "s/^udp-port = .*/udp-port = ${port}/" ${conf}
    echo -e "\033[32m[信息]\033[0m 端口已修改为: ${port}"
}

# 查看在线用户
view_users(){
    echo "========================================"
    echo "  在线用户"
    echo "========================================"
    
    if [[ ! -f /var/run/ocserv.pid ]]; then
        echo -e "\033[33m[警告]\033[0m ocserv 未运行"
        return
    fi
    
    # 使用ss检查连接
    connections=$(ss -tn 2>/dev/null | grep ":443 " | grep ESTABLISHED | wc -l)
    if [[ $connections -gt 0 ]]; then
        echo -e "\033[32m[信息]\033[0m 当前在线用户数: $connections"
        ss -tn 2>/dev/null | grep ":443 " | grep ESTABLISHED
    else
        echo -e "\033[33m[警告]\033[0m 当前无用户在线"
    fi
}

# 流量统计
view_traffic(){
    echo "========================================"
    echo "  流量统计"
    echo "========================================"
    
    if [[ ! -f /var/run/ocserv.pid ]]; then
        echo -e "\033[33m[警告]\033[0m ocserv 未运行"
        return
    fi
    
    # 检查NAT规则
    echo -e "\033[32m[信息]\033[0m 检查NAT转发规则..."
    if command -v iptables &>/dev/null; then
        iptables -t nat -L -n 2>/dev/null | grep -q "MASQUERADE" && echo -e "\033[32m[√]\033[0m NAT Masquerade 已配置" || echo -e "\033[31m[×]\033[0m NAT Masquerade 未配置"
    fi
    
    # 检查IP转发
    echo -e "\033[32m[信息]\033[0m 检查IP转发..."
    ip_forward=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)
    [[ "$ip_forward" == "1" ]] && echo -e "\033[32m[√]\033[0m IP转发已开启" || echo -e "\033[31m[×]\033[0m IP转发未开启"
    
    # 尝试从/proc获取流量
    if [[ -d /proc/net/nf_conntrack ]]; then
        traffic=$(cat /proc/net/nf_conntrack 2>/dev/null | grep ocserv | wc -l)
        echo -e "\033[32m[信息]\033[0m 当前连接数: $traffic"
    fi
    
    # 显示网络接口统计
    echo -e "\033[32m[信息]\033[0m 网络接口统计:"
    ip -s link show 2>/dev/null | grep -A1 "tun\|vpns" || echo "未找到VPN接口"
}

# 修复网络
fix_network(){
    echo -e "\033[32m[信息]\033[0m 修复网络..."
    
    # 开启IP转发
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sysctl -w net.ipv4.ip_forward=1 2>/dev/null
    
    if command -v firewall-cmd &>/dev/null; then
        echo -e "\033[32m[信息]\033[0m 使用 firewalld 修复..."
        
        # 开启masquerade (关键！)
        firewall-cmd --add-masquerade 2>/dev/null
        firewall-cmd --permanent --add-masquerade 2>/dev/null
        
        # 允许VPN网段
        firewall-cmd --add-source=172.16.0.0/22 2>/dev/null
        firewall-cmd --permanent --add-source=172.16.0.0/22 2>/dev/null
        
        # 允许转发
        firewall-cmd --add-forward=accept 2>/dev/null
        
        # 开启IP转发
        firewall-cmd --set-ip-forward=true 2>/dev/null
        
        # 重载
        firewall-cmd --reload 2>/dev/null
        
        echo -e "\033[32m[信息]\033[0m firewalld 修复完成"
        
    elif command -v nft &>/dev/null; then
        echo -e "\033[32m[信息]\033[0m 使用 nftables 修复..."
        
        # 添加NAT规则 (关键！)
        nft add table ip nat 2>/dev/null
        nft add chain ip nat postrouting \{type nat hook postrouting priority srcnat\} 2>/dev/null
        nft add rule ip nat postrouting ip saddr 172.16.0.0/22 counter masquerade 2>/dev/null
        
        # 添加转发规则
        nft add table ip filter 2>/dev/null
        nft add chain ip filter forward \{type filter hook forward priority filter\} 2>/dev/null
        nft add rule ip filter forward iifname vpns+ accept 2>/dev/null
        nft add rule ip filter forward oifname vpns+ accept 2>/dev/null
        nft add rule ip filter forward ct state established,related accept 2>/dev/null
        
        # 允许443端口
        nft add rule ip filter input tcp dport 443 accept 2>/dev/null
        nft add rule ip filter input udp dport 443 accept 2>/dev/null
        
        # 持久化
        nft list ruleset > /etc/nftables.conf 2>/dev/null
        
        echo -e "\033[32m[信息]\033[0m nftables 修复完成"
        
    elif command -v iptables &>/dev/null; then
        echo -e "\033[32m[信息]\033[0m 使用 iptables 修复..."
        
        # 清理旧规则
        iptables -t nat -F POSTROUTING 2>/dev/null
        iptables -F FORWARD 2>/dev/null
        
        # 添加新规则 (关键！)
        iptables -t nat -A POSTROUTING -s 172.16.0.0/22 -j MASQUERADE
        iptables -A FORWARD -i vpns+ -j ACCEPT
        iptables -A FORWARD -o vpns+ -j ACCEPT
        iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        
        # 持久化
        iptables-save > /etc/sysconfig/iptables 2>/dev/null
        
        echo -e "\033[32m[信息]\033[0m iptables 修复完成"
    else
        echo -e "\033[31m[错误]\033[0m 未找到防火墙工具！"
        echo -e "\033[33m[警告]\033[0m 请手动运行: nft -f - <<< 'add table ip nat; add chain ip nat postrouting { type nat hook postrouting priority srcnat; }; add rule ip nat postrouting ip saddr 172.16.0.0/22 masquerade'"
    fi
    
    echo -e "\033[32m[信息]\033[0m 网络修复完成，请重新连接VPN"
}

# SSH bypass - 允许VPN用户访问SSH
ssh_bypass(){
    echo "========================================"
    echo "  SSH bypass 设置"
    echo "========================================"
    echo "1. 开启 SSH bypass (允许VPN用户访问22端口)"
    echo "2. 关闭 SSH bypass"
    echo "0. 返回"
    read -p "请选择: " choice
    
    case $choice in
        1)
            if command -v firewall-cmd &>/dev/null; then
                # firewalld rich rule
                firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="172.16.0.0/22" port port="22" protocol="tcp" accept' 2>/dev/null
                firewall-cmd --reload 2>/dev/null
            elif command -v nft &>/dev/null; then
                # nftables
                nft add rule ip filter INPUT tcp dport 22 ip saddr 172.16.0.0/22 accept 2>/dev/null
            elif command -v iptables &>/dev/null; then
                iptables -I INPUT -p tcp --dport 22 -s 172.16.0.0/22 -j ACCEPT 2>/dev/null
            fi
            echo -e "\033[32m[信息]\033[0m SSH bypass 已开启"
            ;;
        2)
            if command -v firewall-cmd &>/dev/null; then
                firewall-cmd --permanent --remove-rich-rule='rule family="ipv4" source address="172.16.0.0/22" port port="22" protocol="tcp" accept' 2>/dev/null
                firewall-cmd --reload 2>/dev/null
            elif command -v nft &>/dev/null; then
                nft delete rule ip filter INPUT tcp dport 22 ip saddr 172.16.0.0/22 accept 2>/dev/null
            elif command -v iptables &>/dev/null; then
                iptables -D INPUT -p tcp --dport 22 -s 172.16.0.0/22 -j ACCEPT 2>/dev/null
            fi
            echo -e "\033[32m[信息]\033[0m SSH bypass 已关闭"
            ;;
    esac
}

# 重新生成证书
regen_cert(){
    echo -e "\033[32m[信息]\033[0m 重新生成证书..."
    cd ${conf_file}
    rm -f server-cert.pem server-key.pem
    
    # 获取IP
    SERVER_IP=$(curl -s --max-time 5 ip.io 2>/dev/null)
    [[ -z ${SERVER_IP} ]] && SERVER_IP=$(curl -s --max-time 5 api.ip.sb 2>/dev/null)
    [[ -z ${SERVER_IP} ]] && read -p "请输入IP: " SERVER_IP
    [[ -z ${SERVER_IP} ]] && SERVER_IP="VPN"
    
    # 生成
    if command -v certtool &>/dev/null; then
        tmpfile=$(mktemp)
        cat > ${tmpfile} << EOFTEMPLATE
cn = "${SERVER_IP}"
organization = "小白"
serial = 1
expiration_days = 3650
ca
signing_key
cert_signing_key
encryption_key
tls_www_server
EOFTEMPLATE
        certtool --generate-privkey --outfile server-key.pem 2>/dev/null
        certtool --generate-self-signed --load-privkey server-key.pem --outfile server-cert.pem --template=${tmpfile} 2>/dev/null
        rm -f ${tmpfile}
    fi
    
    if [[ ! -s server-cert.pem ]]; then
        openssl req -newkey rsa:2048 -nodes -keyout server-key.pem -x509 -days 3650 -out server-cert.pem -subj "/CN=${SERVER_IP}/O=小白" 2>/dev/null
    fi
    
    chmod 600 server-key.pem 2>/dev/null
    echo -e "\033[32m[信息]\033[0m 证书已重新生成，请重启VPN"
}

# 查看日志
view_log(){
    echo "========================================"
    echo "  查看日志"
    echo "========================================"
    
    if [[ -f ${log_file} ]]; then
        tail -50 ${log_file}
    elif command -v journalctl &>/dev/null; then
        journalctl -u ocserv -n 50 --no-pager 2>/dev/null || echo "无法获取日志"
    else
        echo -e "\033[33m[警告]\033[0m 未找到日志文件"
    fi
}

# 卸载
uninstall_ocserv(){
    echo "========================================"
    echo "  卸载 ocserv VPN"
    echo "========================================"
    read -p "确定要完全卸载吗? (y/n): " c
    [[ $c != "y" ]] && return
    
    echo -e "\033[32m[信息]\033[0m 开始卸载..."
    
    # 停止服务
    stop_ocserv 2>/dev/null
    pkill -9 ocserv 2>/dev/null
    
    # 删除配置
    rm -rf ${conf_file}
    rm -f /var/run/ocserv.pid
    rm -f /var/run/ocserv.socket
    rm -f ${log_file}
    
    # 清理防火墙
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --remove-port=443/tcp 2>/dev/null
        firewall-cmd --permanent --remove-port=443/udp 2>/dev/null
        firewall-cmd --permanent --remove-masquerade 2>/dev/null
        firewall-cmd --permanent --remove-source=172.16.0.0/22 2>/dev/null
        firewall-cmd --reload 2>/dev/null
    fi
    
    # 清理 nftables
    if command -v nft &>/dev/null; then
        nft delete table ip nat 2>/dev/null
        nft delete table ip filter 2>/dev/null
        rm -f /etc/nftables.conf
    fi
    
    # 卸载包
    if command -v dnf &>/dev/null; then
        dnf remove -y ocserv 2>/dev/null
    elif command -v yum &>/dev/null; then
        yum remove -y ocserv 2>/dev/null
    elif command -v apt &>/dev/null; then
        apt remove -y ocserv 2>/dev/null
    fi
    
    echo -e "\033[32m[信息]\033[0m ocserv 已完全卸载"
    echo -e "\033[33m[提示]\033[0m 请手动删除此脚本: rm -f $0"
}

# 菜单
menu(){
    clear
    echo "========================================"
    echo "  ocserv VPN 管理脚本"
    echo "  版本: 1.3.6"
    echo "========================================"
    echo "1.  安装 VPN (推荐)"
    echo "2.  配置 VPN"
    echo "3.  启动 VPN"
    echo "4.  停止 VPN"
    echo "5.  重启 VPN"
    echo "6.  查看状态"
    echo "7.  添加用户"
    echo "8.  删除用户"
    echo "9.  修改端口"
    echo "10. 查看在线用户"
    echo "11. 流量统计"
    echo "12. 重新生成证书"
    echo "13. 查看日志"
    echo "14. 修复网络"
    echo "15. SSH bypass"
    echo "16. 卸载 VPN"
    echo "0.  退出"
    echo "========================================"
    read -p "请输入选项 [0-16]: " choice
    
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
        11) view_traffic ;;
        12) regen_cert ;;
        13) view_log ;;
        14) fix_network ;;
        15) ssh_bypass ;;
        16) uninstall_ocserv ;;
        0) exit 0 ;;
    esac
    
    echo ""
    read -p "按回车继续..."
    menu
}

# 主程序
detect_sys
menu
