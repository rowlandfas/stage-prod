locals {
  ansible_user_data = <<-EOF
#!/bin/bash
sudo yum update -y
sudo yum install -y ansible-core python3 python3-pip
sudo yum install -y yum utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install docker-ce -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user
ansible-galaxy collection install community.docker
sudo chown -R ec2-user:ec2-user /etc/ansible
echo "${tls_private_key.key.private_key_pem}" >> /home/ec2-user/.ssh/id_rsa
sudo chown ec2-user:ec2-user /home/ec2-user/.ssh/id_rsa
chmod 400 id_rsa /home/ec2-user/.ssh/id_rsa
cd /etc/ansible
touch hosts
sudo chown ec2-user:ec2-user hosts
cat <<EOT> /etc/ansible/hosts
[all:vars]
ansible_ssh_common_args='-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'

localhost ansible_connection=local

[stage]
${aws_instance.stage_Docker.private_ip} ansible_user=ec2-user ansible_ssh_private_key_file=/home/ec2-user/.ssh/id_rsa

[prod]
${aws_instance.prod_Docker.private_ip} ansible_user=ec2-user ansible_ssh_private_key_file=/home/ec2-user/.ssh/id_rsa

[docker_host:children]
stage
prod

EOT
sudo mkdir -p /opt/docker

# deploy-stage.yml / deploy-prod.yml: pull the image the Jenkins pipeline pushed
# to the Nexus Docker registry and (re)run the container. Jenkins passes
#   -e image_ref=<registry>/<name>:<tag> -e registry=<registry> \
#   -e nexus_user=<user> -e nexus_pass=<pass>
touch /opt/docker/deploy-stage.yml
cat <<EOT> /opt/docker/deploy-stage.yml
---
 - hosts: stage
   become: true
   gather_facts: false
   vars:
     registry: "{{ registry | default('nexus.everythingops.io:8082') }}"
     image_ref: "{{ image_ref | default(registry + '/bankapp:latest') }}"
     nexus_user: "{{ nexus_user | default('admin') }}"
     nexus_pass: "{{ nexus_pass | default('admin123') }}"
     db_url: "{{ db_url | default('') }}"
     db_user: "{{ db_user | default('') }}"
     db_pass: "{{ db_pass | default('') }}"
   tasks:
    - name: Log in to the Nexus Docker registry
      command: "docker login {{ registry }} -u {{ nexus_user }} --password-stdin"
      args:
        stdin: "{{ nexus_pass }}"
      no_log: true
    - name: Pull the application image
      command: "docker pull {{ image_ref }}"
    - name: Render the container env file
      copy:
        dest: /opt/bankapp.env
        mode: "0600"
        content: |
          SPRING_DATASOURCE_URL={{ db_url }}
          SPRING_DATASOURCE_USERNAME={{ db_user }}
          SPRING_DATASOURCE_PASSWORD={{ db_pass }}
      no_log: true
    - name: Remove the previous container
      command: "docker rm -f bankapp"
      ignore_errors: yes
    - name: Start the new container
      command: >
        docker run -d --name bankapp --restart unless-stopped
        --env-file /opt/bankapp.env
        -p 8080:8080 {{ image_ref }}
    - name: Wait for the app to be healthy
      uri:
        url: "http://localhost:8080/actuator/health"
        status_code: [200]
      register: health
      retries: 15
      delay: 8
      until: health is success
    - name: Prune unused images to bound disk usage
      command: "docker image prune -af"
EOT

touch /opt/docker/deploy-prod.yml
cat <<EOT> /opt/docker/deploy-prod.yml
---
 - hosts: prod
   become: true
   gather_facts: false
   vars:
     registry: "{{ registry | default('nexus.everythingops.io:8082') }}"
     image_ref: "{{ image_ref | default(registry + '/bankapp:latest') }}"
     nexus_user: "{{ nexus_user | default('admin') }}"
     nexus_pass: "{{ nexus_pass | default('admin123') }}"
     db_url: "{{ db_url | default('') }}"
     db_user: "{{ db_user | default('') }}"
     db_pass: "{{ db_pass | default('') }}"
   tasks:
    - name: Log in to the Nexus Docker registry
      command: "docker login {{ registry }} -u {{ nexus_user }} --password-stdin"
      args:
        stdin: "{{ nexus_pass }}"
      no_log: true
    - name: Pull the application image
      command: "docker pull {{ image_ref }}"
    - name: Render the container env file
      copy:
        dest: /opt/bankapp.env
        mode: "0600"
        content: |
          SPRING_DATASOURCE_URL={{ db_url }}
          SPRING_DATASOURCE_USERNAME={{ db_user }}
          SPRING_DATASOURCE_PASSWORD={{ db_pass }}
      no_log: true
    - name: Remove the previous container
      command: "docker rm -f bankapp"
      ignore_errors: yes
    - name: Start the new container
      command: >
        docker run -d --name bankapp --restart unless-stopped
        --env-file /opt/bankapp.env
        -p 8080:8080 {{ image_ref }}
    - name: Wait for the app to be healthy
      uri:
        url: "http://localhost:8080/actuator/health"
        status_code: [200]
      register: health
      retries: 15
      delay: 8
      until: health is success
    - name: Prune unused images to bound disk usage
      command: "docker image prune -af"
EOT

touch /opt/docker/newrelic-container.yml
# Create yaml file to create a newrelic container
cat << EOT > /opt/docker/newrelic-container.yml
---
 - hosts: docker_host
   become: true
   tasks:
   - name: install newrelic agent
     command: docker run \\
                     -d \
                     --name newrelic-infra \
                    --network=host \
                    --cap-add=SYS_PTRACE \
                    --privileged \
                    --pid=host \
                    -v "/:/host:ro" \
                    -v "/var/run/docker.sock:/var/run/docker.sock" \
                    -e  NRIA_LICENSE_KEY=eu01xx8555b8148af8853844069791f4FFFFNRAL \
                    newrelic/infrastructure:latest
     ignore_errors: yes
EOT
sudo chown -R ec2-user:ec2-user /opt/docker
sudo chmod -R 700 /opt/docker
curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash && sudo NEW_RELIC_API_KEY=NRAK-EO270WP5BPKV1G0AMEZZI64U0HS NEW_RELIC_ACCOUNT_ID=5144160 NEW_RELIC_REGION=EU /usr/local/bin/newrelic install -y
sudo hostnamectl set-hostname Ansible


EOF     
}
