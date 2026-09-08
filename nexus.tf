locals {
  nexus_user_data = <<-EOF
#!/bin/bash
sudo yum update -y
sudo yum install wget -y
sudo yum install java-1.8.0-openjdk.x86_64 -y
sudo mkdir /app && cd /app
sudo wget http://download.sonatype.com/nexus/3/nexus-3.23.0-03-unix.tar.gz
sudo tar -xvf nexus-3.23.0-03-unix.tar.gz
sudo mv nexus-3.23.0-03 nexus
sudo adduser nexus
sudo mkdir -p /app/sonatype-work
sudo chown -R nexus:nexus /app/nexus /app/sonatype-work
cat <<EOT | sudo tee /app/nexus/bin/nexus.rc
run_as_user="nexus"
EOT

# Heap: keep well clear of the t3.medium 4 GiB (OS + JVM direct memory). Raise
# these together with the instance size if Nexus needs more headroom.
sed -i '2s/-Xms2703m/-Xms1024m/' /app/nexus/bin/nexus.vmoptions
sed -i '3s/-Xmx2703m/-Xmx1024m/' /app/nexus/bin/nexus.vmoptions
sed -i '4s/-XX:MaxDirectMemorySize=2703m/-XX:MaxDirectMemorySize=1024m/' /app/nexus/bin/nexus.vmoptions

cat <<EOT | sudo tee /etc/systemd/system/nexus.service
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
# systemd kill it mid-boot, which is why it was "only restartable via bin/nexus".
TimeoutStartSec=600
[Install]
WantedBy=multi-user.target
EOT

sudo systemctl daemon-reload
sudo systemctl enable --now nexus
curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash && sudo NEW_RELIC_API_KEY=NRAK-EO270WP5BPKV1G0AMEZZI64U0HS NEW_RELIC_ACCOUNT_ID=5144160 NEW_RELIC_REGION=EU /usr/local/bin/newrelic install -y
sudo hostnamectl set-hostname Nexus
EOF
}