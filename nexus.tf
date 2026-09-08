locals {
  nexus_version = "3.70.1-02"

  nexus_provision_groovy = templatefile("${path.module}/nexus-provision.groovy.tftpl", {
    nexus_docker_port = var.nexusdockerport
    nexus_admin_pass  = random_password.nexus_admin.result
    nexus_ci_user     = "ci"
    nexus_ci_pass     = random_password.nexus_ci.result
  })

  nexus_user_data = <<-EOF
#!/bin/bash
set -x
exec > /var/log/bankapp-bootstrap.log 2>&1

sudo yum update -y
sudo yum install -y wget java-17-openjdk python3

# --- install Nexus ${local.nexus_version} ---------------------------------
sudo mkdir -p /app && cd /app
sudo wget -q "https://download.sonatype.com/nexus/3/nexus-${local.nexus_version}-unix.tar.gz"
sudo tar -xzf "nexus-${local.nexus_version}-unix.tar.gz"
sudo mv "nexus-${local.nexus_version}" nexus
sudo useradd nexus || true
sudo mkdir -p /app/sonatype-work/nexus3/etc

# allow the scripting API (needed for unattended provisioning; off by default)
echo 'nexus.scripts.allowCreation=true' | sudo tee -a /app/sonatype-work/nexus3/etc/nexus.properties
printf 'run_as_user="nexus"\n' | sudo tee /app/nexus/bin/nexus.rc
sudo chown -R nexus:nexus /app/nexus /app/sonatype-work

# --- systemd unit --------------------------------------------------------
cat <<'UNIT' | sudo tee /etc/systemd/system/nexus.service
[Unit]
Description=nexus service
After=network.target

[Service]
Type=forking
LimitNOFILE=65536
ExecStart=/app/nexus/bin/nexus start
ExecStop=/app/nexus/bin/nexus stop
User=nexus
Group=nexus
Restart=on-abort
# Nexus' first start takes minutes; the default 90s TimeoutStartSec would make
# systemd kill it mid-boot.
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now nexus

# --- unattended provisioning -------------------------------------------
cat > /opt/nexus-provision.groovy <<'PROVISION'
${local.nexus_provision_groovy}
PROVISION

# wait for the REST API to answer (up to ~10 min)
for i in $(seq 1 60); do
  curl -sf http://localhost:8081/service/rest/v1/status >/dev/null 2>&1 && break
  sleep 10
done

INIT_PW=$(sudo cat /app/sonatype-work/nexus3/admin.password 2>/dev/null || echo "admin123")

python3 -c "import json;print(json.dumps({'name':'bankapp-provision','type':'groovy','content':open('/opt/nexus-provision.groovy').read()}))" > /opt/nexus-provision.json

# register + run the provisioning script (retry a few times while Nexus settles)
for i in $(seq 1 12); do
  curl -sf -u "admin:$INIT_PW" -H 'Content-Type: application/json' \
       -X POST http://localhost:8081/service/rest/v1/script \
       -d @/opt/nexus-provision.json && break
  sleep 15
done
curl -sf -u "admin:$INIT_PW" -H 'Content-Type: text/plain' \
     -X POST http://localhost:8081/service/rest/v1/script/bankapp-provision/run || true

${local.nr_install}
sudo hostnamectl set-hostname Nexus
EOF
}
