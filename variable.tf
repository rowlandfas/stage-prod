variable "all-cidr" {
  default = ["0.0.0.0/0"]
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
  default = 8085
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
variable "mysqlport" {
  default = 3306
}
variable "redhat_ami" {
  default = "ami-0c55b159cbfafe1f0"
}
variable "ubuntu_ami" {
  default = "ami-0dba2cb6798deb6d8"
}
variable "instance_type" {
  default = "t2.micro"
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
  default = "mydb"
}
variable "dbname" {
  default = "mydatabase"
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