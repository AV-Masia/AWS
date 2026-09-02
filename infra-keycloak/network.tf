# Своё VPC не поднимаем — берём default, как и в infra/ (задание Cognito).
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  # Минимум две AZ нужны и ALB, и Aurora subnet group, и ElastiCache subnet group.
  subnet_ids = slice(sort(data.aws_subnets.default.ids), 0, 2)
}

# --- Security groups -----------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb"
  description = "Public ALB in front of Keycloak: 80 from internet"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from internet (demo, no custom domain / ACM cert)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "To Keycloak tasks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "keycloak" {
  name        = "${var.project}-keycloak"
  description = "Keycloak ECS tasks: 8080 from ALB, outbound to Aurora/Redis/ECR"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # ALB health check бьёт в management interface (порт 9000), не в 8080
  ingress {
    description     = "Health check from ALB (management interface)"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound: Aurora, Redis, ECR, CloudWatch Logs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "redis" {
  name        = "${var.project}-redis"
  description = "ElastiCache Redis: 6379 from Keycloak tasks only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Keycloak tasks"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.keycloak.id]
  }
}
