locals {
  name = "us-team"

}


resource "null_resource" "pre_scan" {
  provisioner "local-exec" {
    command = "./checkov_scan.sh"

    interpreter = ["bash", "-c"]
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -f checkov_output.JSON"
  }

  triggers = {
    always_run = "${timestamp()}"

  }
}

output "pre_scan_status" {
  value = "Pre-scan completed. Check Slack and checkov_output.JSON file for details."
}


resource "aws_vpc" "vpc" {
  cidr_block       = var.cidr
  instance_tenancy = "default"

  tags = {
    Name = "${local.name}-vpc"
  }
}

# create public subnet 1
resource "aws_subnet" "pub_sub1" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.public_subnet_1
  availability_zone = "eu-west-3a"

  tags = {
    Name = "${local.name}-pub_sub1"
  }
}

# create public subnet 2
resource "aws_subnet" "pub_sub2" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.public_subnet_2
  availability_zone = "eu-west-3b"

  tags = {
    Name = "${local.name}-pub_sub2"
  }
}

# create private subnet 1
resource "aws_subnet" "pri_sub1" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.private_subnet_1
  availability_zone = "eu-west-3a"

  tags = {
    Name = "${local.name}-pri_sub1"
  }
}

# create private subnet 2
resource "aws_subnet" "pri_sub2" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.private_subnet_2
  availability_zone = "eu-west-3b"

  tags = {
    Name = "${local.name}-pri_sub2"
  }
}

//Creating internet Gateway 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${local.name}-IGW"
  }
}

//Creating NAT GATEWAY 
resource "aws_nat_gateway" "nat-gw" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.pub_sub1.id

  tags = {
    Name = "${local.name}-Nat-GW"
  }

}

//creating elastic ip 
resource "aws_eip" "eip" {
  domain = "vpc"

  tags = {
    Name = "${local.name}-EIP"
  }
}

//creating public route table 
resource "aws_route_table" "pub-rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = var.all-cidr
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${local.name}-pub_rt"
  }
}


//creating private route table 
resource "aws_route_table" "pri-rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = var.all-cidr
    gateway_id = aws_nat_gateway.nat-gw.id
  }
  tags = {
    Name = "${local.name}-pri-rt"
  }
}

//creating public route table association 1
resource "aws_route_table_association" "pub-RTA1" {
  subnet_id      = aws_subnet.pub_sub1.id
  route_table_id = aws_route_table.pub-rt.id
}

//creating public route table association 2
resource "aws_route_table_association" "pub-RTA2" {
  subnet_id      = aws_subnet.pub_sub2.id
  route_table_id = aws_route_table.pub-rt.id
}

//creating private route table association 1
resource "aws_route_table_association" "pri-RTA1" {
  subnet_id      = aws_subnet.pri_sub1.id
  route_table_id = aws_route_table.pri-rt.id
}

//creating private route table association 2
resource "aws_route_table_association" "pri-RTA2" {
  subnet_id      = aws_subnet.pri_sub2.id
  route_table_id = aws_route_table.pri-rt.id
}


#creating keypair RSA key of size 4096 bits
resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

//creating private key
resource "local_file" "key" {
  content         = tls_private_key.key.private_key_pem
  filename        = "bankapp-key"
  file_permission = "600"
  //depends_on      = [null_resource.pre_scan]
}

//creating public key
resource "aws_key_pair" "key" {
  key_name   = "bankapp-pub-key1"
  public_key = tls_private_key.key.public_key_openssh
}

//security group for jenkins 
resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins_sg"
  description = "instance_security_group"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH"
    protocol    = "tcp"
    from_port   = var.sshport
    to_port     = var.sshport
    cidr_blocks = [var.all-cidr]
  }

  ingress {
    description = "jenkins-port"
    protocol    = "tcp"
    from_port   = var.jenkinsport
    to_port     = var.jenkinsport
    cidr_blocks = [var.all-cidr]
  }

  ingress {
    description = "http-port"
    protocol    = "tcp"
    from_port   = var.httpport
    to_port     = var.httpport
    cidr_blocks = [var.all-cidr]
  }


  ingress {
    description = "HTTPS"
    from_port   = var.httpsport
    to_port     = var.httpsport
    protocol    = "tcp"
    cidr_blocks = [var.all-cidr]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.all-cidr]
  }
  tags = {
    name = "jenkins_sg"
  }
}

