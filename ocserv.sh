#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	Description: ocserv AnyConnect VPN
#	Version: 1.0.1
#	Author: XZ
#	URL: https://chuanghongdu.com
#	支持系统: Debian/Ubuntu/CentOS/RedHat/AlibabaCloud
#=================================================

sh_ver="1.0.1"
file="/usr/local/sbin/ocserv"
conf_file="/usr/local/etc/ocserv"
conf="${conf_file}/ocserv.conf"
passwd_file="${conf_file}/ocpasswd"
log_file="/tmp/ocserv.log"
ocserv_ver="0.11.8"
PID_FILE="/var/run/ocserv.pid"

Green='\033[32m' && Red='\033[31m' && Yellow='\033[33m' && GreenBG='\033[42;37m' && RedBG='\033[41;37m' && NC='\033[0m'
Info="${Green}[信息]${NC}"
Error="${Red}[错误]${NC}"
Warn="${Yellow}[警告]${NC}"
Tip="${Green}[注意]${NC}"

# 检查root权限
check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 请使用ROOT用户运行" && exit 1
}

# 检查系统并设置包管理器
check_sys(){
	# 检测系统类型
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
	
	# 获取系统版本号
	if [[ -f /etc/centos-release ]]; then
		centos_version=$(cat /etc/centos-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
	elif [[ -f /etc/redhat-release ]]; then
		centos_version=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
	elif [[ -f /etc/aliyun-release ]]; then
		centos_version=$(cat /etc/aliyun-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
	elif [[ -f /etc/rocky-release ]]; then
		centos_version=$(cat /etc/rocky-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
	elif [[ -f /etc/almalinux-release ]]; then
		centos_version=$(cat /etc/almalinux-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
	fi
	
	echo -e "${Info} 检测到系统: ${release} ${centos_version}"
}

# 根据系统安装依赖
install_dependencies(){
	echo -e "${Info} 开始安装依赖..."
	
	if [[ ${release} == "centos" ]] || [[ ${release} == "aliyun" ]] || [[ ${release} == "alinux" ]]; then
		# CentOS / Aliyun / Alibaba Cloud
		# 先尝试修复yum源问题
		if [[ -f /etc/centos-release ]]; then
			# 备份并修复yum源
			mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak 2>/dev/null
			# 使用阿里云源
			cat > /etc/yum.repos.d/CentOS-Base.repo << 'EOF'
[base]
name=CentOS-\$releasever - Base - mirrors.aliyun.com
failovermethod=priority
baseurl=https://mirrors.aliyun.com/centos/\$releasever/os/\$basearch/
gpgcheck=0
enabled=1
[updates]
name=CentOS-\$releasever - Updates - mirrors.aliyun.com
failovermethod=priority
baseurl=https://mirrors.aliyun.com/centos/\$releasever/updates/\$basearch/
gpgcheck=0
enabled=1
[extras]
name=CentOS-\$releasever - Extras - mirrors.aliyun.com
failovermethod=priority
baseurl=https://mirrors.aliyun.com/centos/\$releasever/extras/\$basearch/
gpgcheck=0
enabled=1
EOF
			yum clean all
		fi
		
		# 安装EPEL (忽略错误)
		yum install -y epel-release || echo -e "${Warn} EPEL安装失败，继续..."
		
		# 安装基础工具 (使用--skip-broken跳过坏包)
		yum install -y vim net-tools pkgconfig || echo -e "${Warn} 部分基础包安装失败"
		
		# 安装开发依赖
		yum install -y gnutls-devel gnutls-utils || echo -e "${Warn} gnutls安装失败"
		yum install -y libwrap-devel || true
		yum install -y lz4-devel || true
		yum install -y libseccomp-devel || true
		yum install -y readline-devel || true
		yum install -y libnl3-devel || true
		yum install -y libev-devel || true
		yum groupinstall -y "Development Tools" || true
		
	elif [[ ${release} == "debian" ]] || [[ ${release} == "ubuntu" ]]; then
		# Debian / Ubuntu
		apt-get update
		apt-get install -y vim net-tools pkg-config build-essential
		apt-get install -y libgnutls28-dev libwrap0-dev liblz4-dev
		apt-get install -y libseccomp-dev libreadline-dev libnl-nf-3-dev libev-dev gnutls-bin
	fi
	
	# 尝试安装autoconf (某些系统需要)
	if ! command -v autoconf &> /dev/null; then
		if [[ ${release} == "centos" ]] || [[ ${release} == "aliyun" ]]; then
			yum install -y autoconf || true
		else
			apt-get install -y autoconf || true
		fi
	fi
	
	echo -e "${Info} 依赖安装完成"
}

# 下载编译安装ocserv
Download_ocserv(){
	if [[ -e ${file} ]]; then
		echo -e "${Warn} ocserv 已安装"
		return 0
	fi
	
	echo -e "${Info} 开始下载 ocserv ${ocserv_ver}..."
	
	# 创建临时目录
	mkdir -p /tmp/ocserv_build && cd /tmp/ocserv_build
	
	# 尝试多个下载地址
	download_success=false
	
	# 下载源列表
	declare -a sources=(
		"https://github.com/cisco/ocserv/releases/download/v${ocserv_ver}/ocserv-${ocserv_ver}.tar.xz"
		"https://ftp.infradead.org/pub/ocserv/ocserv-${ocserv_ver}.tar.xz"
		"https://mirrors.aliyun.com/ocserv/ocserv-${ocserv_ver}.tar.xz"
		"https://mirrors.tuna.tsinghua.edu.cn/ocserv/ocserv-${ocserv_ver}.tar.xz"
	)
	
	for src in "${sources[@]}"; do
		echo -e "${Info} 尝试从 $src 下载..."
		if wget -O ocserv-${ocserv_ver}.tar.xz "$src" 2>/dev/null && [[ -s "ocserv-${ocserv_ver}.tar.xz" ]]; then
			download_success=true
			break
		fi
	done
	
	if [[ $download_success == false ]]; then
		# 尝试使用包管理器安装 (仅 Debian/Ubuntu)
		if [[ ${release} == "debian" ]] || [[ ${release} == "ubuntu" ]]; then
			echo -e "${Warn} 源码下载失败，尝试使用apt安装..."
			apt-get update
			apt-get install -y ocserv occtl
			if command -v ocserv &> /dev/null; then
				echo -e "${Info} ocserv 安装成功"
				return 0
			fi
		fi
		
		# CentOS 尝试使用epel
		if [[ ${release} == "centos" ]]; then
			echo -e "${Warn} 尝试从EPEL安装..."
			yum install -y epel-release
			yum install -y ocserv
			if command -v ocserv &> /dev/null; then
				echo -e "${Info} ocserv 安装成功"
				return 0
			fi
		fi
		
		echo -e "${Error} ocserv 安装失败"
		exit 1
	fi
	
	tar -xJf ocserv-${ocserv_ver}.tar.xz
	cd ocserv-${ocserv_ver}
	
	echo -e "${Info} 开始编译 ocserv (这可能需要几分钟)..."
	./configure --prefix=/usr/local --sysconfdir=/usr/local/etc
	
	if make -j$(nproc); then
		make install
		cd /tmp && rm -rf ocserv_build
		
		if [[ -e ${file} ]]; then
			echo -e "${Info} ocserv 编译安装成功"
		else
			echo -e "${Error} ocserv 编译安装失败"
			exit 1
		fi
	else
		echo -e "${Error} ocserv 编译失败"
		exit 1
	fi
}

# 配置ocserv
config_ocserv(){
	mkdir -p ${conf_file}
	
	# 下载默认配置
	if [[ ! -s ${conf} ]]; then
		echo -e "${Info} 创建基础配置..."
		
		# 创建基础配置 - /22网段 (1017个IP)
		cat > ${conf} << 'EOFCONF'
# 认证方式
auth = "plain[/usr/local/etc/ocserv/ocpasswd]"

# 服务端口 (AnyConnect默认443)
tcp-port = 443
udp-port = 443

# 运行用户
run-as-user = nobody
run-as-group = nogroup

# PID和Socket文件
socket-file = /var/run/ocserv.socket
pid-file = /var/run/ocserv.pid

# 证书路径
server-cert = /usr/local/etc/ocserv/server-cert.pem
server-key = /usr/local/etc/ocserv/server-key.pem

# 网络配置 - /22 网段 (1017个IP)
ipv4-network = 172.16.0.0
ipv4-netmask = 255.255.252.0

# DNS配置
dns = 8.8.8.8
dns = 114.114.114.114

# VPN路由配置 - 仅代理内网，其他直连
# 默认路由(全局代理) - 注释掉则仅代理内网
# route = 0.0.0.0/0

# 内网路由 - 走VPN
route = 10.0.0.0/8
route = 172.16.0.0/12
route = 192.168.0.0/16

# 排除本地网络 - 不走VPN
no-route = 192.168.1.0/24

# 连接超时
keepalive = 990
timeout = 660

# MTU设置
mtu = 1400
try-mtu = 1400

# 压缩
compression = true
no-compression-http-proxy = ""

welcome-message = "创泓度网络"
tunnel-all-dns = true

# 用户数量限制 (0为不限制)
max-clients = 0

# 每个用户最大设备数
max-same-nodes = 0
EOFCONF
	fi
	
	# 生成证书
	if [[ ! -s "${conf_file}/server-cert.pem" ]]; then
		echo -e "${Info} 生成自签名证书..."
		cd ${conf_file}
		
		# 检查是否有certtool
		if ! command -v certtool &> /dev/null; then
			if [[ ${release} == "centos" ]]; then
				yum install -y gnutls-utils
			else
				apt-get install -y gnutls-bin
			fi
		fi
		
		certtool --generate-privkey --outfile server-key.pem 2>/dev/null
		certtool --generate-self-signed --load-privkey server-key.pem --outfile server-cert.pem --template << 'EOFCERT' 2>/dev/null
cn = "VPN"
organization = "VPN Company"
serial = 1
activation_time = "2024-01-01 00:00:00"
expiration_time = "2027-12-31 23:59:59"
ca
signing_key
encryption_key
tls_www_server
EOFCERT
		chmod 600 server-key.pem 2>/dev/null
	fi
	
	# 创建启动脚本
	cat > /etc/init.d/ocserv << 'EOFSCRIPT'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          ocserv
# Required-Start:    $network $remote_fs $syslog
# Required-Stop:     $network $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       ocserv VPN
### END INIT INFO

PID_FILE=/var/run/ocserv.pid
CONF_FILE=/usr/local/etc/ocserv/ocserv.conf

start() {
    if [[ -f $PID_FILE ]]; then
        echo "VPN已在运行"
        return 1
    fi
    /usr/local/sbin/ocserv -f -d 1 -c $CONF_FILE &
    sleep 2
    if [[ -f $PID_FILE ]]; then
        echo "VPN启动成功"
    else
        echo "VPN启动失败"
        return 1
    fi
}

stop() {
    if [[ ! -f $PID_FILE ]]; then
        echo "VPN未在运行"
        return 1
    fi
    kill $(cat $PID_FILE)
    rm -f $PID_FILE
    echo "ocserv stopped"
}

status() {
    if [[ -f $PID_FILE ]]; then
        echo "ocserv is running (PID编号: $(cat $PID_FILE))"
    else
        echo "VPN未在运行"
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 1
        start
        ;;
    status)
        status
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
EOFSCRIPT
	chmod +x /etc/init.d/ocserv
	
	# 设置开机自启
	echo -e "${Info} 设置开机自启..."
	
	# 检测系统类型并设置开机自启
	if command -v systemctl &> /dev/null && [[ -d /etc/systemd/system ]]; then
		# systemd 系统 (CentOS 7+, Ubuntu 16.04+, Debian 8+)
		cat > /etc/systemd/system/ocserv.service << 'EOSERVICE'
[Unit]
Description=ocserv VPN
After=network.target

[Service]
Type=forking
PIDFile=/var/run/ocserv.pid
ExecStart=/usr/local/sbin/ocserv -c /usr/local/etc/ocserv/ocserv.conf -d 1
ExecStop=/bin/kill -TERM $MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOSERVICE
		
		systemctl daemon-reload
		systemctl enable ocserv
		echo -e "${Info} systemd 开机自启已设置"
		
	elif [[ -f /etc/centos-release ]] || [[ ${release} == "aliyun" ]]; then
		# CentOS 6 / 阿里云旧版
		chkconfig --add ocserv
		chkconfig ocserv on
		echo -e "${Info} chkconfig 开机自启已设置"
		
	else
		# Debian/Ubuntu
		update-rc.d ocserv defaults
		update-rc.d ocserv enable 2>/dev/null
		echo -e "${Info} update-rc.d 开机自启已设置"
	fi
	
	echo -e "${Info} ocserv 配置完成"
}

# 配置防火墙
config_firewall(){
	echo -e "${Info} 开始配置防火墙..."
	
	# 获取配置的端口
	tcp_port=$(grep "^tcp-port" ${conf} | awk '{print $3}')
	udp_port=$(grep "^udp-port" ${conf} | awk '{print $3}')
	
	if [[ -z ${tcp_port} ]]; then
		tcp_port=443
	fi
	if [[ -z ${udp_port} ]]; then
		udp_port=443
	fi
	
	# CentOS/RHEL 7+ (firewall-cmd)
	if command -v firewall-cmd &> /dev/null; then
		firewall-cmd --permanent --add-port=${tcp_port}/tcp
		firewall-cmd --permanent --add-port=${udp_port}/udp
		firewall-cmd --reload
		echo -e "${Info} firewalld 端口已开放"
	
	# CentOS 6 (iptables)
	elif [[ -f /etc/sysconfig/iptables ]]; then
		iptables -I INPUT -p tcp --dport ${tcp_port} -j ACCEPT
		iptables -I INPUT -p udp --dport ${udp_port} -j ACCEPT
		service iptables save
		echo -e "${Info} iptables 端口已开放"
	
	# Ubuntu/Debian (ufw)
	elif command -v ufw &> /dev/null; then
		ufw allow ${tcp_port}/tcp
		ufw allow ${udp_port}/udp
		echo -e "${Info} ufw 端口已开放"
	
	# 直接使用iptables (通用)
	elif command -v iptables &> /dev/null; then
		iptables -I INPUT -p tcp --dport ${tcp_port} -j ACCEPT
		iptables -I INPUT -p udp --dport ${udp_port} -j ACCEPT
		# 保存规则
		if [[ -f /etc/iptables.rules ]]; then
			iptables-save > /etc/iptables.rules
		fi
		echo -e "${Info} iptables 端口已开放"
		
	# 没有找到防火墙工具
	else
		echo -e "${Warn} 未找到防火墙配置工具，请手动开放端口 ${tcp_port}/tcp 和 ${udp_port}/udp"
	fi
	
	echo -e "${Info} 防火墙配置完成"
}

# 添加用户
add_user(){
	if [[ -z $1 ]]; then
		echo -e "${Error} 输入用户名"
		return 1
	fi
	
	username=$1
	password=${2:-password123}
	
	ocpasswd -c ${passwd_file} ${username} << EOF
${password}
${password}
EOF
	
	if [[ $? -eq 0 ]]; then
		echo -e "${Info} 用户 ${username} 添加成功"
	else
		echo -e "${Error} 用户添加失败"
	fi
}

# 删除用户
del_user(){
	if [[ -z $1 ]]; then
		echo -e "${Error} 输入用户名"
		return 1
	fi
	
	ocpasswd -c ${passwd_file} -d $1
	echo -e "${Info} 用户 $1 已删除"
}

# 启动服务
start_ocserv(){
	if [[ -f $PID_FILE ]]; then
		echo -e "${Warn} ocserv 已在运行"
		return 1
	fi
	
	/usr/local/sbin/ocserv -c ${conf} -d &
	sleep 2
	
	if [[ -f $PID_FILE ]]; then
		echo -e "${Info} ocserv 启动成功"
	else
		echo -e "${Error} ocserv 启动失败"
	fi
}

# 停止服务
stop_ocserv(){
	if [[ ! -f $PID_FILE ]]; then
		echo -e "${Warn} ocserv 未在运行"
		return 1
	fi
	
	kill $(cat $PID_FILE)
	rm -f $PID_FILE
	echo -e "${Info} VPN已停止"
}

# 查看状态
status_ocserv(){
	if [[ -f $PID_FILE ]]; then
		echo -e "${Info} VPN运行中 (PID编号: $(cat $PID_FILE))"
	else
		echo -e "${Info} VPN未运行"
	fi
}

# 修改欢迎信息
set_welcome(){
	if [[ ! -f ${conf} ]]; then
		echo -e "${Error} VPN未安装，请先安装"
		return 1
	fi
	
	echo -e "当前欢迎信息:"
	grep "welcome-message" ${conf} 2>/dev/null || echo "无"
	
	read -p "输入新的欢迎信息: " new_welcome
	
	if [[ -n ${new_welcome} ]]; then
		sed -i '/welcome-message/d' ${conf}
		echo "welcome-message = \"${new_welcome}\"" >> ${conf}
		echo -e "${Info} 欢迎信息已修改为: ${new_welcome}"
		
		read -p "是否重启ocserv使配置生效? (y/n): " restart_choice
		if [[ $restart_choice == "y" ]] || [[ $restart_choice == "Y" ]]; then
			stop_ocserv
			sleep 1
			start_ocserv
		fi
	else
		echo -e "${Error} 输入为空，保留原配置"
	fi
}

# 查看当前连接用户
view_users(){
	if [[ ! -f ${conf} ]]; then
		echo -e "${Error} VPN未安装"
		return 1
	fi
	
	if [[ ! -f $PID_FILE ]]; then
		echo -e "${Error} VPN未运行"
		return 1
	fi
	
	echo -e "========================================"
	echo -e "  当前在线"
	echo -e "========================================"
	
	# 使用occtl查看在线用户
	if command -v occtl &> /dev/null; then
		occtl show users
	else
		# 备用方法
		netstat -an | grep ":443" | grep ESTABLISHED | wc -l
		echo -e "连接数: $(netstat -an | grep ':443 ' | grep ESTABLISHED | wc -l)"
	fi
}

# 流量统计
view_traffic(){
	if [[ ! -f ${conf} ]]; then
		echo -e "${Error} VPN未安装"
		return 1
	fi
	
	echo -e "========================================"
	echo -e "  流量统计"
	echo -e "========================================"
	
	if command -v occtl &> /dev/null; then
		occtl show stats
	else
		# 显示基本流量信息
		echo "流量监控需要安装 occtl 工具"
		echo "当前连接统计:"
		netstat -an | grep ':443 ' | grep ESTABLISHED | wc -l
	fi
}

# 修改端口
set_port(){
	if [[ ! -f ${conf} ]]; then
		echo -e "${Error} VPN未安装，请先安装"
		return 1
	fi
	
	echo -e "当前端口:"
	grep "^tcp-port" ${conf}
	grep "^udp-port" ${conf}
	
	read -p "请输入新的TCP端口 (建议1000-65535): " new_tcp_port
	read -p "请输入新的UDP端口 (建议1000-65535，默认同TCP): " new_udp_port
	
	if [[ -z ${new_udp_port} ]]; then
		new_udp_port=${new_tcp_port}
	fi
	
	if [[ -n ${new_tcp_port} ]]; then
		sed -i "s/^tcp-port =.*/tcp-port = ${new_tcp_port}/" ${conf}
		sed -i "s/^udp-port =.*/udp-port = ${new_udp_port}/" ${conf}
		echo -e "${Info} 端口已修改为 TCP:${new_tcp_port} UDP:${new_udp_port}"
		
		read -p "是否重启ocserv使配置生效? (y/n): " restart_choice
		if [[ $restart_choice == "y" ]] || [[ $restart_choice == "Y" ]]; then
			stop_ocserv
			sleep 1
			start_ocserv
		fi
	fi
}

# 重新生成证书
regen_cert(){
	if [[ ! -f ${conf} ]]; then
		echo -e "${Error} VPN未安装，请先安装"
		return 1
	fi
	
	read -p "确定重新生成证书? (y/n): " confirm
	if [[ $confirm != "y" ]] && [[ $confirm != "Y" ]]; then
		return 1
	fi
	
	cd ${conf_file}
	
	# 备份旧证书
	if [[ -f server-cert.pem ]]; then
		mv server-cert.pem server-cert.pem.bak
		mv server-key.pem server-key.pem.bak
		echo -e "${Info} 已备份旧证书"
	fi
	
	# 生成新证书
	certtool --generate-privkey --outfile server-key.pem 2>/dev/null
	certtool --generate-self-signed --load-privkey server-key.pem --outfile server-cert.pem --template << 'EOFCERT' 2>/dev/null
cn = "VPN"
organization = "创泓度网络"
serial = 1
activation_time = "2024-01-01 00:00:00"
expiration_time = "2030-12-31 23:59:59"
ca
signing_key
encryption_key
tls_www_server
EOFCERT
	
	chmod 600 server-key.pem
	echo -e "${Info} 证书已重新生成"
	
	read -p "是否重启ocserv使配置生效? (y/n): " restart_choice
	if [[ $restart_choice == "y" ]] || [[ $restart_choice == "Y" ]]; then
		stop_ocserv
		sleep 1
		start_ocserv
	fi
}

# 查看日志
view_log(){
	if [[ -f ${log_file} ]]; then
		tail -n 50 ${log_file}
	else
		echo -e "${Info} 日志文件不存在，使用以下命令查看实时日志:"
		echo "journalctl -u ocserv -f"
	fi
}

# 卸载ocserv
uninstall_ocserv(){
	read -p "确定完全卸载VPN? 此操作不可恢复! (y/n): " confirm
	if [[ $confirm != "y" ]] && [[ $confirm != "Y" ]]; then
		return 1
	fi
	
	echo -e "${Warn} 开始卸载VPN ocserv..."
	
	# 停止服务
	if [[ -f $PID_FILE ]]; then
		kill $(cat $PID_FILE) 2>/dev/null
		rm -f $PID_FILE
	fi
	
	# 删除启动脚本
	rm -f /etc/init.d/ocserv
	rm -f /etc/systemd/system/ocserv.service
	systemctl daemon-reload 2>/dev/null
	
	# 删除安装文件
	rm -rf /usr/local/sbin/ocserv
	rm -rf /usr/local/etc/ocserv
	rm -f /usr/local/bin/ocpasswd
	rm -f /usr/local/bin/occtl
	
	# 删除日志
	rm -f ${log_file}
	
	# 关闭开机自启
	chkconfig --del ocserv 2>/dev/null
	update-rc.d -f ocserv remove 2>/dev/null
	
	echo -e "${Info} ocserv 已完全卸载"
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
		1)
			check_root
			check_sys
			install_dependencies
			Download_ocserv
			config_ocserv
			config_firewall
			;;
		2)
			config_ocserv
			;;
		3)
			start_ocserv
			;;
		4)
			stop_ocserv
			;;
		5)
			stop_ocserv
			sleep 1
			start_ocserv
			;;
		6)
			status_ocserv
			;;
		7)
			read -p "输入用户名: " username
			read -p "请输入用户密码: " password
			add_user "$username" "$password"
			;;
		8)
			read -p "输入要删除的用户名: " username
			del_user "$username"
			;;
		9)
			set_welcome
			;;
		10)
			view_users
			;;
		11)
			view_traffic
			;;
		12)
			set_port
			;;
		13)
			regen_cert
			;;
		14)
			view_log
			;;
		15)
			uninstall_ocserv
			;;
		0)
			exit 0
			;;
		*)
			echo -e "${Error} 无效选择"
			;;
	esac
	
	read -p "按回车键继续..."
	menu
}

# 检查是否指定参数
if [[ $# -gt 0 ]]; then
	case $1 in
		install)
			check_root
			check_sys
			install_dependencies
			Download_ocserv
			config_ocserv
			;;
		start)
			start_ocserv
			;;
		stop)
			stop_ocserv
			;;
		restart)
			stop_ocserv
			sleep 1
			start_ocserv
			;;
		status)
			status_ocserv
			;;
		add)
			add_user "$2" "$3"
			;;
		del)
			del_user "$2"
			;;
		set-welcome)
			set_welcome
			;;
		users)
			view_users
			;;
		stats)
			view_traffic
			;;
		port)
			set_port
			;;
		regen-cert)
			regen_cert
			;;
		log)
			view_log
			;;
		uninstall)
			uninstall_ocserv
			;;
		*)
			echo "用法: $0 {install|start|stop|restart|status|add|del|set-welcome|users|stats|port|regen-cert|log|uninstall}"
			;;
	esac
else
	menu
fi
