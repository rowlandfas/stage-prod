# bankapp — infrastructure & deployment guide

Terraform for the full CI/CD platform that builds, scans, publishes and deploys
**bankapp** (a Spring Boot app packaged as an executable JAR) to a staging and a
production Docker host on AWS.

This README is the end-to-end runbook: from an empty AWS account to bankapp
running in stage and prod.

---

## 1. What gets built

| Layer | Resources |
|---|---|
| Network | 1 VPC (`10.0.0.0/16`), 2 public + 2 private subnets, IGW, 1 NAT gateway, route tables |
| CI/CD hosts (`t3.medium`, public subnets) | Jenkins, Nexus, SonarQube, Ansible control node, bastion |
| App hosts (`t3.medium`, private subnets) | `stage_Docker`, `prod_Docker` |
| Data | RDS MySQL 5.7 (`bankapp` db), Secrets Manager secret `mysql-secreet1` |
| Load balancing | Classic ELBs for Jenkins / Nexus / Sonar / stage; ALB `prod-docker-LB` + target group `bankapp-TG` (:8080, `prod_Docker` + ASG only) for prod; ASG (min 1 / desired 2 / max 5) baked from `prod_Docker` |
| DNS / TLS | ACM cert for `everythingops.io` + `*.everythingops.io`; Route53 A-records: `jenkins.`, `sonar.`, `nexus.`, `stage.`, `docker.`, `prod.`, apex |
| Root volumes | Jenkins 50 G, Nexus 40 G, `stage_Docker` / `prod_Docker` / ASG 30 G (`*_volume_size` vars) — the default 10 G fills within a few deploys |

### Pipeline flow (Jenkinsfile lives in the **bankapp app repo**, not here)

```
Checkout ─► SonarQube Analysis ─► Quality Gate ─► OWASP Dependency-Check ─►
Build & Unit Test ─► Publish JAR to Nexus ─► Build Docker image ─► Trivy scan ─►
Push image to Nexus ─► Deploy to Stage ─►  [manual approval]  ─► Deploy to Prod
```

Deploy is performed by Ansible on the control node: playbooks
`/opt/docker/deploy-stage.yml` and `/opt/docker/deploy-prod.yml` (baked in by
`Ansible.tf`) pull the image the pipeline pushed to the Nexus Docker registry and
run the `bankapp` container on the `[stage]` / `[prod]` inventory group.

---

## 2. Prerequisites

**On your workstation**

- Terraform ≥ 1.8, AWS CLI v2
- AWS credentials for the target account in the `default` profile
  (`aws configure`), with rights to create everything in section 1
- Region is **`eu-west-3`** (set in `provider.tf`)
- `bash` (the `null_resource.pre_scan` provisioner runs `./checkov_scan.sh`);
  optionally `checkov` and `jq` if you want that pre-scan to actually run

**In AWS, before the first apply**

- A **public Route53 hosted zone for `everythingops.io`** must already exist in
  this account — `data "aws_route53_zone" "selfdevops"` looks it up and the ACM
  DNS validation writes into it. To use a different domain, change `var.domain`
  and the `*-domain` variables in `variable.tf`.

**The bankapp application repo** (GitHub/GitLab) — see section 6 for the
`pom.xml` / `Dockerfile` requirements.

---

## 3. Phase 1 — Provision the infrastructure

```bash
git clone <this repo> && cd stageprod
terraform init
terraform plan -out tf.plan      # review: ~60 resources to add
terraform apply tf.plan
```

Expect **15–25 min** (a forced 6-min `time_sleep.ami-sleep`, ~5 min RDS, ~6 min
AMI bake). When it finishes:

```bash
terraform output
```

| Output | Use |
|---|---|
| `jenkins-server` | SSH to the Jenkins box |
| `nexus-server` | SSH to the Nexus box |
| `sonar-server` | SSH to the SonarQube box |
| `ansible-server` | **paste into the Jenkinsfile `ANSIBLE_HOST`** |
| `baston-server` | bastion (MySQL client) |
| `database-endpoint` | `host:3306` — **paste into the Jenkinsfile `RDS_ENDPOINT`** |
| `prod-docker-server` / `stage-docker-server` | private IPs of the app hosts |

