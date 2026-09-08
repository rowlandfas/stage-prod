locals {
  sonarqube_user_data = <<-EOF
#!/bin/bash
set -x
exec > /var/log/bankapp-bootstrap.log 2>&1
sudo apt update -y
echo "***Firstly Modify OS Level values***"
sudo bash -c 'echo "
vm.max_map_count=262144
fs.file-max=65536
ulimit -n 65536
ulimit -u 4096" >> /etc/sysctl.conf'
sudo bash -c 'echo "
sonarqube   -   nofile   65536
sonarqube   -   nproc    4096" >> /etc/security/limits.conf'
echo "***********Install Java + tools***********"
sudo apt install openjdk-11-jdk -y
sudo apt install -y unzip net-tools jq curl
# AWS CLI v2 (publishes the analysis token to SSM)
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
cd /tmp && unzip -q awscliv2.zip && sudo ./aws/install && cd /
echo "***********Install PostgreSQL 12***********"
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update -y
sudo apt-get -y install postgresql-12 postgresql-contrib-12
sudo systemctl enable postgresql
sudo systemctl start postgresql
sudo chpasswd <<<"postgres:Admin123@"
sudo su -c 'createuser sonar' postgres
sudo su -c "psql -c \"ALTER USER sonar WITH ENCRYPTED PASSWORD 'Admin123'\"" postgres
sudo su -c "psql -c \"CREATE DATABASE sonarqube OWNER sonar\"" postgres
sudo su -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE sonarqube to sonar\"" postgres
sudo systemctl restart postgresql
#Install SonarQube
sudo mkdir /sonarqube/
cd /sonarqube/
sudo wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-8.6.0.39681.zip
sudo unzip sonarqube-8.6.0.39681.zip -d /opt/
sudo mv /opt/sonarqube-8.6.0.39681/ /opt/sonarqube
sudo groupadd sonar
sudo useradd -c "SonarQube - User" -d /opt/sonarqube/ -g sonar sonar
sudo chown sonar:sonar /opt/sonarqube/ -R
sudo bash -c 'echo "
sonar.jdbc.username=sonar
sonar.jdbc.password=Admin123
sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube
sonar.search.javaOpts=-Xmx512m -Xms512m -XX:+HeapDumpOnOutOfMemoryError" >> /opt/sonarqube/conf/sonar.properties'
sudo touch /etc/systemd/system/sonarqube.service
sudo bash -c 'echo "
[Unit]
Description=SonarQube service
After=syslog.target network.target
[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
ExecReload=/opt/sonarqube/bin/linux-x86-64/sonar.sh restart
User=sonar
Group=sonar
Restart=always
LimitNOFILE=65536
LimitNPROC=4096
[Install]
WantedBy=multi-user.target" >> /etc/systemd/system/sonarqube.service'
sudo systemctl daemon-reload
sudo systemctl enable sonarqube.service
sudo systemctl start sonarqube.service
#Install nginx
sudo apt-get install nginx -y
sudo touch /etc/nginx/sites-enabled/sonarqube.conf
sudo bash -c 'echo "
server {
  listen 80;
  access_log  /var/log/nginx/sonar.access.log;
  error_log   /var/log/nginx/sonar.error.log;
  proxy_buffers 16 64k;
  proxy_buffer_size 128k;
  location / {
      proxy_pass  http://127.0.0.1:9000;
      proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
      proxy_redirect off;
      proxy_set_header    Host            \$host;
      proxy_set_header    X-Real-IP       \$remote_addr;
      proxy_set_header    X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header    X-Forwarded-Proto http;
  }
}" >> /etc/nginx/sites-enabled/sonarqube.conf'
sudo rm /etc/nginx/sites-enabled/default
sudo systemctl enable nginx.service
sudo systemctl restart nginx.service

# --- unattended bootstrap: admin pw, analysis token (-> SSM), Jenkins webhook.
# Runs from a systemd unit so it survives the reboot below; self-disables on success.
cat <<'SONARBOOT' | sudo tee /usr/local/bin/sonar-bootstrap.sh
#!/bin/bash
set -x
REGION="${var.region}"
SONAR="http://localhost:9000"
NEWPW='${random_password.sonar_admin.result}'
WEBHOOK="https://${var.jenkins-domain}/sonarqube-webhook/"

for i in $(seq 1 90); do
  st=$(curl -sf $SONAR/api/system/status | python3 -c 'import sys,json;print(json.load(sys.stdin).get("status",""))' 2>/dev/null)
  [ "$st" = "UP" ] && break
  sleep 10
done

curl -sf -u admin:admin -X POST "$SONAR/api/users/change_password" \
  --data-urlencode "login=admin" --data-urlencode "previousPassword=admin" \
  --data-urlencode "password=$NEWPW" || true

AUTH="admin:$NEWPW"
curl -sf -u "$AUTH" -X POST "$SONAR/api/user_tokens/revoke" --data-urlencode "name=jenkins" || true
TOKEN=$(curl -sf -u "$AUTH" -X POST "$SONAR/api/user_tokens/generate" \
        --data-urlencode "name=jenkins" \
        | python3 -c 'import sys,json;print(json.load(sys.stdin).get("token",""))' 2>/dev/null)

if [ -n "$TOKEN" ] && aws ssm put-parameter --region "$REGION" \
      --name /bankapp/sonar/token --type SecureString --overwrite --value "$TOKEN"; then
  curl -sf -u "$AUTH" -X POST "$SONAR/api/webhooks/create" \
    --data-urlencode "name=jenkins" --data-urlencode "url=$WEBHOOK" || true
  systemctl disable sonar-bootstrap.service
  echo "sonar-bootstrap: done"
else
  echo "sonar-bootstrap: token/SSM failed, will retry next boot"
  exit 1
fi
SONARBOOT
sudo chmod 700 /usr/local/bin/sonar-bootstrap.sh

cat <<'SONARUNIT' | sudo tee /etc/systemd/system/sonar-bootstrap.service
[Unit]
Description=bankapp SonarQube bootstrap (token + webhook)
After=network-online.target sonarqube.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sonar-bootstrap.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SONARUNIT
sudo systemctl daemon-reload
sudo systemctl enable sonar-bootstrap.service

${local.nr_install}
sudo hostnamectl set-hostname Sonarqube
sudo reboot
EOF
}
