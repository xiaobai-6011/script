#!/bin/bash
# 清理并重新配置CentOS Stream 10源

echo "清理旧源..."
rm -f /etc/yum.repos.d/*.repo

echo "配置阿里云源..."
cat > /etc/yum.repos.d/centos-stream.repo << 'EOF'
[base]
name=CentOS-Stream - Base
baseurl=https://mirrors.aliyun.com/centos-stream/10/BaseOS/x86_64/os/
enabled=1
gpgcheck=0

[extras]
name=CentOS-Stream - Extras  
baseurl=https://mirrors.aliyun.com/centos-stream/10/extras/x86_64/os/
enabled=1
gpgcheck=0

[appstream]
name=CentOS-Stream - AppStream
baseurl=https://mirrors.aliyun.com/centos-stream/10/AppStream/x86_64/os/
enabled=1
gpgcheck=0

[epel]
name=Extra Packages for Enterprise Linux
baseurl=https://mirrors.aliyun.com/epel/10/Everything/x86_64
enabled=1
gpgcheck=0
EOF

echo "清理缓存..."
dnf clean all

echo "测试源..."
dnf repolist

echo ""
echo "安装ocserv..."
dnf install -y ocserv
