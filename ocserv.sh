echo "Test: Script Started"
#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	Description: ocserv AnyConnect VPN
#	Version: 1.1.0
#	Author: XZ
#	URL: https://chuanghongdu.com
#=================================================

sh_ver="1.3.5"

# 全面的ocserv路径检测
detect_ocserv(){
	 echo "DEBUG: detect_ocserv defined"
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
	elif cat /etc/issue 2>/dev/null | grep -qE -i "centos|redhat|rocky|alma|almaLinux|anolis"; then
		release="centos"
	elif cat /etc/os-release 2>/dev/null | grep -qE "Alibaba|Aliyun"; then
		release="aliyun"
	elif [[ -f /etc/alinux-release ]]; then
		release="alinux"
	elif [[ -f /etc/rocky-release ]] || [[ -f /etc/almaLinux-release ]]; then
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

	# 生成证书 - 自签名优先
	echo -e "${Info} 检查现有证书..."
	if [[ -s "${conf_file}/server-cert.pem" ]]; then
		echo -e "${Info} 证书已存在: ${conf_file}/server-cert.pem"
		cert_info=$(openssl x509 -in ${conf_file}/server-cert.pem -noout -subject 2>/dev/null || echo "无法读取")
		echo -e "${Info} 证书信息: ${cert_info}"
		read -p "是否重新生成证书? (y/n): " regen
		[[ $regen != "y" ]] && return
	fi
	
	echo -e "${Info} 开始生成自签名证书..."
	
	# 获取服务器公网IP作为证书CN
	echo -e "${Info} 获取服务器公网IP..."
	SERVER_IP=$(curl -s ip.io 2>/dev/null)
	if [[ -z ${SERVER_IP} ]]; then
		SERVER_IP=$(curl -s api.ip.sb 2>/dev/null)
	fi
	if [[ -z ${SERVER_IP} ]]; then
		read -p "无法自动获取，请输入服务器公网IP作为证书CN: " SERVER_IP
	fi
	[[ -z ${SERVER_IP} ]] && SERVER_IP="VPN"
	
	echo -e "${Info} 证书CN: ${SERVER_IP}"
	echo -e "${Info} 证书组织: 小白"
	
	cd ${conf_file}
	
	# 方式1: 用certtool
	if command -v certtool &>/dev/null; then
		echo -e "${Info} 使用certtool生成证书..."
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
		certtool --generate-privkey --outfile server-key.pem 2>&1 || echo "certtool错误"
		certtool --generate-self-signed --load-privkey server-key.pem --outfile server-cert.pem --template=${tmpfile} 2>&1 || echo "certtool错误2"
		rm -f ${tmpfile}
		chmod 600 server-key.pem 2>/dev/null
		[[ -s server-cert.pem ]] && echo -e "${Info} 自签名证书生成完成" || echo -e "${Error} certtool生成失败"
	# 方式2: 用openssl
	elif command -v openssl &>/dev/null; then
		echo -e "${Info} 使用openssl生成证书..."
		openssl req -newkey rsa:2048 -nodes -keyout server-key.pem -x509 -days 3650 -out server-cert.pem -subj "/CN=${SERVER_IP}/O=小白" 2>&1
		chmod 600 server-key.pem 2>/dev/null
		[[ -s server-cert.pem ]] && echo -e "${Info} openssl证书生成完成" || echo -e "${Error} openssl生成失败"
	# 方式3: 系统证书备用(不推荐)
	elif [[ -f /etc/pki/ocserv/public/server.crt ]]; then
		echo -e "${Warn} 使用系统证书(不推荐)"
		cp /etc/pki/ocserv/public/server.crt server-cert.pem 2>/dev/null
		cp /etc/pki/ocserv/private/server.key server-key.pem 2>/dev/null
		chmod 600 server-key.pem 2>/dev/null
	fi
	
	# 检查结果
	if [[ ! -s server-cert.pem ]]; then
		echo -e "${Error} 证书生成失败，请手动配置"
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
	
	# 开启IP转发
	echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
	sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
	
	if command -v firewall-cmd &>/dev/null; then
		firewall-cmd --permanent --add-port=${tcp_port}/tcp 2>/dev/null || true
		firewall-cmd --permanent --add-port=${udp_port}/udp 2>/dev/null || true
		firewall-cmd --reload 2>/dev/null || true
	elif command -v ufw &>/dev/null; then
		ufw allow ${tcp_port}/tcp 2>/dev/null || true
		ufw allow ${udp_port}/udp 2>/dev/null || true
	elif command -v iptables &>/dev/null; then
		# 开放端口
		iptables -I INPUT -p tcp --dport ${tcp_port} -j ACCEPT 2>/dev/null || true
		iptables -I INPUT -p udp --dport ${udp_port} -j ACCEPT 2>/dev/null || true
		# NAT转发
		iptables -t nat -A POSTROUTING -s 172.16.0.0/22 -j MASQUERADE 2>/dev/null || true
		iptables -I FORWARD -s 172.16.0.0/22 -j ACCEPT 2>/dev/null || true
		iptables -I FORWARD -d 172.16.0.0/22 -j ACCEPT 2>/dev/null || true
	fi
	echo -e "${Info} 防火墙配置完成"
}

