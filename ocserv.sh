#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	Description: ocserv AnyConnect VPN
#	Version: 1.0.3
#	Author: XZ
#	URL: https://chuanghongdu.com
#	支持系统: Debian/Ubuntu/CentOS/RedHat/AlibabaCloud/Rocky/Alma
#=================================================

sh_ver="1.0.3"

# 自动检测ocserv安装路径
detect_ocserv(){
	# 先用command -v查找
	ocserv_path=$(command -v ocserv 2>/dev/null)
	if [[ -z ${ocserv_path} ]]; then
		# 遍历常见路径
		for path in /usr/sbin/ocserv /usr/local/sbin/ocserv /usr/bin/ocserv /opt/ocserv/sbin/ocserv; do
			if [[ -x ${path} ]]; then
				ocserv_path=${path}
				break
			fi
		done
	fi
	# 如果还没找到，尝试用which
	if [[ -z ${ocserv_path} ]]; then
		ocserv_path=$(which ocserv 2>/dev/null)
	fi
	# 还是没有就用rpm查找(CentOS)
	if [[ -z ${ocserv_path} ]] && command -v rpm &>/dev/null; then
		ocserv_path=$(rpm -ql ocserv 2>/dev/null | grep -E "sbin/ocserv$" | head -1)
	fi
	ocserv_path=${ocserv_path:-/usr/sbin/ocserv}
}

# 检测配置文件路径
detect_conf(){
	# 尝试多个可能的配置目录
	for dir in /etc/ocserv /usr/local/etc/ocserv /etc; do
		if [[ -f ${dir}/ocserv.conf ]]; then
			conf_file=${dir}
			conf=${dir}/ocserv.conf
			passwd_file=${dir}/ocpasswd
			break
		fi
	done
	conf_file=${conf_file:-/etc/ocserv}
	conf=${conf_file}/ocserv.conf
	passwd_file=${conf_file}/ocpasswd
}

# 检测运行用户和组
detect_user_group(){
	# 检测组
	if getent group nogroup >/dev/null 2>&1; then
		default_group="nogroup"
	elif getent group nobody >/dev/null 2>&1; then
		default_group="nobody"
	elif getent group www-data >/dev/null 2>&1; then
		default_group="www-data"
	else
		default_group="nobody"
	fi
	
	# 检测用户
	if id nobody >/dev/null 2>&1; then
		default_user="nobody"
	elif id www-data >/dev/null 2>&1; then
		default_user="www-data"
	elif id daemon >/dev/null 2>&1; then
		default_user="daemon"
	else
		default_user="nobody"
	fi
}

detect_ocserv
detect_conf
detect_user_group

log_file="/tmp/ocserv.log"
PID_FILE="/var/run/ocserv.pid"

Green='\033[32m' && Red='\033[31m' && Yellow='\033[33m' && NC='\033[0m'
Info="${Green}[信息]${NC}"
Error="${Red}[错误]${NC}"
Warn="${Yellow}[警告]${NC}"

# 检查root
check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 请使用ROOT用户运行" && exit 1
}

# 检查系统
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
	elif [[ -f /etc/rocky-release ]]; then
		release="centos"
	elif [[ -f /etc/almalinux-release ]]; then
		release="centos"
	elif cat /proc/version 2>/dev/null | grep -qE "debian"; then
		release="debian"
	elif cat /proc/version 2>/dev/null | grep -qE "ubuntu"; then
		release="ubuntu"
	elif cat /proc/version 2>/dev/null | grep -qE "centos|redhat|rocky"; then
		release="centos"
	else
		echo -e "${Error} 不支持的Linux系统" && exit 1
	fi
	
	echo -e "${Info} 检测到系统: ${release}"
}