Terraform also writes the SSH private key to **`./bankapp-key`** (mode 600). This
one key opens every instance (`ec2-user@…`).

URLs once the boxes finish their user-data (SonarQube reboots once — give it
~8–10 min):

| Service | URL | First credentials |
|---|---|---|
| Jenkins | `https://jenkins.everythingops.io` | `sudo cat /var/lib/jenkins/secrets/initialAdminPassword` |
| Nexus | `https://nexus.everythingops.io` | `sudo cat /app/sonatype-work/nexus3/admin.password` |
| SonarQube | `https://sonar.everythingops.io` | `admin` / `admin` |

> DNS may take a few minutes to propagate. Only HTTPS (443) is wired on the
> Jenkins/Nexus/Sonar ELBs — there is no port-80 listener.

---

## 4. Phase 2 — Bootstrap Nexus

SSH: `ssh -i bankapp-key ec2-user@<nexus-server>`

1. **Log in** at `https://nexus.everythingops.io` as `admin` with the password
   from `/app/sonatype-work/nexus3/admin.password`. Set a new password. You may
   leave anonymous access enabled or disabled.
2. **Maven repositories** — `maven-releases` and `maven-snapshots` exist by
   default. The pipeline's `mvn deploy` publishes here (the app `pom.xml`
   `distributionManagement` must point at them — section 6).
3. **Docker (hosted) repository**
   - *Settings → Repositories → Create repository → `docker (hosted)`*
   - Name: `docker-hosted`
   - **HTTP connector: `8082`** (this is what `Ansible.tf` and the Jenkinsfile
     assume — `var.nexusdockerport`)
   - Save
4. **Enable the Docker token realm**
   - *Settings → Security → Realms* → move **`Docker Bearer Token Realm`** to the
     active column → Save (required for `docker login`)
5. **CI user** (recommended over using `admin`)
   - *Settings → Security → Users → Create local user*, e.g. `ci` /
     `<strong-pass>`
   - Roles: a custom role with
     `nx-repository-view-docker-docker-hosted-*` and
     `nx-repository-view-maven2-maven-snapshots-*` (add `-add`, `-edit`,
     `-browse`, `-read`), or `nx-admin` for a lab setup.

TLS is terminated at the ELB with the real ACM cert, so
`nexus.everythingops.io:8082` is valid HTTPS — **no Docker `insecure-registries`
config is needed** anywhere.

---

## 5. Phase 3 — Bootstrap SonarQube

SSH: `ssh -i bankapp-key ec2-user@<sonar-server>` (Ubuntu — user is `ubuntu`)

1. **Log in** at `https://sonar.everythingops.io` as `admin` / `admin`, change
   the password.
2. **Generate a token** — *My Account → Security → Generate Tokens* → type
   "Global Analysis Token", name `jenkins`. Copy it.
3. **Webhook back to Jenkins** (required for the `Quality Gate` stage /
   `waitForQualityGate`)
   - *Administration → Configuration → Webhooks → Create*
   - Name: `jenkins`
   - URL: `https://jenkins.everythingops.io/sonarqube-webhook/`
4. Leave the **`Sonar way`** quality gate as default, or create your own and set
   it as default.

---

## 6. Phase 4 — Prepare the bankapp application repo

The Jenkinsfile (delivered separately — put it at the repo root) expects:

### `pom.xml`

