#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	Description: ocserv AnyConnect VPN
#	Version: 1.1.0
#	Author: XZ
#	URL: https://chuanghongdu.com
#=================================================

sh_ver="1.1.0"

# 全面的ocserv路径检测
detect_ocserv(){
	ocserv_path=""
	
	# 1. 直接尝试运行ocserv，看哪个路径有效
	for path in /usr/sbin/ocserv /usr/bin/ocserv /usr/local/sbin/ocserv /usr/local/bin/ocserv /opt/ocserv/sbin/ocserv; do
		if [[ -f ${path} ]]; then
			# 检查是否可执行
			if [[ -x ${path} ]]; then
				ocserv_path=${path}
				break
			else
				# 尝试添加执行权限
				chmod +x ${path} 2>/dev/null && if [[ -x ${path} ]]; then
					ocserv_path=${path}
					break
				fi
			fi
		fi
	done
	
	# 2. 如果上面没找到，用find搜索
	if [[ -z ${ocserv_path} ]]; then
		ocserv_path=$(find /usr -name "ocserv" -type f -executable 2>/dev/null | head -1)
	fi
	
	# 3. 用rpm查找(CentOS/RedHat)
	if [[ -z ${ocserv_path} ]] && command -v rpm &>/dev/null; then
		ocserv_path=$(rpm -ql ocserv 2>/dev/null | grep -E "sbin/ocserv$" | head -1)
	fi
	
	# 4. 用dpkg查找(Debian/Ubuntu)
	if [[ -z ${ocserv_path} ]] && command -v dpkg &>/dev/null; then
		ocserv_path=$(dpkg -L ocserv 2>/dev/null | grep -E "sbin/ocserv$" | head -1)
	fi
	
	# 5. 用command -v
	if [[ -z ${ocserv_path} ]]; then
		ocserv_path=$(command -v ocserv 2>/dev/null)
	fi
	
	# 6. 最终备用
	if [[ -z ${ocserv_path} ]] || [[ ! -f ${ocserv_path} ]]; then
		ocserv_path="/usr/sbin/ocserv"
	fi
	
	echo "检测到ocserv路径: ${ocserv_path}"
}

# 检测配置文件路径
detect_conf(){
	conf_file=""
	conf=""
	passwd_file=""
	
	# 多个可能的配置目录
	for dir in /etc/ocserv /usr/local/etc/ocserv /etc; do
		if [[ -f ${dir}/ocserv.conf ]]; then
			conf_file=${dir}
			conf=${dir}/ocserv.conf
			passwd_file=${dir}/ocpasswd
			break
		fi
	done
	
	# 如果没找到，使用默认
	if [[ -z ${conf_file} ]]; then
		conf_file="/etc/ocserv"
		conf="${conf_file}/ocserv.conf"
		passwd_file="${conf_file}/ocpasswd"
	fi
	
	echo "配置文件目录: ${conf_file}"
}

log_file="/tmp/ocserv.log"
PID_FILE="/var/run/ocserv.pid"

Green='\033[32m' && Red='\033[31m' && Yellow='\033[33m' && NC='\033[0m'
Info="${Green}[信息]${NC}"
Error="${Red}[错误]${NC}"
Warn="${Yellow}[警告]${NC}"

check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 请使用ROOT用户运行" && exit 1
}

check_sys(){
	if [[ -f /etc/redhat-release ]]; then
		release="centos"
	elif [[ -f /etc/lsb-release ]]; then
		release="ubuntu"
	elif cat /etc/issue 2>/dev/null | grep -qE -i "debian"; then
		release="debian"
	elif cat /etc/issue 2>/dev/null | grep -qE -i "ubuntu"; then
		release="ubuntu"
	elif cat /etc/issue 2>/dev/null | grep -qE -i "centos|redhat|rocky|alma|anolis"; then
		release="centos"
	elif cat /etc/os-release 2>/dev/null | grep -qE "Alibaba|Aliyun"; then
		release="aliyun"
	elif [[ -f /etc/alinux-release ]]; then
		release="alinux"
	elif [[ -f /etc/rocky-release ]] || [[ -f /etc/almalinux-release ]]; then
		release="centos"
	elif cat /proc/version 2>/dev/null | grep -qE "debian|ubuntu|centos|redhat"; then
		release="debian"
	else
		echo -e "${Error} 不支持的Linux系统" && exit 1
	fi
	echo -e "${Info} 检测到系统: ${release}"
}

install_dependencies(){
	echo -e "${Info} 开始安装依赖..."
	
	if [[ ${release} == "centos" ]] || [[ ${release} == "aliyun" ]] || [[ ${release} == "alinux" ]]; then
		# CentOS/阿里云
		if [[ -f /etc/centos-release ]]; then
			if ! grep -q "mirrors.aliyun.com" /etc/yum.repos.d/CentOS-Base.repo 2>/dev/null; then
				mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak 2>/dev/null
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
			fi
		fi
		
		yum install -y epel-release 2>/dev/null || true
		yum install -y ocserv 2>/dev/null || true
		
	elif [[ ${release} == "debian" ]] || [[ ${release} == "ubuntu" ]]; then
		apt-get update
		apt-get install -y ocserv
	fi
	
	# 检测安装结果
	detect_ocserv
	if [[ -x ${ocserv_path} ]]; then
		echo -e "${Info} ocserv 安装成功"
	else
		echo -e "${Warn} ocserv 可能未正确安装，将尝试其他方式"
	fi
}

config_ocserv(){
	detect_ocserv
	detect_conf
	
	mkdir -p ${conf_file}
	
	# 兼容不同版本的配置
	cat > ${conf} << EOFCONF
auth = "plain[${passwd_file}]"
tcp-port = 443
udp-port = 443
server-cert = ${conf_file}/server-cert.pem
server-key = ${conf_file}/server-key.pem
device = vpns
ipv4-network = 172.16.0.0
ipv4-netmask = 255.255.252.0
dns = 8.8.8.8
dns = 114.114.114.114
route = 10.0.0.0/8
route = 172.16.0.0/12
route = 192.168.0.0/16
keepalive = 990
mtu = 1400
compression = true
max-clients = 0
tunnel-all-dns = true
EOFCONF

	# 生成证书
	if [[ ! -s "${conf_file}/server-cert.pem" ]] || [[ ! -s "${conf_file}/server-key.pem" ]]; then
		echo -e "${Info} 生成证书..."
		cd ${conf_file}
		if command -v certtool &>/dev/null; then
			certtool --generate-privkey --outfile server-key.pem 2>/dev/null || true
			certtool --generate-self-signed --load-privkey server-key.pem --outfile server-cert.pem --template << 'EOFCERT' 2>/dev/null || true
cn = VPN
organization = 创泓度网络
serial = 1
activation_time = 2024-01-01 00:00:00
expiration_time = 2030-12-31 23:59:59
ca
signing_key
encryption_key
tls_www_server
EOFCERT
			chmod 600 server-key.pem 2>/dev/null || true
		else
			echo -e "${Warn} certtool未安装，跳过证书生成"
		fi
	fi
	
	# 启动脚本
	cat > /etc/init.d/ocserv << 'EOFSCRIPT'
#!/bin/bash
PID_FILE=/var/run/ocserv.pid
CONF_FILE=/etc/ocserv/ocserv.conf
ocserv_path=$(command -v ocserv 2>/dev/null || echo "/usr/sbin/ocserv")

case "$1" in
start)
    if [[ -f $PID_FILE ]]; then
        echo "VPN已在运行"
        exit 1
    fi
    $ocserv_path -f -c $CONF_FILE &
    sleep 2
    if [[ -f $PID_FILE ]]; then
        echo "VPN启动成功"
    else
        echo "VPN启动失败"
        exit 1
    fi
    ;;
stop)
    if [[ ! -f $PID_FILE ]]; then
        echo "VPN未运行"
        exit 1
    fi
    kill $(cat $PID_FILE)
    rm -f $PID_FILE
    echo "VPN已停止"
    ;;
restart)
    $0 stop
    sleep 1
    $0 start
    ;;
status)
    if [[ -f $PID_FILE ]]; then
        echo "VPN运行中 (PID: $(cat $PID_FILE))"
    else
        echo "VPN未运行"
    fi
    ;;
*)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
EOFSCRIPT
	chmod +x /etc/init.d/ocserv
	
	# 开机自启
	if command -v systemctl &>/dev/null && [[ -d /etc/systemd/system ]]; then
		ocserv_path=$(command -v ocserv 2>/dev/null || echo "/usr/sbin/ocserv")
		cat > /etc/systemd/system/ocserv.service << EOSERVICE
