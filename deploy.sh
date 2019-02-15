#!/bin/bash

if [[ -z ${SSH} ]] || [[ -z ${NAME} ]] || [[ -z ${DOMAIN} ]]; then
  echo "ERROR: SSH, NAME and DOMAIN variables must be defined"
  exit 1
fi

###########################################################
# Start
echo "Start: $(date)" > deploy

###########################################################
# Disable IPv6
sudo cat <<EOF >> /etc/sysctl.d/01-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

# Apply changes
sysctl -p /etc/sysctl.d/*

###########################################################
# Set hostname
echo "HOSTNAME=${NAME}" >> /etc/sysconfig/network
/sbin/ifconfig eth0 | awk '/inet/ { print $2,"\t__HOSTNAME__" }' >> /etc/hosts
sed "s/__HOSTNAME__/${NAME}/g" -i /etc/hosts
hostnamectl set-hostname ${NAME}.${DOMAIN}

###########################################################
# Configure ulimits
echo "*                soft    nofile          32768" >> /etc/security/limits.d/20-nofile.conf
echo "*                hard    nofile          32768" >> /etc/security/limits.d/20-nofile.conf

###########################################################
# Allows root user to to login and adds SSH Keys
if [[ -f /root/.ssh/authorized_keys ]]; then
  sed -i "/Please login as the user/d" /root/.ssh/authorized_keys
else
  mkdir /root/.ssh
fi
echo "${SSH}" >> /root/.ssh/authorized_keys

# Configure SSH service for key access only
sudo sed -e "s/^PermitRootLogin.*/PermitRootLogin without-password/g" -i /etc/ssh/sshd_config
sudo sed -e "s/^PasswordAuthentication.*/PasswordAuthentication no/g" -i /etc/ssh/sshd_config
sudo systemctl restart sshd

###########################################################
# Disable SELinux
# sudo sed "s/^SELINUX=.*$/SELINUX=disabled/g" -i /etc/selinux/config
# sudo setenforce 0

###########################################################
# Update repo
sudo apt-get update

# Install required packages
sudo apt-get install -y rsync git python python-pip

###########################################################
# Install fail2ban
sudo apt-get install -y fail2ban

# Configure fail2ban
sudo cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
banaction = iptables-multiport
[sshd]
enabled = true
EOF

# Enable fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

###########################################################
# Configure NTP
sudo apt-get install -y ntp
sudo systemctl enable ntp
sudo systemctl start ntp

# Set timezone, default: UTC
sudo timedatectl set-timezone ${TZ:-UTC}
sudo timedatectl

###########################################################
# Update system packages
sudo apt-get upgrade -y

###########################################################
# Install Docker service
sudo apt-get remove docker docker-engine docker.io containerd runc
sudo apt-get install \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg-agent \
  software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88
sudo add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) \
  stable"
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io
sudo apt-get install docker-ce=18.03.1~ce-0~ubuntu

# Configure Docker service
sudo systemctl enable docker
sudo systemctl start docker
sudo docker version

###########################################################
# Disable cloud-init
sudo touch /etc/cloud/cloud-init.disabled

###########################################################
# Finish
echo "Finish: $(date)" >> deploy