```xml
<groupId>com.motivalogic</groupId>
<artifactId>bankapp</artifactId>
<version>1.0.0-SNAPSHOT</version>          <!-- Jenkinsfile greps artifactId then version -->

<properties>
  <sonar.projectKey>bankapp</sonar.projectKey>
  <sonar.projectName>bankapp</sonar.projectName>
</properties>

<build>
  <finalName>bankapp</finalName>            <!-- => target/bankapp.jar -->
  <plugins>
    <plugin>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-maven-plugin</artifactId>
      <configuration><mainClass>...</mainClass></configuration>
      <executions><execution><goals><goal>repackage</goal></goals></execution></executions>
    </plugin>
    <plugin>
      <groupId>org.jacoco</groupId>
      <artifactId>jacoco-maven-plugin</artifactId>
      <version>0.8.12</version>
      <executions>
        <execution><goals><goal>prepare-agent</goal></goals></execution>
        <execution><id>report</id><phase>verify</phase><goals><goal>report</goal></goals></execution>
      </executions>
    </plugin>
    <plugin>
      <groupId>org.owasp</groupId>
      <artifactId>dependency-check-maven</artifactId>
      <version>10.0.4</version>
      <configuration>
        <formats><format>HTML</format><format>XML</format></formats>
        <outputDirectory>${project.build.directory}</outputDirectory>
      </configuration>
    </plugin>
  </plugins>
</build>

<distributionManagement>
  <repository>
    <id>nexus</id>
    <url>https://nexus.everythingops.io/repository/maven-releases/</url>
  </repository>
  <snapshotRepository>
    <id>nexus</id>
    <url>https://nexus.everythingops.io/repository/maven-snapshots/</url>
  </snapshotRepository>
</distributionManagement>
```

### `Dockerfile` (repo root)

```dockerfile
FROM eclipse-temurin:21-jre-jammy
ARG JAR_FILE=target/bankapp.jar
WORKDIR /app
COPY ${JAR_FILE} /app/bankapp.jar
EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/bankapp.jar","--server.port=8080"]
```

### Database wiring

The deploy playbooks write `/opt/bankapp.env` on the target host and pass it to
`docker run --env-file`, populated from Jenkins:

```
SPRING_DATASOURCE_URL=jdbc:mysql://<database-endpoint>/bankapp
SPRING_DATASOURCE_USERNAME=<DB_CREDS user>
SPRING_DATASOURCE_PASSWORD=<DB_CREDS password>
```

Your `application.properties` should read those standard Spring env vars (they
map to `spring.datasource.*` automatically). The RDS master user is `admin`; its
password is in Secrets Manager (`mysql-secreet1`) — retrieve it with:

```bash
aws secretsmanager get-secret-value --secret-id mysql-secreet1 \
  --query SecretString --output text --region eu-west-3
```

Load the bankapp schema once from the bastion (which has the MySQL client and
sits in an SG allowed to reach RDS):

```bash
ssh -i bankapp-key ec2-user@<baston-server>
mysql -h <database-endpoint-without-:3306> -u admin -p bankapp < schema.sql
```

---

## 7. Phase 5 — Bootstrap Jenkins

SSH: `ssh -i bankapp-key ec2-user@<jenkins-server>`

The user-data already installed **Java 21**, Maven, Docker, Trivy and
pre-installed the pipeline plugins (`config-file-provider`, `sonar`,
`nexus-artifact-uploader`, `dependency-check`, `docker-workflow`, `ssh-agent`,
`pipeline-utility-steps`, `htmlpublisher`, `slack`, `jacoco`, …).

1. **Unlock** at `https://jenkins.everythingops.io` with
   `/var/lib/jenkins/secrets/initialAdminPassword`, choose **"Select plugins to
   install" → none** (they're already baked in), create your admin user.

2. **Global Tool Configuration** (*Manage Jenkins → Tools*) — names must match
   the Jenkinsfile `tools{}` block:
   - JDK: name **`java`**, uncheck "Install automatically",
     `JAVA_HOME=/usr/lib/jvm/java-21-openjdk` (confirm the exact dir with
     `ls -d /usr/lib/jvm/java-21-openjdk*` — use the symlink if present)
   - Maven: name **`maven`**, uncheck "Install automatically",
     `MAVEN_HOME=/usr/share/maven`