[Unit]
Description=ocserv VPN
After=network.target
[Service]
Type=forking
PIDFile=/var/run/ocserv.pid
ExecStart=${ocserv_path} -f -c /etc/ocserv/ocserv.conf
ExecStop=/bin/kill -TERM $MAINPID
[Install]
WantedBy=multi-user.target
EOSERVICE
		systemctl daemon-reload
		systemctl enable ocserv 2>/dev/null || true
	elif [[ -f /etc/centos-release ]]; then
		chkconfig --add ocserv 2>/dev/null || true
	else
		update-rc.d ocserv defaults 2>/dev/null || true
	fi
	
	echo -e "${Info} ocserv 配置完成"
}

config_firewall(){
	detect_conf
	tcp_port=$(grep "^tcp-port" ${conf} 2>/dev/null | awk '{print $3}')
	udp_port=$(grep "^udp-port" ${conf} 2>/dev/null | awk '{print $3}')
	tcp_port=${tcp_port:-443}
	udp_port=${udp_port:-443}
	
	if command -v firewall-cmd &>/dev/null; then
		firewall-cmd --permanent --add-port=${tcp_port}/tcp 2>/dev/null || true
		firewall-cmd --permanent --add-port=${udp_port}/udp 2>/dev/null || true
		firewall-cmd --reload 2>/dev/null || true
	elif command -v ufw &>/dev/null; then
		ufw allow ${tcp_port}/tcp 2>/dev/null || true
		ufw allow ${udp_port}/udp 2>/dev/null || true
	elif command -v iptables &>/dev/null; then
		iptables -I INPUT -p tcp --dport ${tcp_port} -j ACCEPT 2>/dev/null || true
		iptables -I INPUT -p udp --dport ${udp_port} -j ACCEPT 2>/dev/null || true
	fi
	echo -e "${Info} 防火墙配置完成"
}

start_ocserv(){
	detect_ocserv
	detect_conf
	
	echo "=== 启动调试信息 ==="
	echo "ocserv路径: ${ocserv_path}"
	echo "文件存在: $([ -f ${ocserv_path} ] && echo '是' || echo '否')"
	echo "可执行: $([ -x ${ocserv_path} ] && echo '是' || echo '否')"
	
	# 尝试修复权限
	if [[ -f ${ocserv_path} ]] && [[ ! -x ${ocserv_path} ]]; then
		echo "尝试添加执行权限..."
		chmod +x ${ocserv_path} 2>/dev/null
		echo "权限设置后可执行: $([ -x ${ocserv_path} ] && echo '是' || echo '否')"
	fi
	 echo "======================"
	
	if [[ -f $PID_FILE ]]; then
		echo -e "${Warn} ocserv 已在运行"
		return 1
	fi
	
	${ocserv_path} -f -c ${conf} &
	sleep 2
	
	if [[ -f $PID_FILE ]]; then
		echo -e "${Info} ocserv 启动成功"
	else
		echo -e "${Error} ocserv 启动失败"
	fi
}

stop_ocserv(){
	if [[ ! -f $PID_FILE ]]; then
		echo -e "${Warn} ocserv 未运行"
		return 1
	fi
	kill $(cat $PID_FILE)
	rm -f $PID_FILE
	echo -e "${Info} ocserv 已停止"
}

status_ocserv(){
	if [[ -f $PID_FILE ]]; then
		echo -e "${Info} ocserv 运行中 (PID: $(cat $PID_FILE))"
	else
		echo -e "${Info} ocserv 未运行"
	fi
}

add_user(){
	detect_conf
	ocpasswd -c ${passwd_file} $1 << EOF
$2
$2
EOF
	[[ $? -eq 0 ]] && echo -e "${Info} 用户 $1 添加成功"
}

del_user(){
	detect_conf
	ocpasswd -c ${passwd_file} -d $1
	echo -e "${Info} 用户 $1 已删除"
}

set_welcome(){
	detect_conf
	banner_file="${conf_file}/banner"
	read -p "输入欢迎信息: " new_welcome
	[[ -n ${new_welcome} ]] && echo "${new_welcome}" > ${banner_file}
	echo -e "${Info} 欢迎信息已设置"
}

view_users(){
	echo "当前连接数: $(netstat -an | grep ':443 ' | grep ESTABLISHED | wc -l)"
}

view_traffic(){
	view_users
}

