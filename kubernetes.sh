#!/bin/bash

# 绿色
# printf  "\e[32m 文本\n"

# env
hostname="k8s-master01"
ip=$(ip a|grep ens33|grep inet |awk -F '[ :]' '{print $6}' |awk -F '/' '{print $1}')
echo "$ip"



printf  "\e[32m 修改主机名: %s\n" "$hostname" "\e[0m"
hostnamectl  set-hostname  $hostname

printf  "\e[32m 设置防火墙为 Iptables 并设置空规则 \n \e[0m"
systemctl stop firewalld 
systemctl disable firewalld
yum -y install iptables-services
systemctl start iptables
systemctl enable iptables
iptables -F
service iptables save

printf  "\e[32m 关闭 SELINUX \n \e[0m"
swapoff -a && sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
setenforce 0 && sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

printf  "\e[32m 调整内核参数，对于 K8S \n \e[0m"
cat > kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.tcp_tw_recycle=0
vm.swappiness=0 # 禁止使用 swap 空间，只有当系统 OOM 时才允许使用它
vm.overcommit_memory=1 # 不检查物理内存是否够用
vm.panic_on_oom=0 # 开启 OOM	
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nf_conntrack_max=2310720
EOF
cp kubernetes.conf  /etc/sysctl.d/kubernetes.conf
sysctl -p /etc/sysctl.d/kubernetes.conf


printf  "\e[32m 调整系统时区 \n \e[0m"
timedatectl set-timezone Asia/Shanghai
timedatectl set-local-rtc 0
systemctl restart rsyslog 
systemctl restart crond


printf  "\e[32m 关闭系统不需要服务 \n \e[0m"
systemctl stop postfix && systemctl disable postfix


printf  "\e[32m 设置 rsyslogd 和 systemd journald \n \e[0m"
# 持久化保存日志的目录
mkdir /var/log/journal
mkdir /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-prophet.conf <<EOF
[Journal]
# 持久化保存到磁盘
Storage=persistent
# 压缩历史日志
Compress=yes
SyncIntervalSec=5m
RateLimitInterval=30s
RateLimitBurst=1000
# 最大占用空间 10G
SystemMaxUse=10G
# 单日志文件最大 200M
SystemMaxFileSize=200M
# 日志保存时间 2 周
MaxRetentionSec=2week
# 不将日志转发到 syslog
ForwardToSyslog=no
EOF
systemctl restart systemd-journald


printf  "\e[32m kube-proxy开启ipvs的前置条件  \n \e[0m"
modprobe br_netfilter
cat > /etc/sysconfig/modules/ipvs.modules <<EOF
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack
# modprobe -- nf_conntrack_ipv4
# 高版本的centos内核nf_conntrack_ipv4被nf_conntrack替换了，所以装不了。
EOF
chmod 755 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules && lsmod | grep -e ip_vs -e nf_conntrack


printf  "\e[32m 安装docker  \n \e[0m"
yum remove -y docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-engine

sudo yum install -y yum-utils \
  device-mapper-persistent-data \
  lvm2

sudo yum-config-manager \
    --add-repo \
    http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

sudo yum -y install docker-ce docker-ce-cli containerd.io
sudo mkdir -p /etc/docker

cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "registry-mirrors": ["https://22htyyx8.mirror.aliyuncs.com"],
  "insecure-registries": ["harbor.com"]
}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker

