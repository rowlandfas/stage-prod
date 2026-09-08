# bankapp — infrastructure & deployment

Terraform for the full CI/CD platform that builds, scans, publishes and deploys
**bankapp** (a Spring Boot executable JAR) to a staging and a production Docker
host on AWS.

**Goal of this repo: one `terraform apply` gives you a platform that is ready to
run the pipeline — no SSH, no click-ops.** Nexus, SonarQube and Jenkins all
configure themselves at boot.

---

## 1. What gets built

| Layer | Resources |
|---|---|
| Network | 1 VPC (`10.0.0.0/16`), 2 public + 2 private subnets, IGW, 1 NAT gateway |
| CI/CD hosts | Jenkins (`t3.medium`, 50 G), Nexus (`t3.large`, 40 G), SonarQube (`t3.large`, 20 G), Ansible control node, bastion |
| App hosts | `stage_Docker`, `prod_Docker` (`t3.medium`, 30 G, private subnets) |
| Data | RDS **MySQL 8.0** (`bankapp` db); passwords in Secrets Manager |
| Load balancing | Classic ELBs for Jenkins / Nexus / Sonar / stage; ALB `prod-docker-LB` + target group `bankapp-TG` (`/actuator/health`) → `prod_Docker` |
| DNS / TLS | ACM cert for `everythingops.io` + `*`; Route53 A-records `jenkins.` `sonar.` `nexus.` `stage.` `docker.` `prod.` apex |
| IAM | Narrow instance profiles: Sonar publishes its token to SSM, Jenkins reads it back |

### Self-configuration at boot

| Box | Done automatically |
|---|---|
| **Nexus** | `docker-hosted` repo on `:8082`, Docker Bearer Token realm, admin password set, CI user `ci` created (scripting API) |
| **SonarQube** | admin password set, `jenkins` analysis token generated → **AWS SSM** `/bankapp/sonar/token`, Jenkins webhook created (systemd `sonar-bootstrap` unit, survives the box's one reboot) |
| **Jenkins** | setup wizard skipped, plugins pre-installed, **JCasC** applies: admin user, JDK/Maven tools, all credentials (`nexus-cred`, `bankapp-db`, `ansible-key`, `sonar-token`, optional `app-repo-cred`), SonarQube server, managed Maven `settings.xml`, and the **`bankapp` pipeline job** pointing at your app repo. Jenkins waits (≤15 min) for the Sonar token in SSM before starting. |

---

## 2. Prerequisites

- Terraform ≥ 1.8, AWS CLI v2, credentials in the `default` profile (region `eu-west-3`)
- A **public Route53 hosted zone for `everythingops.io`** already in the account
  (ACM DNS validation writes into it). Different domain → set `domain` +
  `*-domain` vars.
- `bash` on your workstation (the `pre_scan` provisioner runs `checkov_scan.sh`;
  it is advisory and `on_failure = continue`).

---

## 3. Deploy the platform

```bash
cp terraform.tfvars.example terraform.tfvars
#   edit terraform.tfvars  ->  set app_repo_url  (and app_repo_user/token if private)

terraform init
terraform apply        # ~20-25 min
```

Timeline: RDS ~10 min · SonarQube reboots once then bootstraps ~5 min · Jenkins
blocks on the Sonar token, so it finishes last (~15-20 min).

```bash
terraform output urls
terraform output -raw jenkins_admin_password
terraform output -raw nexus_admin_password
terraform output -raw nexus_ci_password
terraform output -raw sonar_admin_password
# everything is also in Secrets Manager:
aws secretsmanager get-secret-value --secret-id bankapp-platform-credentials \
  --query SecretString --output text --region eu-west-3 | jq
```

The SSH key for every box is written to **`./bankapp-key`** (`ec2-user@…`).

---

## 4. The bankapp application repo

Terraform already created the Jenkins job. The app repo just needs the standard
files at its root:

### `Jenkinsfile`
Use **`Jenkinsfile.txt`** from this repo verbatim (rename to `Jenkinsfile`). It
reads `ANSIBLE_HOST` / `RDS_ENDPOINT` / `DB_NAME` / `NEXUS_DOCKER_REGISTRY` from
the Jenkins global environment (injected by JCasC) — nothing to edit.

### `pom.xml`
```xml
<groupId>com.motivalogic</groupId>
<artifactId>bankapp</artifactId>
<version>1.0.0-SNAPSHOT</version>       <!-- Jenkinsfile greps artifactId then version -->

<build>
  <finalName>bankapp</finalName>        <!-- => target/bankapp.jar -->
  <plugins>
    <plugin><groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-maven-plugin</artifactId>
            <executions><execution><goals><goal>repackage</goal></goals></execution></executions></plugin>
    <plugin><groupId>org.jacoco</groupId><artifactId>jacoco-maven-plugin</artifactId><version>0.8.12</version>
      <executions>
        <execution><goals><goal>prepare-agent</goal></goals></execution>
        <execution><id>report</id><phase>verify</phase><goals><goal>report</goal></goals></execution>
      </executions></plugin>
    <plugin><groupId>org.owasp</groupId><artifactId>dependency-check-maven</artifactId><version>10.0.4</version>
      <configuration><formats><format>HTML</format><format>XML</format></formats>
        <outputDirectory>${project.build.directory}</outputDirectory></configuration></plugin>
  </plugins>
</build>

<distributionManagement>
  <repository><id>nexus</id><url>https://nexus.everythingops.io/repository/maven-releases/</url></repository>
  <snapshotRepository><id>nexus</id><url>https://nexus.everythingops.io/repository/maven-snapshots/</url></snapshotRepository>
</distributionManagement>
```
The managed `settings.xml` maps server id **`nexus`** → the `nexus-cred` CI user,
so keep the `distributionManagement` id as `nexus`.

### `Dockerfile` (repo root)
```dockerfile
FROM eclipse-temurin:21-jre-jammy
ARG JAR_FILE=target/bankapp.jar
WORKDIR /app
COPY ${JAR_FILE} /app/bankapp.jar
EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/bankapp.jar","--server.port=8080"]
```

### `application.properties`
```properties
spring.datasource.url=${SPRING_DATASOURCE_URL}
spring.datasource.username=${SPRING_DATASOURCE_USERNAME}
spring.datasource.password=${SPRING_DATASOURCE_PASSWORD}
management.endpoints.web.exposure.include=health
management.endpoint.health.probes.enabled=true
```
`/actuator/health` **must return 200 unauthenticated** — the deploy playbooks and
the ALB target group both health-check it. If Spring Security is on, permit it.

### Database schema
The deploy passes the JDBC URL/creds only. Have the app create its own schema
(Flyway / Liquibase / `spring.jpa.hibernate.ddl-auto`), **or** load it once from
the bastion:
```bash
ssh -i bankapp-key ec2-user@$(terraform output -raw baston-server)
mysql -h <database-endpoint w/o :3306> -u admin -p bankapp < schema.sql
```

---

## 5. Run the pipeline

1. Open `https://jenkins.everythingops.io`, log in as `admin` /
   `terraform output -raw jenkins_admin_password`.
2. Open the **`bankapp`** job → **Build Now**.
3. Click **Deploy to prod** at the approval gate.

| Stage | Notes |
|---|---|
| SonarQube Analysis / Quality Gate | **non-blocking** (`catchError` + `abortPipeline:false`); marks the stage UNSTABLE on Sonar trouble, never blocks the deploy. Flip in the Jenkinsfile to enforce. |
| OWASP Dependency-Check | first run downloads the NVD (slow); set a global `NVD_API_KEY` to speed it up |
| Trivy scan | **report-only** (`--exit-code 0`) until the app bumps Spring Boot 3.3.4→current, Tomcat, Jackson |
| Push image to Nexus | `docker-hosted` @ `:8082` + `nexus-cred` (both auto-created) |
| Deploy Stage / Prod | Ansible on the control node renders `/opt/bankapp.env`, runs the container, waits on `/actuator/health` |

---

## 6. Verify

```bash
curl -kI https://stage.everythingops.io/
curl -kI https://everythingops.io/            # prod (apex)
curl -kI https://prod.everythingops.io/        # prod (alias)

ssh -i bankapp-key -J ec2-user@$(terraform output -raw baston-server) \
  ec2-user@$(terraform output -raw prod-docker-server) \
  'docker ps && docker logs --tail 50 bankapp'
```

---

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| Jenkins won't start after boot | JCasC error. `sudo journalctl -u jenkins | grep -i casc`. Recover: delete `/etc/systemd/system/jenkins.service.d/casc.conf`, `systemctl daemon-reload && systemctl restart jenkins`, configure per the JCasC file by hand. |
| `bankapp` job missing / SCM wrong | `app_repo_url` was left as the placeholder. Set it in `terraform.tfvars` and `terraform apply` (Jenkins is replaced), or fix the job's Git URL in the UI. |
| `sonar-token` credential is `PENDING` | Sonar bootstrap didn't publish in time. On the Sonar box: `sudo systemctl start sonar-bootstrap && journalctl -u sonar-bootstrap`. Then restart Jenkins so JCasC re-reads `/var/lib/jenkins/secrets-casc/SONAR_TOKEN` (re-fetch it with `aws ssm get-parameter`). |
| Quality Gate hangs | Sonar→Jenkins webhook missing; bootstrap creates it. Check *Sonar → Administration → Webhooks*. |
| `docker push` → `x509` / refused on `:8082` | Nexus provisioning didn't run: `sudo cat /var/log/bankapp-bootstrap.log` on the Nexus box; re-run the script block from `nexus.tf`. |
| `mvn deploy` 401 | pom `distributionManagement` id must be `nexus`; the CI user needs write on `maven-releases`/`maven-snapshots` (it is `nx-admin`). |
| App container up, 500s | schema not loaded, or `/actuator/health` requires auth. |
| Disk fills on a box | volume sizes are `*_volume_size` vars; after a bump run `sudo growpart /dev/nvme0n1 1 && sudo xfs_growfs /`. |

Every box logs its bootstrap to **`/var/log/bankapp-bootstrap.log`**.

---

## 8. Teardown

```bash
terraform destroy
```
`skip_final_snapshot = true` on RDS. The `everythingops.io` hosted zone is not
managed here and stays. Delete `./bankapp-key` afterwards. The SSM parameter
`/bankapp/sonar/token` and the Secrets Manager secrets are removed.