3. **SonarQube server** (*Manage Jenkins → System → SonarQube servers*)
   - Name: **`sonarqube`**
   - Server URL: `https://sonar.everythingops.io`
   - Server authentication token: **Add → Secret text** = the Sonar token from
     Phase 3 (id e.g. `sonar-token`), then select it

4. **Credentials** (*Manage Jenkins → Credentials → System → Global*)

   | ID | Kind | Value |
   |---|---|---|
   | `nexus-cred` | Username/password | Nexus CI user (Docker push **and** Maven deploy) |
   | `ansible-key` | SSH username with private key | username `ec2-user`, private key = contents of `./bankapp-key` |
   | `bankapp-db` | Username/password | `admin` / the `mysql-secreet1` secret value |
   | `sonar-token` | Secret text | (already added in step 3) |

5. **Managed Maven settings** (*Manage Jenkins → Managed files → Add a new
   Config → "Maven settings.xml"*)
   - ID: **`nexus-maven-settings`** (matches the Jenkinsfile `MAVEN_SETTINGS`)
   - Content:

<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">

  <servers>
    <server>
      <id>nexus</id>
      <username>admin</username>
      <password>admin123</password>
    </server>
    <server>
      <id>nexus-releases</id>
      <username>admin</username>
      <password>admin123</password>
    </server>
    <server>
      <id>nexus-snapshots</id>
      <username>admin</username>
      <password>admin123</password>
    </server>
  </servers>

  <mirrors>
    <mirror>
      <id>nexus</id>
      <name>Nexus Public Mirror</name>
      <url>https://nexus.everythingops.io/repository/maven-public/</url>
      <mirrorOf>*</mirrorOf>
    </mirror>
  </mirrors>

</settings>
   Use the "Server Credentials" mapping in the managed-file editor to bind
   `nexus` → `nexus-cred` instead of hard-coding the password.

6. **Fill the Jenkinsfile placeholders** in your app repo:
   - `ANSIBLE_HOST` = `terraform output -raw ansible-server`
   - `RDS_ENDPOINT` = `terraform output -raw database-endpoint`

7. **First-run SSH trust**: from the Jenkins box, make one manual SSH so the
   `known_hosts`/agent path is warm (optional — the Jenkinsfile uses
   `StrictHostKeyChecking=no`):
   ```bash
   sudo -u jenkins ssh -i /dev/stdin ec2-user@<ansible-server> hostname   # paste key, or just rely on -o flags
   ```

---

## 8. Phase 6 — Create & run the pipeline

1. *New Item → Pipeline* (or *Multibranch Pipeline*), name `bankapp`.
2. **Pipeline → Definition: "Pipeline script from SCM"**, SCM Git, repo URL of
   the bankapp app repo, credentials if private, **Script Path: `Jenkinsfile`**.
3. **Build Now.**

Stage-by-stage expectation:

| Stage | Needs |
|---|---|
| Checkout | repo reachable |
| SonarQube Analysis | `sonarqube` server + `nexus-maven-settings` |
| Quality Gate | Sonar → Jenkins webhook (Phase 3.3) |
| OWASP Dependency-Check | `dependency-check-maven` in pom; first run downloads the NVD (slow — set a global `NVD_API_KEY` env var to speed it up) |
| Build & Unit Test | `mvn clean verify`, jacoco + surefire output |
| Publish JAR to Nexus | `distributionManagement` + `nexus` server creds |
| Build Docker image | Docker on the Jenkins host (installed by user-data), `Dockerfile` at root |
| Trivy scan | currently **report-only** (`--exit-code 0`) — flip back to `--exit-code 1` after bumping Spring Boot 3.3.4 → current, Tomcat and Jackson |
| Push image to Nexus | `docker-hosted` repo + connector 8082 + token realm + `nexus-cred` |
| Deploy to Stage | `ansible-key`, `ANSIBLE_HOST` reachable on 22, playbook renders `/opt/bankapp.env` and runs the container |
| Approve production deployment | click **Deploy to prod** in the Jenkins UI (1-hour timeout) |
| Deploy to Prod | same against the `[prod]` group |