# 安装依赖
install_dependencies(){
	echo -e "${Info} 开始安装依赖..."
	
	if [[ ${release} == "centos" ]] || [[ ${release} == "aliyun" ]] || [[ ${release} == "alinux" ]]; then
		# CentOS/阿里云 - 修复yum源
		if [[ -f /etc/centos-release ]] && ! grep -q "mirrors.aliyun.com" /etc/yum.repos.d/CentOS-Base.repo 2>/dev/null; then
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
		
		# 安装EPEL
		yum install -y epel-release 2>/dev/null || true
		
		# 安装依赖
		yum install -y vim net-tools pkgconfig 2>/dev/null || true
		yum install -y gnutls-devel gnutls-utils 2>/dev/null || true
		yum install -y libwrap-devel 2>/dev/null || true
		yum install -y lz4-devel 2>/dev/null || true
		yum install -y libseccomp-devel 2>/dev/null || true
		yum install -y readline-devel 2>/dev/null || true
		yum install -y libnl3-devel 2>/dev/null || true
		yum install -y libev-devel 2>/dev/null || true
		yum groupinstall -y "Development Tools" 2>/dev/null || true
		
	elif [[ ${release} == "debian" ]] || [[ ${release} == "ubuntu" ]]; then
		apt-get update
		apt-get install -y vim net-tools pkg-config build-essential
		apt-get install -y libgnutls28-dev libwrap0-dev liblz4-dev
		apt-get install -y libseccomp-dev libreadline-dev libnl-nf-3-dev libev-dev gnutls-bin
	fi
	
	# 安装autoconf
	if ! command -v autoconf &> /dev/null; then
		if [[ ${release} == "centos" ]]; then
			yum install -y autoconf 2>/dev/null || true
		else
			apt-get install -y autoconf 2>/dev/null || true
		fi
	fi
	
	echo -e "${Info} 依赖安装完成"
}

# 下载编译安装ocserv
Download_ocserv(){
	detect_ocserv
	if [[ -x ${ocserv_path} ]]; then
		echo -e "${Warn} ocserv 已安装 (${ocserv_path})"
		return 0
	fi
	
	echo -e "${Info} 开始下载 ocserv..."
	mkdir -p /tmp/ocserv_build && cd /tmp/ocserv_build
	
	ocserv_ver="0.11.8"
	declare -a sources=(
		"https://github.com/cisco/ocserv/releases/download/v${ocserv_ver}/ocserv-${ocserv_ver}.tar.xz"
		"https://ftp.infradead.org/pub/ocserv/ocserv-${ocserv_ver}.tar.xz"
		"https://mirrors.aliyun.com/ocserv/ocserv-${ocserv_ver}.tar.xz"
	)
	
	download_success=false
	for src in "${sources[@]}"; do
		echo -e "${Info} 尝试: ${src}"
		if wget -O "ocserv-${ocserv_ver}.tar.xz" "$src" 2>/dev/null && [[ -s "ocserv-${ocserv_ver}.tar.xz" ]]; then
			download_success=true
			break
		fi
	done
	
	if [[ $download_success == false ]]; then
		# 尝试包管理器安装
		if [[ ${release} == "debian" ]] || [[ ${release} == "ubuntu" ]]; then
			apt-get update
			apt-get install -y ocserv occtl 2>/dev/null
			detect_ocserv
			if [[ -x ${ocserv_path} ]]; then
				echo -e "${Info} ocserv 安装成功"
				return 0
			fi
		elif [[ ${release} == "centos" ]]; then
			yum install -y epel-release 2>/dev/null || true
			yum install -y ocserv 2>/dev/null || true
			# 强制重新检测
			detect_ocserv
			# 如果还没找到，搜索所有ocserv相关文件
			if [[ ! -x ${ocserv_path} ]] && command -v rpm &>/dev/null; then
				ocserv_path=$(rpm -ql ocserv 2>/dev/null | grep -E "ocserv$" | head -1)
			fi
			if [[ -x ${ocserv_path} ]]; then
				echo -e "${Info} ocserv 安装成功 (${ocserv_path})"
				return 0
			fi
		fi
	fi
	
	tar -xJf ocserv-${ocserv_ver}.tar.xz
	cd ocserv-${ocserv_ver}
	./configure --prefix=/usr/local --sysconfdir=/etc
	make -j$(nproc) && make install
	cd /tmp && rm -rf ocserv_build
	detect_ocserv
	[[ -x ${ocserv_path} ]] && echo -e "${Info} ocserv 编译安装成功"
}

