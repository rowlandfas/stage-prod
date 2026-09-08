locals {
  jenkins_casc = templatefile("${path.module}/casc.yaml.tftpl", {
    jenkins_admin_pass    = random_password.jenkins_admin.result
    nexus_ci_user         = "ci"
    nexus_ci_pass         = random_password.nexus_ci.result
    db_user               = var.dbusername
    db_pass               = random_password.db-password.result
    ssh_private_key       = tls_private_key.key.private_key_pem
    ansible_host          = aws_instance.ansible-server.public_ip
    rds_endpoint          = aws_db_instance.bankapp-db.endpoint
    db_name               = var.dbname
    nexus_docker_registry = "${var.nexus-domain}:${var.nexusdockerport}"
    nexus_host            = var.nexus-domain
    jenkins_url           = "https://${var.jenkins-domain}/"
    sonar_url             = "https://${var.sonar-domain}"
    has_app_repo_cred     = var.app_repo_user != ""
    app_repo_user         = var.app_repo_user
    app_repo_token        = var.app_repo_token
    app_repo_url          = var.app_repo_url
    app_repo_branch       = var.app_repo_branch
  })

  jenkins_user_data = <<-EOF
#!/bin/bash
set -x
exec > /var/log/bankapp-bootstrap.log 2>&1
sudo yum update -y
sudo yum install -y wget git jq unzip python3

# Jenkins LTS requires Java 17+; install Java 21 and make it the system default
sudo yum install -y java-21-openjdk java-21-openjdk-devel
JAVA21_BIN=$(rpm -ql java-21-openjdk-headless | grep -m1 '/bin/java$')
JAVA21_HOME=$(dirname "$(dirname "$JAVA21_BIN")")
sudo alternatives --set java "$JAVA21_BIN" || true

sudo yum install -y maven

sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
sudo yum upgrade -y
sudo yum install -y jenkins

sudo sed -i 's/^User=jenkins/User=root/' /usr/lib/systemd/system/jenkins.service

# AWS CLI v2 - used to read the Sonar analysis token published to SSM
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
cd /tmp && unzip -q awscliv2.zip && sudo ./aws/install && cd /

# --- systemd drop-ins --------------------------------------------------
sudo mkdir -p /etc/systemd/system/jenkins.service.d
printf '[Service]\nEnvironment="JAVA_HOME=%s"\nEnvironment="JENKINS_JAVA_CMD=%s"\n' "$JAVA21_HOME" "$JAVA21_BIN" | sudo tee /etc/systemd/system/jenkins.service.d/java.conf
cat <<'DROPIN' | sudo tee /etc/systemd/system/jenkins.service.d/casc.conf
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"
Environment="JENKINS_JAVA_OPTIONS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc.yaml"
Environment="SECRETS=/var/lib/jenkins/secrets-casc"
DROPIN

# belt-and-suspenders wizard skip (independent of the systemd env plumbing)
JV=$(unzip -p /usr/share/java/jenkins.war META-INF/MANIFEST.MF | awk -F': ' '/Jenkins-Version/{print $2}' | tr -d '\r')
sudo mkdir -p /var/lib/jenkins
echo "$JV" | sudo tee /var/lib/jenkins/jenkins.install.InstallUtil.lastExecVersion
echo "$JV" | sudo tee /var/lib/jenkins/jenkins.install.UpgradeWizard.state

# --- plugins (pre-installed so the controller comes up ready) ----------
PLUGIN_MGR_VERSION=2.13.2
sudo curl -fsSL -o /opt/jenkins-plugin-manager.jar \
  "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/$PLUGIN_MGR_VERSION/jenkins-plugin-manager-$PLUGIN_MGR_VERSION.jar"
sudo mkdir -p /var/lib/jenkins/plugins
cat << 'EOT' | sudo tee /var/lib/jenkins/plugins.txt
configuration-as-code
job-dsl
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

# --- JCasC config + secrets -----------------------------------------
sudo mkdir -p /var/lib/jenkins/secrets-casc
printf '%s' "$JAVA21_HOME" | sudo tee /var/lib/jenkins/secrets-casc/JAVA_HOME_21

# wait for the SonarQube box to publish its analysis token to SSM (~15 min max)
for i in $(seq 1 90); do
  T=$(/usr/local/bin/aws ssm get-parameter --region ${var.region} --name /bankapp/sonar/token --with-decryption --query Parameter.Value --output text 2>/dev/null)
  if [ -n "$T" ] && [ "$T" != "PENDING" ] && [ "$T" != "None" ]; then break; fi
  sleep 10
done
[ -z "$T" ] && T="PENDING"
printf '%s' "$T" | sudo tee /var/lib/jenkins/secrets-casc/SONAR_TOKEN

cat > /tmp/casc.yaml <<'CASCEOF'
${local.jenkins_casc}
CASCEOF
sudo mv /tmp/casc.yaml /var/lib/jenkins/casc.yaml

sudo chown -R jenkins:jenkins /var/lib/jenkins
sudo chmod 700 /var/lib/jenkins/secrets-casc
sudo chmod 600 /var/lib/jenkins/casc.yaml /var/lib/jenkins/secrets-casc/*

# --- Docker engine (pipeline builds/pushes images from this host) -------
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker jenkins

# --- Trivy ------------------------------------------------------------
RELEASE_VERSION=$(grep -Po '(?<=VERSION_ID=")[0-9]' /etc/os-release)
cat << EOT | sudo tee -a /etc/yum.repos.d/trivy.repo
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$RELEASE_VERSION/\$basearch/
gpgcheck=0
enabled=1
EOT
sudo yum -y install trivy || true

# --- start Jenkins (config + secrets are now in place) -----------------
sudo systemctl daemon-reload
sudo systemctl enable --now jenkins

${local.nr_install}

# Checkov (used by the infra pre-scan, harmless here)
python3 -m pip install --user checkov --quiet || true

sudo hostnamectl set-hostname Jenkins
EOF
}