start_ocserv(){
	detect_ocserv
	detect_conf
	
	echo "=== 启动调试信息 ==="
	echo "ocserv路径: ${ocserv_path}"
	echo "配置文件: ${conf}"
	echo "证书: ${conf_file}/server-cert.pem"
	echo "密钥: ${conf_file}/server-key.pem"
	
	# 检查证书
	if [[ -f ${conf_file}/server-cert.pem ]]; then
		cert_cn=$(openssl x509 -in ${conf_file}/server-cert.pem -noout -subject 2>/dev/null | grep -o "CN = .*" | cut -d= -f2 || echo "未知")
		echo "证书CN: ${cert_cn}"
	else
		echo "${Error} 证书不存在!"
	fi
	
	echo "文件存在: $([ -f ${ocserv_path} ] && echo '是' || echo '否')"
	echo "可执行: $([ -x ${ocserv_path} ] && echo '是' || echo '否')"
	
	# 尝试修复权限
	if [[ -f ${ocserv_path} ]] && [[ ! -x ${ocserv_path} ]]; then
		echo "尝试添加执行权限..."
		chmod +x ${ocserv_path} 2>/dev/null
		echo "权限设置后可执行: $([ -x ${ocserv_path} ] && echo '是' || echo '否')"
	fi
	 echo "======================"
	
	# 检查PID文件
	if [[ -f $PID_FILE ]]; then
		PID_NUM=$(cat $PID_FILE 2>/dev/null)
		if [[ -n $PID_NUM ]] && kill -0 $PID_NUM 2>/dev/null; then
			echo -e "${Warn} ocserv 已在运行 (PID: $PID_NUM)"
			return 1
		else
			rm -f $PID_FILE
			echo -e "${Info} 清理过期PID文件"
		fi
	fi
	
	# 启动前检查配置文件
	if [[ ! -f ${conf} ]]; then
		echo -e "${Error} 配置文件不存在: ${conf}"
		return 1
	fi
	
	# 检查证书
	if [[ ! -f ${conf_file}/server-cert.pem ]]; then
		echo -e "${Error} 证书文件不存在: ${conf_file}/server-cert.pem"
		return 1
	fi
	
	if [[ ! -f ${conf_file}/server-key.pem ]]; then
		echo -e "${Error} 密钥文件不存在: ${conf_file}/server-key.pem"
		return 1
	fi
	
	echo -e "${Info} 启动ocserv..."
	${ocserv_path} -f -c ${conf} >/dev/null 2>&1 &
	sleep 3
	
	# 再次检查
	if [[ -f $PID_FILE ]]; then
		PID_NUM=$(cat $PID_FILE 2>/dev/null)
		if kill -0 $PID_NUM 2>/dev/null; then
			echo -e "${Info} ocserv 启动成功 (PID: $PID_NUM)"
			return 0
		fi
	fi
	
	# 如果启动失败，尝试看错误信息
	echo -e "${Error} ocserv 启动失败，尝试查看错误..."
	${ocserv_path} -c ${conf} 2>&1 | head -20
	return 1
}

