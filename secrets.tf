# ---------------------------------------------------------------------------
# Generated credentials for the platform services.
#
# Everything here is created once by Terraform and pushed into the relevant
# instance at boot (templated user-data) and/or into Jenkins via JCasC, so no
# service ever needs to be configured by hand. Retrieve any of them later with:
#
#   terraform output -raw jenkins_admin_password
#   terraform output -raw nexus_admin_password
#   terraform output -raw nexus_ci_password
#   terraform output -raw sonar_admin_password
#
# They are also mirrored into Secrets Manager (see the aws_secretsmanager_*
# resources below) for anything that would rather read them from there.
# ---------------------------------------------------------------------------

# alphanumeric only - these values get embedded in shell, JSON and YAML during
# bootstrap, so keep them free of quoting hazards.
resource "random_password" "jenkins_admin" {
  length  = 24
  special = false
}

resource "random_password" "nexus_admin" {
  length  = 24
  special = false
}

resource "random_password" "nexus_ci" {
  length  = 24
  special = false
}

resource "random_password" "sonar_admin" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "platform" {
  name                    = "bankapp-platform-credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "platform" {
  secret_id = aws_secretsmanager_secret.platform.id
  secret_string = jsonencode({
    jenkins_admin_user = "admin"
    jenkins_admin_pass = random_password.jenkins_admin.result
    nexus_admin_user   = "admin"
    nexus_admin_pass   = random_password.nexus_admin.result
    nexus_ci_user      = "ci"
    nexus_ci_pass      = random_password.nexus_ci.result
    sonar_admin_user   = "admin"
    sonar_admin_pass   = random_password.sonar_admin.result
    db_user            = var.dbusername
    db_pass            = random_password.db-password.result
  })
}

# SSM parameter the SonarQube box writes its generated analysis token into and
# the Jenkins box reads back during bootstrap (cross-instance hand-off).
resource "aws_ssm_parameter" "sonar_token" {
  name  = "/bankapp/sonar/token"
  type  = "SecureString"
  value = "PENDING" # real value is published by the sonar-bootstrap unit
  lifecycle {
    ignore_changes = [value]
  }
}
