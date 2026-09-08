locals {
  nexus_user_data = <<-EOF
#!/bin/bash
set -x
exec > /var/log/bankapp-bootstrap.log 2>&1
sudo yum update -y
sudo yum install -y wget java-1.8.0-openjdk.x86_64

sudo mkdir -p /app && cd /app
sudo wget -q https://download.sonatype.com/nexus/3/nexus-3.23.0-03-unix.tar.gz
sudo tar -xzf nexus-3.23.0-03-unix.tar.gz
sudo mv nexus-3.23.0-03 nexus
sudo useradd nexus || true
sudo mkdir -p /app/sonatype-work
sudo chown -R nexus:nexus /app/nexus /app/sonatype-work
printf 'run_as_user="nexus"\n' | sudo tee /app/nexus/bin/nexus.rc

# Keep the JVM inside the box. t3.large = 8 GiB, so Nexus' 2703m default heap is
# fine, but pattern-match (not line numbers) so this can't silently no-op.
sudo sed -i 's/^-Xms2703m/-Xms2048m/; s/^-Xmx2703m/-Xmx2048m/; s/^-XX:MaxDirectMemorySize=2703m/-XX:MaxDirectMemorySize=2048m/' /app/nexus/bin/nexus.vmoptions

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
# Nexus' first start takes minutes; the default 90s TimeoutStartSec makes
# systemd kill it mid-boot.
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now nexus

curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash && sudo NEW_RELIC_API_KEY=NRAK-EO270WP5BPKV1G0AMEZZI64U0HS NEW_RELIC_ACCOUNT_ID=5144160 NEW_RELIC_REGION=EU /usr/local/bin/newrelic install -y || true
sudo hostnamectl set-hostname Nexus
EOF
}
