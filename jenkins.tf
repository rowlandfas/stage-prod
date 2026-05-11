locals {
  jenkins_user_data = <<-EOF
#!/bin/bash
sudo yum update -y
sudo yum install wget -y
sudo yum install maven -y
sudo yum install git -y
sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
sudo yum upgrade -y
sudo yum install java-17-openjdk -y
sudo yum install jenkins -y
sudo sed -i 's/^User=jenkins/User=root/' /usr/lib/systemd/system/jenkins.service
sudo systemctl daemon-reload
sudo systemctl start jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins
# Install trivy for container scanning
RELEASE_VERSION=$(grep -Po '(?<=VERSION_ID=")[0-9]' /etc/os-release)
cat << EOT | sudo tee -a /etc/yum.repos.d/trivy.repo
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$RELEASE_VERSION/\$basearch/
gpgcheck=0
enabled=1
EOT
sudo yum -y update
sudo yum -y install trivy
#installing opentelementry
sudo yum update
sudo yum -y install wget systemctl
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.106.1/otelcol_0.106.1_linux_amd64.rpm
sudo rpm -ivh otelcol_0.106.1_linux_amd64.rpm
curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash && sudo NEW_RELIC_API_KEY=NRAK-EO270WP5BPKV1G0AMEZZI64U0HS NEW_RELIC_ACCOUNT_ID=5144160 NEW_RELIC_REGION=EU /usr/local/bin/newrelic install -y

# Install Checkov for security scanning
python3 -m pip install --upgrade pip
python3 -m pip install --user checkov --quiet

# Add Checkov to PATH for all users
echo 'export PATH=$PATH:$(python3 -m site --user-base)/bin' | sudo tee -a /etc/profile.d/checkov.sh

# Reload PATH
source /etc/profile.d/checkov.sh

# Verify Checkov installation
checkov --version || echo "Checkov installation failed"
EOF
}