# 配置ocserv
config_ocserv(){
	detect_ocserv
	detect_conf
	detect_user_group
	
	mkdir -p ${conf_file}
	
	# 配置文件
	cat > ${conf} << EOFCONF
auth = "plain[${passwd_file}]"
tcp-port = 443
udp-port = 443
run-as-user = ${default_user}
run-as-group = ${default_group}
socket-file = /var/run/ocserv.socket
pid-file = ${PID_FILE}
server-cert = ${conf_file}/server-cert.pem
server-key = ${conf_file}/server-key.pem
ipv4-network = 172.16.0.0
ipv4-netmask = 255.255.252.0
dns = 8.8.8.8
dns = 114.114.114.114
route = 10.0.0.0/8
route = 172.16.0.0/12
route = 192.168.0.0/16
keepalive = 990
timeout = 660
mtu = 1400
try-mtu = 1400
compression = true
no-compression-http-proxy = ""
cert-user-oid = 2.5.4.41
welcome-message = "创泓度网络"
max-clients = 0
max-same-nodes = 0
tunnel-all-dns = true
EOFCONF

	# 生成证书
	if [[ ! -s "${conf_file}/server-cert.pem" ]]; then
		echo -e "${Info} 生成证书..."
		cd ${conf_file}
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
	fi
	
	# 启动脚本
	cat > /etc/init.d/ocserv << 'EOFSCRIPT'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          ocserv
# Required-Start:    $network $remote_fs
# Required-Stop:     $network $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       ocserv VPN
### END INIT INFO

PID_FILE=/var/run/ocserv.pid
CONF_FILE=/etc/ocserv/ocserv.conf

case "$1" in
start)
    if [[ -f $PID_FILE ]]; then
        echo "VPN已在运行"
        exit 1
    fi
    /usr/sbin/ocserv -f -c $CONF_FILE &
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
	if command -v systemctl &> /dev/null && [[ -d /etc/systemd/system ]]; then
		cat > /etc/systemd/system/ocserv.service << 'EOSERVICE'
[Unit]
Description=ocserv VPN
After=network.target
[Service]
Type=forking
PIDFile=/var/run/ocserv.pid
ExecStart=/usr/sbin/ocserv -f -c /etc/ocserv/ocserv.conf
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

# 防火墙配置
config_firewall(){
	detect_conf
	tcp_port=$(grep "^tcp-port" ${conf} 2>/dev/null | awk '{print $3}')
	udp_port=$(grep "^udp-port" ${conf} 2>/dev/null | awk '{print $3}')
	tcp_port=${tcp_port:-443}
	udp_port=${udp_port:-443}
	
	if command -v firewall-cmd &> /dev/null; then
		firewall-cmd --permanent --add-port=${tcp_port}/tcp 2>/dev/null || true
		firewall-cmd --permanent --add-port=${udp_port}/udp 2>/dev/null || true
		firewall-cmd --reload 2>/dev/null || true
	elif command -v ufw &> /dev/null; then
		ufw allow ${tcp_port}/tcp 2>/dev/null || true
		ufw allow ${udp_port}/udp 2>/dev/null || true
	elif command -v iptables &> /dev/null; then
		iptables -I INPUT -p tcp --dport ${tcp_port} -j ACCEPT 2>/dev/null || true
		iptables -I INPUT -p udp --dport ${udp_port} -j ACCEPT 2>/dev/null || true
	fi
	echo -e "${Info} 防火墙配置完成"
}