---

## 9. Phase 7 — Verify

```bash
# Stage (classic ELB → stage_Docker:8080)
curl -kI https://stage.everythingops.io/

# Prod (ALB → bankapp-TG → prod_Docker + ASG instances)
curl -kI https://everythingops.io/
curl -kI https://docker.everythingops.io/
curl -kI https://prod.everythingops.io/

# On a docker host (hop via bastion or ansible node — private subnets)
ssh -i bankapp-key -J ec2-user@<baston-server> ec2-user@<prod-docker-server> \
  'docker ps && docker logs --tail 50 bankapp'
```

The ALB target group health check accepts HTTP `200-399` on `/` (so the Spring
Security `/` → `/login` redirect counts as healthy). The Ansible deploy
playbooks gate on `GET /actuator/health` returning `200`, so the app must expose
the Spring Boot Actuator health endpoint unauthenticated.

New Relic: an APM app named **`bankapp`** and infra hosts should appear in the EU
account baked into the user-data.

---

## 10. "Does destroy + reapply just work?"

- **Infrastructure:** yes. `terraform destroy` then `terraform apply` rebuilds
  everything; all user-data re-runs from scratch. `aws_instance.Jenkins` and
  `aws_instance.ansible-server` carry `user_data_replace_on_change = true`, so
  editing their scripts also forces a clean rebuild on a normal `apply`.
- **The CI/CD app delivery:** no — Phases 2–8 (Nexus repos, Sonar token +
  webhook, Jenkins job + credentials + managed file, Jenkinsfile placeholders,
  DB schema load) are manual one-time setup and must be redone after a full
  recreate.

---

## 11. Troubleshooting

| Symptom | Fix |
|---|---|
| `No such DSL method 'configFile'` | `config-file-provider` plugin missing — it's in the user-data list; on an already-running box install it via *Manage Jenkins → Plugins* |
| Jenkins won't start / wrong Java | `systemctl cat jenkins` should show the `java.conf` drop-in pointing at `/usr/lib/jvm/java-21-openjdk*/bin/java` |
| `docker: command not found` in pipeline | user-data installs `docker-ce` after Jenkins and restarts it; on an old instance install Docker and `usermod -aG docker jenkins && systemctl restart jenkins` |
| `docker push` → `x509` / `connection refused` on :8082 | Nexus docker connector not on 8082, token realm not enabled, or `var.nexusdockerport` ingress/listener not applied |
| `systemctl start nexus` fails but `/app/nexus/bin/nexus start` works | old boxes: the unit had no `TimeoutStartSec` and a duplicate SysV init.d entry. Fix in place: `sudo rm -f /etc/init.d/nexus; sudo chkconfig --del nexus 2>/dev/null; ` then recreate `/etc/systemd/system/nexus.service` from `nexus.tf`, `sudo systemctl daemon-reload && sudo systemctl enable --now nexus` |
| Quality Gate stage hangs then times out | Sonar webhook to `https://jenkins.everythingops.io/sonarqube-webhook/` not configured |
| `mvn deploy` 401 | `nexus-maven-settings` server id ≠ pom `distributionManagement` id, or `nexus-cred` lacks write on the repo |
| Deploy stage: `ssh: connect ... timed out` | `ANSIBLE_HOST` placeholder not replaced, or you used the private IP |
| App container up but 500s on DB | `bankapp` schema not loaded, or `bankapp-db` credential password ≠ current `mysql-secreet1` secret |
| `checkov: command not found` during apply | cosmetic — `checkov_scan.sh` exits 0; install `checkov` locally to enable the pre-scan |

---

## 12. Teardown

```bash
terraform destroy
```

`skip_final_snapshot = true` on the RDS instance and `force_delete = true` on the
ASG, so destroy is clean. The ACM cert + Route53 validation records are removed
too; the `everythingops.io` hosted zone itself is **not** managed here and stays.
Delete the local `bankapp-key` afterwards.
