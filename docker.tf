locals {
  docker_user_data = <<-EOF
#!/bin/bash
set -x
exec > /var/log/bankapp-bootstrap.log 2>&1
sudo yum update -y
sudo yum install -y yum-utils
sudo yum config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install docker-ce -y
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user
sudo mkdir -p /opt/docker
sudo chown -R ec2-user:ec2-user /opt/docker
sudo chmod 700 /opt/docker
${local.nr_install}
sudo hostnamectl set-hostname Docker
EOF
}
