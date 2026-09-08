output "prod-docker-server" {
  value = aws_instance.prod_Docker.private_ip
}

output "stage-docker-server" {
  value = aws_instance.stage_Docker.private_ip
}

output "nexus-server" {
  value = aws_instance.nexus.public_ip
}
output "sonar-server" {
  value = aws_instance.sonarqube_instance.public_ip
}

output "ansible-server" {
  value = aws_instance.ansible-server.public_ip
}
output "jenkins-server" {
  value = aws_instance.Jenkins.public_ip
}
output "baston-server" {
  value = aws_instance.baston-server.public_ip
}

output "database-endpoint" {
  value = aws_db_instance.bankapp-db.endpoint
}

# --- service URLs --------------------------------------------------------
output "urls" {
  value = {
    jenkins = "https://${var.jenkins-domain}"
    nexus   = "https://${var.nexus-domain}"
    sonar   = "https://${var.sonar-domain}"
    stage   = "https://${var.stage-domain}"
    prod    = "https://${var.domain}"
  }
}

# --- generated credentials (sensitive) ---------------------------------
# Retrieve with:  terraform output -raw jenkins_admin_password   (etc.)
output "jenkins_admin_password" {
  value     = random_password.jenkins_admin.result
  sensitive = true
}
output "nexus_admin_password" {
  value     = random_password.nexus_admin.result
  sensitive = true
}
output "nexus_ci_password" {
  value     = random_password.nexus_ci.result
  sensitive = true
}
output "sonar_admin_password" {
  value     = random_password.sonar_admin.result
  sensitive = true
}
output "db_password" {
  value     = random_password.db-password.result
  sensitive = true
}

output "all_credentials_secret" {
  description = "Secrets Manager secret holding every generated credential as JSON."
  value       = aws_secretsmanager_secret.platform.name
}