//security group for sonacube 
resource "aws_security_group" "sonarqube-sg" {
  name        = "sonacube-sg"
  description = "allowing inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH"
    protocol    = "tcp"
    from_port   = var.sshport
    to_port     = var.sshport
    cidr_blocks = [var.all-cidr]
  }

  ingress {
    description = "sona-port"
    protocol    = "tcp"
    from_port   = var.sonarport
    to_port     = var.sonarport
    cidr_blocks = [var.all-cidr]
  }

  ingress {
    description = "http-port"
    protocol    = "tcp"
    from_port   = var.httpport
    to_port     = var.httpport
    cidr_blocks = [var.all-cidr]
  }

  ingress {
    description = "HTTPS"
    from_port   = var.httpsport
    to_port     = var.httpsport
    protocol    = "tcp"
    cidr_blocks = [var.all-cidr]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.all-cidr]
  }
  tags = {
    name = "jenkins-sg"
  }
}

//security group for docker 
resource "aws_security_group" "docker-sg" {
  name        = "docker-sg"
  description = "allowing inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH"
    protocol    = "tcp"
    from_port   = var.sshport
    to_port     = var.sshport
    cidr_blocks = [var.all-cidr]
  }

  ingress {
    description = "docker-port"
    protocol    = "tcp"
    from_port   = var.dockerport
    to_port     = var.dockerport
    cidr_blocks = [var.all-cidr]
  }

  ingress {
    description = "http-port"
    protocol    = "tcp"
    from_port   = var.httpport
    to_port     = var.httpport
    cidr_blocks = [var.all-cidr]
  }

  ingress {
    description = "HTTPS"
    from_port   = var.httpsport
    to_port     = var.httpsport
    protocol    = "tcp"
    cidr_blocks = [var.all-cidr]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.all-cidr]
  }
  tags = {
    name = "docker-sg"
  }
}

//security group for ansible 
resource "aws_security_group" "ansible-baston-sg" {
  name        = "ansible-baston-sg"
  description = "allowing inbound traffic"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    description = "SSH"
    protocol    = "tcp"
    from_port   = var.sshport
    to_port     = var.sshport
    cidr_blocks = [var.all-cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.all-cidr]
  }
  tags = {
    name = "ansible-sg"
  }
}


//security group for nexus 
resource "aws_security_group" "nexus-sg" {
  name        = "nexus-sg"
  description = "allowing inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH"
    protocol    = "tcp"
    from_port   = var.sshport
    to_port     = var.sshport
    cidr_blocks = [var.all-cidr]
  }

  ingress {
    description = "nexus-port"
    protocol    = "tcp"
    from_port   = var.nexusport
    to_port     = var.nexusport
    cidr_blocks = [var.all-cidr]
  }

  ingress {
    description = "http-port"
    protocol    = "tcp"
    from_port   = var.httpport
    to_port     = var.httpport
    cidr_blocks = [var.all-cidr]
  }

  ingress {
    description = "HTTPS"
    from_port   = var.httpsport
    to_port     = var.httpsport
    protocol    = "tcp"
    cidr_blocks = [var.all-cidr]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.all-cidr]
  }
  tags = {
    name = "${local.name}-nexus-sg"
  }
}

//creating rds security group 
resource "aws_security_group" "rds-sg" {
  name        = "rds-sg"
  description = "allowing outbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description     = "MYSQL"
    protocol        = "tcp"
    from_port       = var.mysqlport
    to_port         = var.mysqlport
    security_groups = [aws_security_group.ansible-baston-sg.id, aws_security_group.docker-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.all-cidr]
    description = "allow all traffic"
  }
  tags = {
    name = "rds-sg"
  }
}