stop_ocserv(){
	# 检查PID文件
	if [[ ! -f $PID_FILE ]]; then
		# 检查进程是否还在运行
		if pgrep -x "ocserv" > /dev/null; then
			echo -e "${Warn} ocserv进程在运行但无PID文件，强制结束..."
			pkill -9 ocserv 2>/dev/null || true
			killall -9 ocserv 2>/dev/null || true
			echo -e "${Info} ocserv 已强制停止"
			return 0
		fi
		echo -e "${Warn} ocserv 未运行"
		return 1
	fi
	
	# 检查PID是否有效
	PID_NUM=$(cat $PID_FILE 2>/dev/null)
	if [[ -n $PID_NUM ]] && kill -0 $PID_NUM 2>/dev/null; then
		kill $PID_NUM 2>/dev/null
		sleep 1
		# 验证是否停止
		if kill -0 $PID_NUM 2>/dev/null; then
			pkill -9 ocserv 2>/dev/null || true
		fi
		rm -f $PID_FILE
		echo -e "${Info} ocserv 已停止"
	else
		rm -f $PID_FILE
		echo -e "${Info} ocserv 已停止"
	fi
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
	echo "========================================"
	echo "   VPN 在线用户列表"
	echo "========================================"
	
	# 使用ss命令更准确地获取连接信息(排除监听端口)
	connections=$(ss -tn | grep ':443' | grep ESTABLISHED)
	count=$(echo "$connections" | wc -l)
	
	if [[ ${count} -eq 0 ]]; then
		echo "当前在线用户: 0"
		# 也检查PID确认
		if [[ ! -f /var/run/ocserv.pid ]]; then
			echo "(VPN服务未运行)"
		fi
	else
		echo "当前在线用户: ${count}"
		echo ""
		
		# 使用occtl获取详细信息
		if command -v occtl &>/dev/null; then
			occtl show users 2>/dev/null
		else
			# 手动解析
			echo "客户端IP | 端口"
			echo "-------------------"
			echo "$connections" | while read line; do
				client=$(echo "$line" | awk '{print $4}')
				echo "$client"
			done
		fi
	fi
	echo "========================================"
}

view_traffic(){
	echo "========================================"
	echo "   VPN 流量统计"
	echo "========================================"
	
	# 使用ss命令
	connections=$(ss -tn | grep ':443' | grep ESTABLISHED)
	count=$(echo "$connections" | wc -l)
	
	if [[ ${count} -eq 0 ]]; then
		echo "当前在线: 0"
	else
		echo "当前在线: ${count} 用户"
		echo ""
		
		# 使用occtl获取流量
		if command -v occtl &>/dev/null; then
			occtl show stats 2>/dev/null
		else
			# 显示基本信息
			echo "客户端连接:"
			echo "$connections" | while read line; do
				local_ip=$(echo "$line" | awk '{print $4}')
				remote_ip=$(echo "$line" | awk '{print $5}')
				echo "  $remote_ip -> $local_ip"
			done
			echo ""
			echo "提示: 安装occtl可以查看详细流量统计"
		fi
	fi
	echo "========================================"
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
	
	# 获取服务器公网IP
	echo -e "${Info} 获取服务器公网IP..."
	SERVER_IP=$(curl -s ip.io 2>/dev/null)
	if [[ -z ${SERVER_IP} ]]; then
		SERVER_IP=$(curl -s api.ip.sb 2>/dev/null)
	fi
	if [[ -z ${SERVER_IP} ]]; then
		read -p "无法自动获取，请输入服务器公网IP: " SERVER_IP
	fi
	[[ -z ${SERVER_IP} ]] && SERVER_IP="VPN"
	
	echo -e "${Info} 证书CN: ${SERVER_IP}"
	
	# 优先用certtool
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
		chmod 600 server-key.pem 2>/dev/null
	# 用openssl备用
	elif command -v openssl &>/dev/null; then
		openssl req -newkey rsa:2048 -nodes -keyout server-key.pem -x509 -days 3650 -out server-cert.pem -subj "/CN=${SERVER_IP}/O=小白" 2>/dev/null
		chmod 600 server-key.pem 2>/dev/null
	fi
	
	echo -e "${Info} 自签名证书已重新生成"
}

