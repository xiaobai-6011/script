#!/usr/bin/env bash
# ocserv VPN 管理脚本
# Version: 1.3.6

echo "Starting script..."

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

sh_ver="1.3.6"

detect_ocserv(){
	ocserv_path=""
	for path in /usr/sbin/ocserv /usr/bin/ocserv /usr/local/sbin/ocserv; do
		if [[ -f ${path} ]]; then
			ocserv_path=${path}
			break
		fi
	done
	ocserv_path=${ocserv_path:-/usr/sbin/ocserv}
}

detect_conf(){
	conf_file="/etc/ocserv"
	conf="${conf_file}/ocserv.conf"
	passwd_file="${conf_file}/ocpasswd"
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
	elif cat /etc/issue 2>/dev/null | grep -qE -i "debian"; then
		release="debian"
	elif cat /etc/issue 2>/dev/null | grep -qE -i "ubuntu"; then
		release="ubuntu"
	else
		release="centos"
	fi
}

install_dependencies(){
	echo -e "${Info} 安装依赖..."
	if [[ ${release} == "centos" ]]; then
		yum install -y ocserv 2>/dev/null || true
	else
		apt-get update && apt-get install -y ocserv 2>/dev/null || true
	fi
	detect_ocserv
}

config_ocserv(){
	detect_ocserv
	detect_conf
	mkdir -p ${conf_file}
	cat > ${conf} << 'EOFCONF'
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
	if [[ ! -s "${conf_file}/server-cert.pem" ]]; then
		cd ${conf_file}
		openssl req -newkey rsa:2048 -nodes -keyout server-key.pem -x509 -days 3650 -out server-cert.pem -subj "/CN=VPN/O=小白" 2>/dev/null || true
		chmod 600 server-key.pem 2>/dev/null || true
	fi
}

config_firewall(){
	iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
	iptables -I INPUT -p udp --dport 443 -j ACCEPT 2>/dev/null || true
	iptables -t nat -A POSTROUTING -s 172.16.0.0/22 -j MASQUERADE 2>/dev/null || true
	echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
}

start_ocserv(){
	detect_ocserv
	detect_conf
	if [[ -f $PID_FILE ]]; then
		echo -e "${Warn} ocserv 已在运行"
		return 1
	fi
	${ocserv_path} -f -c ${conf} >/dev/null 2>&1 &
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
	kill $(cat $PID_FILE) 2>/dev/null || true
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
	read -p "用户名: " u
	read -p "密码: " p
	echo -e "${p}\n${p}" | ocpasswd -c ${passwd_file} $u 2>/dev/null || echo "$p" | ocpasswd -c ${passwd_file} $u
	echo -e "${Info} 用户 $u 添加成功"
}

del_user(){
	detect_conf
	read -p "用户名: " u
	ocpasswd -c ${passwd_file} -d $u 2>/dev/null || true
	echo -e "${Info} 用户 $u 已删除"
}

menu(){
	clear
	echo "========================================"
	echo "  ocserv VPN 管理脚本"
	echo "  版本: ${sh_ver}"
	echo "========================================"
	echo "1. 安装 VPN"
	echo "2. 配置 VPN"
	echo "3. 启动 VPN"
	echo "4. 停止 VPN"
	echo "5. 重启 VPN"
	echo "6. 查看状态"
	echo "7. 添加用户"
	echo "8. 删除用户"
	echo "0. 退出"
	echo "========================================"
	read -p "请输入选项 [0-8]: " choice
	
	case $choice in
		1) check_root && check_sys && install_dependencies && config_ocserv && config_firewall ;;
		2) check_root && config_ocserv && config_firewall ;;
		3) start_ocserv ;;
		4) stop_ocserv ;;
		5) stop_ocserv; sleep 1; start_ocserv ;;
		6) status_ocserv ;;
		7) add_user ;;
		8) del_user ;;
		0) exit 0 ;;
	esac
	read -p "按回车继续..."
	menu
}

echo "Calling menu..."
menu