# 启动
start_ocserv(){
	detect_ocserv
	detect_conf
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

# 停止
stop_ocserv(){
	if [[ !_FILE ]]; then
		echo -e -f $PID "${Warn} ocserv 未在运行"
		return 1
	fi
	kill $(cat $PID_FILE)
	rm -f $PID_FILE
	echo -e "${Info} ocserv 已停止"
}

# 状态
status_ocserv(){
	if [[ -f $PID_FILE ]]; then
		echo -e "${Info} ocserv 运行中 (PID: $(cat $PID_FILE))"
	else
		echo -e "${Info} ocserv 未运行"
	fi
}

# 添加用户
add_user(){
	detect_conf
	if [[ -z $1 ]]; then
		echo -e "${Error} 请输入用户名"
		return 1
	fi
	ocpasswd -c ${passwd_file} $1 << EOF
$2
$2
EOF
	[[ $? -eq 0 ]] && echo -e "${Info} 用户 $1 添加成功"
}

# 删除用户
del_user(){
	detect_conf
	if [[ -z $1 ]]; then
		echo -e "${Error} 请输入用户名"
		return 1
	fi
	ocpasswd -c ${passwd_file} -d $1
	echo -e "${Info} 用户 $1 已删除"
}

# 修改欢迎信息
set_welcome(){
	detect_conf
	if [[ ! -f ${conf} ]]; then
		echo -e "${Error} ocserv 未安装"
		return 1
	fi
	echo -e "当前欢迎信息:"
	grep "welcome-message" ${conf} 2>/dev/null || echo "无"
	read -p "输入新欢迎信息: " new_welcome
	if [[ -n ${new_welcome} ]]; then
		sed -i "s/.*welcome-message.*/welcome-message = \"${new_welcome}\"/" ${conf}
		echo -e "${Info} 已修改为: ${new_welcome}"
		read -p "是否重启? (y/n): " r
		[[ $r == "y" ]] && { stop_ocserv; sleep 1; start_ocserv; }
	fi
}

# 查看在线用户
view_users(){
	netstat -an | grep ':443 ' | grep ESTABLISHED | wc -l
}

# 流量统计
view_traffic(){
	if command -v occtl &> /dev/null; then
		occtl show stats
	else
		echo "当前连接数: $(netstat -an | grep ':443 ' | grep ESTABLISHED | wc -l)"
	fi
}

# 修改端口
set_port(){
	detect_conf
	read -p "输入TCP端口: " new_port
	if [[ -n ${new_port} ]]; then
		sed -i "s/^tcp-port =.*/tcp-port = ${new_port}/" ${conf}
		sed -i "s/^udp-port =.*/udp-port = ${new_port}/" ${conf}
		echo -e "${Info} 端口已修改为: ${new_port}"
		read -p "是否重启? (y/n): " r
		[[ $r == "y" ]] && { stop_ocserv; sleep 1; start_ocserv; }
	fi
}

# 重新生成证书
regen_cert(){
	detect_conf
	read -p "确定重新生成证书? (y/n): " c
	[[ $c != "y" ]] && return
	cd ${conf_file}
	mv server-cert.pem server-cert.pem.bak 2>/dev/null
	mv server-key.pem server-key.pem.bak 2>/dev/null
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
	echo -e "${Info} 证书已重新生成"
	read -p "是否重启? (y/n): " r
	[[ $r == "y" ]] && { stop_ocserv; sleep 1; start_ocserv; }
}

# 查看日志
view_log(){
	[[ -f ${log_file} ]] && tail -n 50 ${log_file} || echo "日志文件不存在"
}

# 卸载
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
	rm -f /usr/local/bin/ocpasswd /usr/local/bin/occtl
	rm -f ${log_file}
	echo -e "${Info} ocserv 已卸载"
}

# 主菜单
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
		1) check_root && check_sys && install_dependencies && Download_ocserv && config_ocserv && config_firewall ;;
		2) check_root && config_ocserv && config_firewall ;;
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

# 命令行模式
if [[ $# -gt 0 ]]; then
	case $1 in
		install) check_root && check_sys && install_dependencies && Download_ocserv && config_ocserv && config_firewall ;;
		start) start_ocserv ;;
		stop) stop_ocserv ;;
		restart) stop_ocserv; sleep 1; start_ocserv ;;
		status) status_ocserv ;;
		add) add_user "$2" "$3" ;;
		del) del_user "$2" ;;
		set-welcome) set_welcome ;;
		users) view_users ;;
		stats) view_traffic ;;
		port) set_port ;;
		regen-cert) regen_cert ;;
		log) view_log ;;
		uninstall) check_root && uninstall_ocserv ;;
		*) echo "用法: $0 {install|start|stop|restart|status|add|del|set-welcome|users|stats|port|regen-cert|log|uninstall}" ;;
	esac
else
	menu
fi