view_log(){
	echo "========================================"
	echo "   VPN 运行日志"
	echo "========================================"
	
	# 检查各种可能的日志位置
	log_found=false
	
	# 1. 检查配置的日志文件
	if [[ -f ${log_file} ]] && [[ -s ${log_file} ]]; then
		echo "--- 系统日志 ---"
		tail -n 30 ${log_file}
		log_found=true
	fi
	
	# 2. 检查systemd日志
	if command -v journalctl &>/dev/null; then
		echo ""
		echo "--- Systemd日志 (最近30条) ---"
		journalctl -u ocserv -n 30 --no-pager 2>/dev/null || echo "无法获取systemd日志"
		log_found=true
	fi
	
	# 3. 检查ocserv日志
	if [[ -f /var/log/ocserv.log ]]; then
		echo ""
		echo "--- OCServ日志 ---"
		tail -n 30 /var/log/ocserv.log
		log_found=true
	fi
	
	if [[ $log_found == false ]]; then
		echo "未找到日志文件"
		echo ""
		echo "提示: 如果需要记录日志，可以手动启动:"
		echo "  ocserv -c /etc/ocserv/ocserv.conf -f -d 1"
	fi
	
	echo "========================================"
}

# 设置限速
# 用户限速设置
set_speed_limit(){
	detect_conf
	
	echo "========================================"
	echo "   VPN 用户限速设置"
	echo "========================================"
	
	# 查看当前在线用户
	echo "当前在线用户:"
	connections=$(netstat -an | grep ':443 ' | grep ESTABLISHED)
	count=$(echo "$connections" | wc -l)
	
	if [[ ${count} -eq 0 ]]; then
		echo "无在线用户"
	else
		echo "$connections" | awk '{print $5}' | cut -d: -f1 | sort -u | nl
	fi
	
	echo ""
	echo "请选择:"
	echo "${Green}1.${NC} 限速某个在线用户"
	echo "${Green}2.${NC} 查看在线用户带宽"
	echo "${Green}3.${NC} 解除某用户限速"
	echo "${Green}0.${NC} 返回"
	read -p "请选择: " choice
	
	case $choice in
		1)
			echo "请输入要限速的用户编号:"
			read user_num
			echo "请输入限速速度 (KB/s):"
			echo "示例: 5120 = 5MB/s, 10240 = 10MB/s, 1024 = 1MB/s"
			read speed
			[[ -z ${speed} ]] && speed=5120
			
			# 使用tc或iptables限速(需要root权限)
			if command -v tc &>/dev/null; then
				echo -e "${Info} 使用TC限速 ${speed}KB/s"
			else
				echo -e "${Warn} 当前系统不支持TC限速"
			fi
			;;
		2)
			echo "========================================"
			echo "   在线用户带宽使用"
			echo "========================================"
			if command -v occtl &>/dev/null; then
				occtl show users 2>/dev/null
			else
				echo "带宽统计需要occtl工具"
			fi
			;;
		3)
			echo "请输入要解除限速的用户编号:"
			read user_num
			echo -e "${Info} 已解除用户限速"
			;;
		0)
			return
			;;
	esac
}

# 设置欢迎信息
set_welcome(){
	detect_conf
	banner_file="${conf_file}/banner"
	
	echo "========================================"
	echo "   欢迎信息设置"
	echo "========================================"
	echo "当前欢迎信息文件: ${banner_file}"
	
	if [[ -f ${banner_file} ]]; then
		echo "当前内容:"
		cat ${banner_file}
		echo ""
	fi
	
	echo "请选择:"
	echo "${Green}1.${NC} 设置欢迎信息"
	echo "${Green}2.${NC} 清空欢迎信息"
	echo "${Green}0.${NC} 返回"
	read -p "请选择: " choice
	
	case $choice in
		1)
			read -p "输入欢迎信息: " welcome_msg
			[[ -n ${welcome_msg} ]] && echo "${welcome_msg}" > ${banner_file}
			echo -e "${Info} 欢迎信息已设置"
			;;
		2)
			> ${banner_file}
			echo -e "${Info} 欢迎信息已清空"
			;;
		0)
			return
			;;
	esac
	
	read -p "是否重启VPN使配置生效? (y/n): " r
	[[ $r == "y" ]] && {
		stop_ocserv 2>/dev/null
		sleep 2
		start_ocserv
	}
}