//create baston host 
resource "aws_instance" "baston-server" {
  ami                         = var.redhat_ami
  instance_type               = var.instance_type
  associate_public_ip_address = true
  key_name                    = aws_key_pair.key.id
  vpc_security_group_ids      = [aws_security_group.ansible-baston-sg.id]
  subnet_id                   = aws_subnet.pub_sub1.id
  user_data                   = <<-EOF
  #!/bin/bash 
  echo "${tls_private_key.key.private_key_pem}" >> /home/ec2-user/.ssh/id.rsa
  sudo chmod 400 /home/ec2-user/.ssh/id.rsa 
  sudo chown ec2-user:ec2-user /home/ec2-user/.ssh/id.rsa
  sudo yum install mysql -y
  sudo hostnamectl set-hostname baston 
  EOF

  tags = {
    name = "${local.name}-baston"
  }
}


#creating sonarqube_server
resource "aws_instance" "sonarqube_instance" {
  ami                         = var.ubuntu_ami
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.key.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.sonarqube-sg.id]
  subnet_id                   = aws_subnet.pub_sub1.id
  user_data                   = local.sonarqube_user_data
  metadata_options {
    http_tokens = "required"
  }
  tags = {
    Name = "SonarQube Instance"
  }
}

# Creating Ansible server
resource "aws_instance" "ansible-server" {
  ami                         = var.redhat_ami
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ansible-baston-sg.id]
  subnet_id                   = aws_subnet.pub_sub2.id
  key_name                    = aws_key_pair.key.id
  user_data                   = local.ansible_user_data
  metadata_options {
    http_tokens = "required"
  }
  tags = {
    Name = "${local.name}-ansible-server"
  }
}

# Creating Docker host
resource "aws_instance" "prod_Docker" {
  ami                         = var.redhat_ami
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.docker-sg.id]
  subnet_id                   = aws_subnet.pri_sub1.id
  key_name                    = aws_key_pair.key.id
  user_data                   = local.docker_user_data
  metadata_options {
    http_tokens = "required"
  }
  tags = {
    Name = "${local.name}-prod-docker"
  }
}

# Creating Docker host
resource "aws_instance" "stage_Docker" {
  ami                         = var.redhat_ami
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.docker-sg.id]
  subnet_id                   = aws_subnet.pri_sub1.id
  key_name                    = aws_key_pair.key.id
  user_data                   = local.docker_user_data
  metadata_options {
    http_tokens = "required"
  }
  tags = {
    Name = "${local.name}-stage-docker"
  }
}

# Creating Jenkins server
resource "aws_instance" "Jenkins" {
  ami                         = var.redhat_ami
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  subnet_id                   = aws_subnet.pub_sub1.id
  key_name                    = aws_key_pair.key.id
  user_data                   = local.jenkins_user_data
  metadata_options {
    http_tokens = "required"
  }
  tags = {
    Name = "${local.name}-jenkins"
  }
}

# Creating Nexus server
resource "aws_instance" "nexus" {
  ami                         = var.redhat_ami
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.nexus-sg.id]
  subnet_id                   = aws_subnet.pub_sub1.id
  key_name                    = aws_key_pair.key.id
  user_data                   = local.nexus_user_data
  metadata_options {
    http_tokens = "required"
  }
  tags = {
    Name = "${local.name}-nexus"
  }
}

//Creating secreets manager
resource "aws_secretsmanager_secret" "mysql-secret" {
  name                    = "mysql-secreet1"
  recovery_window_in_days = 0
}

data "aws_secretsmanager_random_password" "db-password" {
  password_length     = 10
  exclude_punctuation = true
}

resource "aws_secretsmanager_secret_version" "dbase-secret" {
  secret_id     = aws_secretsmanager_secret.mysql-secret.id
  secret_string = data.aws_secretsmanager_random_password.db-password.random_password
}

//creating subnet group 
resource "aws_db_subnet_group" "database" {
  name       = "database-sgb"
  subnet_ids = [aws_subnet.pri_sub1.id, aws_subnet.pri_sub2.id]

  tags = {
    Name = "${local.name}- db-subnet"
  }
}

//creating RDS database
resource "aws_db_instance" "bankapp-db" {
  identifier             = var.db-identifier
  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = [aws_security_group.rds-sg.id]
  allocated_storage      = 10
  db_name                = var.dbname
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t3.micro"
  username               = var.dbusername
  password               = aws_secretsmanager_secret_version.dbase-secret.secret_string
  parameter_group_name   = "default.mysql5.7"
  skip_final_snapshot    = true
  publicly_accessible    = false
  storage_type           = "gp2"
}

