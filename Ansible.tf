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

[docker_host]
${aws_instance.stage_Docker.private_ip} ansible_user=ec2-user ansible_ssh_private_key_file=/home/ec2-user/.ssh/id_rsa
${aws_instance.prod_Docker.private_ip} ansible_user=ec2-user ansible_ssh_private_key_file=/home/ec2-user/.ssh/id_rsa

EOT
sudo mkdir /opt/docker
echo "${file(var.newrelicfile)}" >> /opt/docker/newrelic.yml
touch /opt/docker/Dockerfile
cat <<EOT>> /opt/docker/Dockerfile
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
COPY *.jar /app/bankapp.jar
RUN apt-get update -y && apt-get install -y curl unzip
RUN curl -O https://download.newrelic.com/newrelic/java-agent/newrelic-agent/current/newrelic-java.zip && \
    unzip newrelic-java.zip -d /app
ENV JAVA_OPTS="$JAVA_OPTS -javaagent:/app/newrelic/newrelic.jar"
ENV NEW_RELIC_APP_NAME="bankapp"
ENV NEW_RELIC_LOG_FILE_NAME=STDOUT
ENV NEW_RELIC_LICENCE_KEY="4fe454560348c09a686f1ddf970f1af0FFFFNRAL"
ADD ./newrelic.yml /app/newrelic/newrelic.yml
ENTRYPOINT [ "java", "-javaagent:/app/newrelic/newrelic.jar", "-jar", "/app/bankapp.jar", "--server.port=8080"]
EOT

touch /opt/docker/docker-image.yml
cat <<EOT>> /opt/docker/docker-image.yml

---
 - hosts: localhost
   become: true

   tasks:
    - name: Download JAR file from Nexus repository
      get_url:
        url: http://admin:admin123@${aws_instance.nexus.public_ip}:8081/repository/nexus-repo/Bankapp/bankapp/1.0/bankapp-1.0.jar

        dest: /opt/docker/bankapp.jar

    - name: Build Docker image from JAR file
      community.docker.docker_image:
        build:
          path: /opt/docker
        name: cloudhight/bankapp
        tag: latest
        source: build
    - name: Login to Docker Hub
      community.docker.docker_login:
        username: cloudhight
        password: Motiva123@
    - name: Push Docker image to Docker Hub
      community.docker.docker_image:
        name: cloudhight/bankapp
        tag: latest
        push: yes
        source: local
    - name: Remove Docker image from Ansible server
      community.docker.docker_image:
        name: cloudhight/bankapp:latest
        state: absent
EOT

touch /opt/docker/docker-container.yml
cat <<EOT>> /opt/docker/docker-container.yml
---
 - hosts: docker_host
   become: true
   tasks:
    - name: Login to Docker Hub
      docker_login:
        username: cloudhight
        password: Motiva123@
    - name: Stop any container running
      docker_container:
        name: bankappContainer
        state: stopped
      ignore_errors: yes
    - name: Remove stopped container
      docker_container:
        name: bankappContainer
        state: absent
      ignore_errors: yes
    - name: Remove docker image
      docker_image:
        state: absent
        name: cloudhight/bankapp
        tag: latest
      ignore_errors: yes
    - name: Pull docker image from Docker Hub
      docker_image:
        name: cloudhight/bankapp
        tag: latest
        source: pull
    - name: Create container from bankapp image
      docker_container:
        name: bankappContainer
        image: cloudhight/bankapp
        state: started
        ports:
          - "8080:8080"
        detach: true
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
