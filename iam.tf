# ---------------------------------------------------------------------------
# Instance profiles. Kept deliberately narrow:
#   - sonar  : publish its generated analysis token to one SSM path
#   - jenkins: read that token back + read the DB / platform secrets
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  sonar_token_arn = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/bankapp/sonar/token"
  platform_secrets = [
    aws_secretsmanager_secret.platform.arn,
    aws_secretsmanager_secret.mysql-secret.arn,
  ]
}

# ---- SonarQube -------------------------------------------------------------
resource "aws_iam_role" "sonar" {
  name = "${local.name}-sonar"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "sonar" {
  name = "publish-sonar-token"
  role = aws_iam_role.sonar.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:PutParameter"]
      Resource = local.sonar_token_arn
    }]
  })
}

resource "aws_iam_instance_profile" "sonar" {
  name = "${local.name}-sonar"
  role = aws_iam_role.sonar.name
}

# ---- Jenkins -------------------------------------------------------------
resource "aws_iam_role" "jenkins" {
  name = "${local.name}-jenkins"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "jenkins" {
  name = "read-platform-secrets"
  role = aws_iam_role.jenkins.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = local.sonar_token_arn
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = local.platform_secrets
      },
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${local.name}-jenkins"
  role = aws_iam_role.jenkins.name
}