//Creating AMI 
resource "aws_ami_from_instance" "asg_ami" {
  name                    = "asg-ami"
  source_instance_id      = aws_instance.prod_Docker.id
  snapshot_without_reboot = true
  depends_on              = [aws_instance.prod_Docker, time_sleep.ami-sleep]
}

//Creating time sleep 
resource "time_sleep" "ami-sleep" {
  depends_on      = [aws_instance.prod_Docker]
  create_duration = "360s"
}

//creating launch template 
resource "aws_launch_template" "launch_config" {
  name          = "asg-config"
  image_id      = aws_ami_from_instance.asg_ami.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.key.id

  vpc_security_group_ids = [aws_security_group.docker-sg.id]

  lifecycle {
    create_before_destroy = true
  }
}


//Creating Auto scaling group 
resource "aws_autoscaling_group" "asg_group" {
  name                      = "${local.name}- asg"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 30
  health_check_type         = "EC2"
  desired_capacity          = 2
  force_delete              = true
  launch_template {
    id      = aws_launch_template.launch_config.id
    version = "$Latest"
  }
  vpc_zone_identifier = [aws_subnet.pub_sub1.id, aws_subnet.pub_sub2.id]
  target_group_arns   = [aws_lb_target_group.TG.arn]
  tag {
    key                 = "name"
    value               = "ASG"
    propagate_at_launch = true
  }

}

# creating autoscaling policy
resource "aws_autoscaling_policy" "autoscaling_grp-policy" {
  autoscaling_group_name = aws_autoscaling_group.asg_group.name
  name                   = "${local.name}-asg-policy"
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}
#creating Jenkins elb
resource "aws_elb" "elb-jenkins1" {
  name            = "elb-jenkins1"
  security_groups = [aws_security_group.jenkins_sg.id]
  subnets         = [aws_subnet.pub_sub1.id, aws_subnet.pub_sub2.id]

  listener {
    instance_port      = 8080
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = aws_acm_certificate.ssl-cert.arn
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "tcp:8080"
    interval            = 30
  }

  instances                   = [aws_instance.Jenkins.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400


  tags = {
    Name = "jenkins-elb"
  }
}

#creating nexus elb
resource "aws_elb" "elb-nexus1" {
  name            = "elb-nexus1"
  security_groups = [aws_security_group.nexus-sg.id]
  subnets         = [aws_subnet.pub_sub1.id, aws_subnet.pub_sub2.id]

  listener {
    instance_port      = 8081
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = aws_acm_certificate.ssl-cert.arn
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "tcp:8081"
    interval            = 30
  }

  instances                   = [aws_instance.nexus.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "nexus-elb"
  }
}

#creating stage elb
resource "aws_elb" "elb-stage" {
  name            = "elb-stage"
  security_groups = [aws_security_group.docker-sg.id]
  subnets         = [aws_subnet.pub_sub1.id, aws_subnet.pub_sub2.id]

  listener {
    instance_port      = 8080
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = aws_acm_certificate.ssl-cert.arn
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "tcp:8080"
    interval            = 30
  }

  instances                   = [aws_instance.stage_Docker.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "stage-elb"
  }
}

#creating sonar elb
resource "aws_elb" "elb-sonar1" {
  name            = "elb-sonar1"
  security_groups = [aws_security_group.sonarqube-sg.id]
  subnets         = [aws_subnet.pub_sub1.id, aws_subnet.pub_sub2.id]

  listener {
    instance_port      = 9000
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = aws_acm_certificate.ssl-cert.arn

  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "tcp:9000"
    interval            = 30
  }

  instances                   = [aws_instance.sonarqube_instance.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400


  tags = {
    Name = "sonar-elb"
  }
}

# creating target group
resource "aws_lb_target_group" "TG" {
  name     = "bankapp-TG"
  port     = var.dockerport
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 5
    interval            = 60
    timeout             = 10
    matcher             = "200-399"
  }
}

# creating target group attachment
resource "aws_lb_target_group_attachment" "TG-attach" {
  target_group_arn = aws_lb_target_group.TG.arn
  target_id        = aws_instance.stage_Docker.id
  port             = var.dockerport
}

# creating target group attachment
resource "aws_lb_target_group_attachment" "TG-attach2" {
  target_group_arn = aws_lb_target_group.TG.arn
  target_id        = aws_instance.prod_Docker.id
  port             = var.dockerport
}

# creating docker application load balancer
resource "aws_lb" "prod-docker-LB" {
  name                       = "prod-docker-LB"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.docker-sg.id]
  subnets                    = [aws_subnet.pub_sub1.id, aws_subnet.pub_sub2.id]
  enable_deletion_protection = false
  tags = {
    Name = "${local.name}-prod-docker_LB"
  }
  drop_invalid_header_fields = true
}

