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
  value = aws_db_instance.pet-clinic-db.endpoint
}