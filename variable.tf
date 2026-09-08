variable "all-cidr" {
  default = "0.0.0.0/0"
}
variable "httpport" {
  default = 80
}
variable "httpsport" {
  default = 443
}
variable "sshport" {
  default = 22
}
variable "sonarport" {
  default = 9000
}
variable "dockerport" {
  default = 8080
}

variable "jenkinsport" {
  default = 8080
}
variable "otlpport" {
  default = 4317
}
variable "nexusport" {
  default = 8081
}
variable "nexusdockerport" {
  default = 8082
}
variable "mysqlport" {
  default = 3306
}
variable "redhat_ami" {
  default = "ami-0574a94188d1b84a1"
}
variable "ubuntu_ami" {
  default = "ami-09be70e689bddcef5"
}
variable "instance_type" {
  default = "t3.medium"
}

# Root volume sizes (GiB). Defaults match the sizes the boxes were manually
# grown to; keep them here so `terraform apply` stops shrinking them back.
variable "jenkins_volume_size" {
  default = 50
}
variable "nexus_volume_size" {
  default = 40
}
variable "docker_volume_size" {
  default = 30
}
variable "cidr" {
  default = "10.0.0.0/16"
}
variable "public_subnet_1" {
  default = "10.0.1.0/24"
}
variable "public_subnet_2" {
  default = "10.0.2.0/24"
}
variable "private_subnet_1" {
  default = "10.0.3.0/24"
}
variable "private_subnet_2" {
  default = "10.0.4.0/24"
}
variable "dbusername" {
  default = "admin"
}
variable "db-identifier" {
  default = "bankapp-db"
}
variable "dbname" {
  default = "bankapp"
}
variable "domain" {
  default = "everythingops.io"
}
variable "newrelicfile" {
  default = "./newrelic.yml"
}
variable "jenkins-domain" {
  default = "jenkins.everythingops.io"
}
variable "sonar-domain" {
  default = "sonar.everythingops.io"
}
variable "nexus-domain" {
  default = "nexus.everythingops.io"
}
variable "docker-domain" {
  default = "docker.everythingops.io"
}
variable "stage-domain" {
  default = "stage.everythingops.io"
}
variable "prod-domain" {
  default = "prod.everythingops.io"
}
