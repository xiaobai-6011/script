#!/bin/bash
# 使用官方vault源

echo "清理旧源..."
rm -f /etc/yum.repos.d/*.repo

echo "配置官方Vault源..."
cat > /etc/yum.repos.d/centos-vault.repo << 'EOF'
[base]
name=CentOS-Stream - Base
baseurl=http://vault.centos.org/10.0/BaseOS/x86_64/os/
enabled=1
gpgcheck=0

[appstream]
name=CentOS-Stream - AppStream
baseurl=http://vault.centos.org/10.0/AppStream/x86_64/os/
enabled=1
gpgcheck=0

[extras]
name=CentOS-Stream - Extras
baseurl=http://vault.centos.org/10.0/extras/x86_64/os/
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