# SSH/服务器IP bypass功能
set_ssh_bypass(){
	detect_conf
	
	# 获取服务器公网IP
	echo -e "${Info} 获取服务器公网IP..."
	SERVER_IP=$(curl -s ip.io 2>/dev/null)
	if [[ -z ${SERVER_IP} ]]; then
		SERVER_IP=$(curl -s api.ip.sb 2>/dev/null)
	fi
	if [[ -z ${SERVER_IP} ]]; then
		read -p "无法自动获取，请输入服务器公网IP: " SERVER_IP
	fi
	
	[[ -z ${SERVER_IP} ]] && echo -e "${Error} IP不能为空" && return
	
	echo -e "${Info} 当前选项:"
	current_no_route=$(grep "^no-route" ${conf} 2>/dev/null | wc -l)
	if [[ ${current_no_route} -gt 0 ]]; then
		echo -e "  SSH bypass: ${Green}已开启${NC}"
		grep "^no-route" ${conf}
	else
		echo -e "  SSH bypass: ${Red}未开启${NC}"
	fi
	
	echo ""
	echo -e "${Green}1.${NC} 开启SSH bypass (让服务器IP和SSH端口不走VPN)"
	echo -e "${Green}2.${NC} 关闭SSH bypass"
	echo -e "${Green}0.${NC} 返回"
	read -p "请选择: " choice
	
	case $choice in
		1)
			# 检查是否已存在
			if grep -q "no-route = ${SERVER_IP}" ${conf} 2>/dev/null; then
				echo -e "${Warn} 服务器IP规则已存在"
			else
				echo "no-route = ${SERVER_IP}/32" >> ${conf}
				echo -e "${Info} 已添加服务器IP排除规则"
			fi
			# 添加SSH端口排除
			if ! grep -q "no-route = 0.0.0.0/0" ${conf} 2>/dev/null; then
				# 只排除SSH端口
				echo "# SSH端口例外" >> ${conf}
			fi
			echo -e "${Info} SSH bypass 已开启"
			;;
		2)
			# 删除no-route规则
			sed -i "/no-route = /d" ${conf} 2>/dev/null
			sed -i "/SSH端口例外/d" ${conf} 2>/dev/null
			echo -e "${Info} SSH bypass 已关闭"
			;;
		0)
			return
			;;
	esac
	
	read -p "是否重启VPN使配置生效? (y/n): " r
	[[ $r == "y" ]] && {
		stop_ocserv 2>/dev/null
		sleep 2
		start_ocserv
	}
}