set_port(){
	detect_conf
	read -p "输入端口: " new_port
	[[ -n ${new_port} ]] && {
		sed -i "s/^tcp-port =.*/tcp-port = ${new_port}/" ${conf}
		sed -i "s/^udp-port =.*/udp-port = ${new_port}/" ${conf}
		echo -e "${Info} 端口已修改"
	}
}

regen_cert(){
	detect_conf
	cd ${conf_file}
	mv server-cert.pem server-cert.pem.bak 2>/dev/null
	mv server-key.pem server-key.pem.bak 2>/dev/null
	if command -v certtool &>/dev/null; then
		certtool --generate-privkey --outfile server-key.pem 2>/dev/null
		certtool --generate-self-signed --load-privkey server-key.pem --outfile server-cert.pem --template << 'EOFCERT' 2>/dev/null
cn = VPN
organization = 创泓度网络
serial = 1
activation_time = 2024-01-01 00:00:00
expiration_time = 2030-12-31 23:59:59
ca
signing_key
encryption_key
tls_www_server
EOFCERT
		chmod 600 server-key.pem 2>/dev/null
	fi
	echo -e "${Info} 证书已重新生成"
}

view_log(){
	[[ -f ${log_file} ]] && tail -n 50 ${log_file} || echo "无日志"
}

uninstall_ocserv(){
	read -p "确定卸载? (y/n): " c
	[[ $c != "y" ]] && return
	stop_ocserv 2>/dev/null
	rm -f /etc/init.d/ocserv
	rm -f /etc/systemd/system/ocserv.service
	systemctl daemon-reload 2>/dev/null
	detect_ocserv
	[[ -x ${ocserv_path} ]] && rm -f ${ocserv_path}
	rm -rf /etc/ocserv
	rm -f /usr/local/bin/ocpasswd /usr/local/bin/occtl 2>/dev/null
	rm -f ${log_file}
	echo -e "${Info} ocserv 已卸载"
}

menu(){
	clear
	echo -e "========================================"
	echo -e "  ocserv VPN 管理脚本"
	echo -e "  版本: ${sh_ver}"
	echo -e "========================================"
	echo -e "${Green}1.${NC} 安装 VPN"
	echo -e "${Green}2.${NC} 配置 VPN"
	echo -e "${Green}3.${NC} 启动 VPN"
	echo -e "${Green}4.${NC} 停止 VPN"
	echo -e "${Green}5.${NC} 重启 VPN"
	echo -e "${Green}6.${NC} 查看状态"
	echo -e "${Green}7.${NC} 添加用户"
	echo -e "${Green}8.${NC} 删除用户"
	echo -e "${Green}9.${NC} 修改欢迎信息"
	echo -e "${Green}10.${NC} 查看在线用户"
	echo -e "${Green}11.${NC} 流量统计"
	echo -e "${Green}12.${NC} 修改端口"
	echo -e "${Green}13.${NC} 重新生成证书"
	echo -e "${Green}14.${NC} 查看日志"
	echo -e "${Green}15.${NC} 卸载 VPN"
	echo -e "${Green}0.${NC} 退出"
	echo -e "========================================"
	read -p "请输入选项 [0-15]: " choice
	
	case $choice in
		1) 
			check_root
			check_sys
			install_dependencies
			config_ocserv
			config_firewall
			;;
		2) 
			check_root
			config_ocserv
			config_firewall
			;;
		3) start_ocserv ;;
		4) stop_ocserv ;;
		5) stop_ocserv; sleep 1; start_ocserv ;;
		6) status_ocserv ;;
		7) read -p "用户名: " u; read -p "密码: " p; add_user "$u" "$p" ;;
		8) read -p "用户名: " u; del_user "$u" ;;
		9) set_welcome ;;
		10) view_users ;;
		11) view_traffic ;;
		12) set_port ;;
		13) regen_cert ;;
		14) view_log ;;
		15) check_root && uninstall_ocserv ;;
		0) exit 0 ;;
	esac
	read -p "按回车继续..."
	menu
}

if [[ $# -gt 0 ]]; then
	case $1 in
		install) check_root && check_sys && install_dependencies && config_ocserv && config_firewall ;;
		start) start_ocserv ;;
		stop) stop_ocserv ;;
		restart) stop_ocserv; sleep 1; start_ocserv ;;
		status) status_ocserv ;;
		add) add_user "$2" "$3" ;;
		del) del_user "$2" ;;
		*) echo "用法: $0 {install|start|stop|restart|status|add|del}" ;;
	esac
else
	menu
fi
