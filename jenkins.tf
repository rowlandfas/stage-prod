locals {
  jenkins_user_data = <<-EOF
#!/bin/bash
sudo yum update -y
sudo yum install -y wget git

# Jenkins LTS requires Java 17+; install Java 21 and make it the system default
sudo yum install -y java-21-openjdk java-21-openjdk-devel
JAVA21_BIN=$(rpm -ql java-21-openjdk-headless | grep -m1 '/bin/java$')
JAVA21_HOME=$(dirname "$(dirname "$JAVA21_BIN")")
sudo alternatives --set java "$JAVA21_BIN" || true

# Maven installed after the JDK so it runs on Java 21 (it may still pull an older
# headless JDK as an rpm dependency, which is why we pin Jenkins to Java 21 below)
sudo yum install -y maven

sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
sudo yum upgrade -y
sudo yum install -y jenkins

sudo sed -i 's/^User=jenkins/User=root/' /usr/lib/systemd/system/jenkins.service

# Pin the Jenkins service to the Java 21 runtime regardless of the default alternative
sudo mkdir -p /etc/systemd/system/jenkins.service.d
printf '[Service]\nEnvironment="JAVA_HOME=%s"\nEnvironment="JENKINS_JAVA_CMD=%s"\n' "$JAVA21_HOME" "$JAVA21_BIN" | sudo tee /etc/systemd/system/jenkins.service.d/java.conf

# Pre-install the plugins the bankapp pipeline needs so a rebuild comes up ready.
# config-file-provider is the one that was missing (configFileProvider/configFile step);
# the rest match what the Jenkinsfile uses (Sonar, Nexus upload, OWASP, Docker, Slack, ssh-agent).
PLUGIN_MGR_VERSION=2.13.2 # bump if the download 404s
sudo curl -fsSL -o /opt/jenkins-plugin-manager.jar \
  "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/$PLUGIN_MGR_VERSION/jenkins-plugin-manager-$PLUGIN_MGR_VERSION.jar"
sudo mkdir -p /var/lib/jenkins/plugins
cat << 'EOT' | sudo tee /var/lib/jenkins/plugins.txt
config-file-provider
pipeline-utility-steps
workflow-aggregator
git
credentials-binding
ssh-agent
sonar
nexus-artifact-uploader
dependency-check-jenkins-plugin
docker-workflow
docker-commons
htmlpublisher
slack
timestamps
ws-cleanup
EOT
sudo "$JAVA21_BIN" -jar /opt/jenkins-plugin-manager.jar \
  --war /usr/share/java/jenkins.war \
  --plugin-file /var/lib/jenkins/plugins.txt \
  --plugin-download-directory /var/lib/jenkins/plugins \
  --latest true
sudo chown -R jenkins:jenkins /var/lib/jenkins/plugins

sudo systemctl daemon-reload
sudo systemctl enable --now jenkins

# Docker engine + CLI - the pipeline runs `docker build` / `docker push` on this host
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

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