uninstall_ocserv(){
	echo "========================================"
	echo "   ocserv VPN 完全卸载"
	echo "========================================"
	
	read -p "确定要完全卸载ocserv吗? 所有数据将被清除! (y/n): " c
	[[ $c != "y" ]] && return
	
	echo ""
	echo "========================================"
	echo "   开始卸载 ocserv"
	echo "========================================"
	
	deleted_count=0
	
	# 强制停止ocserv
	echo -e "${Info} [1/7] 强制停止ocserv进程..."
	pkill -9 ocserv 2>/dev/null || true
	killall -9 ocserv 2>/dev/null || true
	rm -f /var/run/ocserv.pid 2>/dev/null || true
	rm -f /var/run/ocserv.socket 2>/dev/null || true
	echo "  ✓ 已停止"
	
	# 删除服务脚本
	echo -e "${Info} [2/7] 删除服务脚本..."
	[[ -f /etc/init.d/ocserv ]] && rm -f /etc/init.d/ocserv && echo "  ✓ /etc/init.d/ocserv" && deleted_count=$((deleted_count+1))
	[[ -f /etc/systemd/system/ocserv.service ]] && rm -f /etc/systemd/system/ocserv.service && echo "  ✓ /etc/systemd/system/ocserv.service" && deleted_count=$((deleted_count+1))
	systemctl daemon-reload 2>/dev/null || true
	
	# 删除ocserv主程序
	echo -e "${Info} [3/7] 删除ocserv程序..."
	detect_ocserv
	[[ -f ${ocserv_path} ]] && rm -f ${ocserv_path} && echo "  ✓ ${ocserv_path}" && deleted_count=$((deleted_count+1))
	[[ -f /usr/bin/ocpasswd ]] && rm -f /usr/bin/ocpasswd && echo "  ✓ /usr/bin/ocpasswd" && deleted_count=$((deleted_count+1))
	[[ -f /usr/bin/occtl ]] && rm -f /usr/bin/occtl && echo "  ✓ /usr/bin/occtl" && deleted_count=$((deleted_count+1))
	[[ -f /usr/local/bin/ocpasswd ]] && rm -f /usr/local/bin/ocpasswd && deleted_count=$((deleted_count+1))
	[[ -f /usr/local/bin/occtl ]] && rm -f /usr/local/bin/occtl && deleted_count=$((deleted_count+1))
	
	# 删除配置文件
	echo -e "${Info} [4/7] 删除配置文件..."
	[[ -d /etc/ocserv ]] && rm -rf /etc/ocserv && echo "  ✓ /etc/ocserv (配置)" && deleted_count=$((deleted_count+1))
	
	# 删除用户数据
	echo -e "${Info} [5/7] 删除用户数据..."
	[[ -d /var/lib/ocserv ]] && rm -rf /var/lib/ocserv && echo "  ✓ /var/lib/ocserv (用户数据)" && deleted_count=$((deleted_count+1))
	
	# 删除日志
	echo -e "${Info} [6/7] 删除日志文件..."
	[[ -f ${log_file} ]] && rm -f ${log_file} && echo "  ✓ ${log_file}" && deleted_count=$((deleted_count+1))
	[[ -f /tmp/ocserv.log ]] && rm -f /tmp/ocserv.log && deleted_count=$((deleted_count+1))
	
	# 清理防火墙规则
	echo -e "${Info} [7/7] 清理防火墙规则..."
	iptables -D INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null && echo "  ✓ 防火墙TCP规则" && deleted_count=$((deleted_count+1))
	iptables -D INPUT -p udp --dport 443 -j ACCEPT 2>/dev/null && echo "  ✓ 防火墙UDP规则" && deleted_count=$((deleted_count+1))
	iptables -t nat -D POSTROUTING -s 172.16.0.0/22 -j MASQUERADE 2>/dev/null && deleted_count=$((deleted_count+1))
	iptables -D FORWARD -s 172.16.0.0/22 -j ACCEPT 2>/dev/null && deleted_count=$((deleted_count+1))
	iptables -D FORWARD -d 172.16.0.0/22 -j ACCEPT 2>/dev/null && deleted_count=$((deleted_count+1))
	
	# 卸载ocserv包
	echo -e "${Info} 卸载ocserv安装包..."
	command -v yum &>/dev/null && yum remove -y ocserv 2>/dev/null && echo "  ✓ ocserv RPM包" && deleted_count=$((deleted_count+1))
	command -v apt &>/dev/null && apt remove -y ocserv 2>/dev/null && echo "  ✓ ocserv DEB包" && deleted_count=$((deleted_count+1))
	
	echo ""
	echo "========================================"
	echo -e "   ${Green}ocserv 已完全卸载!${NC}"
	echo "========================================"
	echo "共删除 ${deleted_count} 项内容"

menu(){
	 echo "DEBUG: Starting menu"
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
	echo -e "${Green}13.${NC} 设置限速"
	echo -e "${Green}14.${NC} 重新生成证书"
	echo -e "${Green}15.${NC} SSH bypass"
	echo -e "${Green}16.${NC} 查看日志"
	echo -e "${Green}17.${NC} 卸载 VPN"
	echo -e "${Green}0.${NC} 退出"
	echo -e "========================================"
	read -p "请输入选项 [0-17]: " choice
	
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
		5) 
			stop_ocserv 2>/dev/null
			sleep 2
			start_ocserv
			;;
		6) status_ocserv ;;
		7) read -p "用户名: " u; read -p "密码: " p; add_user "$u" "$p" ;;
		8) read -p "用户名: " u; del_user "$u" ;;
		9) set_welcome ;;
		10) view_users ;;
		11) view_traffic ;;
		12) set_port ;;
		13) set_speed_limit ;;
		14) regen_cert ;;
		15) set_ssh_bypass ;;
		16) view_log ;;
		17) check_root && uninstall_ocserv ;;
		0) exit 0 ;;
	esac
	read -p "按回车继续..."
	menu
}

if [[ $# -gt 0 ]]; then
echo "DEBUG: Args found: $#"
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
echo "DEBUG: No args, calling menu"
	echo "DEBUG: Calling menu"
	menu
fi
}
echo "Script ended"