# creating docker load balancer http listener
resource "aws_lb_listener" "prod-docker-http-listener" {
  load_balancer_arn = aws_lb.prod-docker-LB.arn
  port              = var.httpport
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.TG.arn
  }
}

# creating docker load balancer https listener
resource "aws_lb_listener" "prod-docker-https-listener" {
  load_balancer_arn = aws_lb.prod-docker-LB.arn
  port              = var.httpsport
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.ssl-cert.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.TG.arn
  }
}

#creating ssl certificate
resource "aws_acm_certificate" "ssl-cert" {
  domain_name               = var.domain
  subject_alternative_names = ["*.${var.domain}"]
  validation_method         = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}
#creating route53 record
resource "aws_route53_record" "validate-record" {
  for_each = {
    for dvo in aws_acm_certificate.ssl-cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.selfdevops.zone_id
}
resource "aws_acm_certificate_validation" "cert-validation" {
  certificate_arn         = aws_acm_certificate.ssl-cert.arn
  validation_record_fqdns = [for record in aws_route53_record.validate-record : record.fqdn]
}

#creating route53 hosted zone
data "aws_route53_zone" "selfdevops" {
  name         = var.domain
  private_zone = false
}

#creating A jenkins record
resource "aws_route53_record" "jenkins-record" {
  zone_id = data.aws_route53_zone.selfdevops.zone_id
  name    = var.jenkins-domain
  type    = "A"
  alias {
    name                   = aws_elb.elb-jenkins1.dns_name
    zone_id                = aws_elb.elb-jenkins1.zone_id
    evaluate_target_health = true
  }
}
#creating A sonar record
resource "aws_route53_record" "sonar-record" {
  zone_id = data.aws_route53_zone.selfdevops.zone_id
  name    = var.sonar-domain
  type    = "A"
  alias {
    name                   = aws_elb.elb-sonar1.dns_name
    zone_id                = aws_elb.elb-sonar1.zone_id
    evaluate_target_health = true
  }
}
#creating A nexus record
resource "aws_route53_record" "nexus-record" {
  zone_id = data.aws_route53_zone.selfdevops.zone_id
  name    = var.nexus-domain
  type    = "A"
  alias {
    name                   = aws_elb.elb-nexus1.dns_name
    zone_id                = aws_elb.elb-nexus1.zone_id
    evaluate_target_health = true
  }
}


#creating A stage record
resource "aws_route53_record" "stage-record" {
  zone_id = data.aws_route53_zone.selfdevops.zone_id
  name    = var.stage-domain
  type    = "A"
  alias {
    name                   = aws_elb.elb-stage.dns_name
    zone_id                = aws_elb.elb-stage.zone_id
    evaluate_target_health = true
  }
}

#creating A docker record
resource "aws_route53_record" "prod-subdocker-record" {
  zone_id = data.aws_route53_zone.selfdevops.zone_id
  name    = var.docker-domain #create the same A record for selfdevops.sace
  type    = "A"
  alias {
    name                   = aws_lb.prod-docker-LB.dns_name
    zone_id                = aws_lb.prod-docker-LB.zone_id
    evaluate_target_health = true
  }
}

#creating A docker record
resource "aws_route53_record" "prod-docker-record" {
  zone_id = data.aws_route53_zone.selfdevops.zone_id
  name    = var.domain
  type    = "A"
  alias {
    name                   = aws_lb.prod-docker-LB.dns_name
    zone_id                = aws_lb.prod-docker-LB.zone_id
    evaluate_target_health = true
  }
}

