# Своё VPC для демо не поднимаем — берём default, он в аккаунте уже есть.
# Так меньше кода и не надо думать про route tables и IGW.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Lambda и interface endpoint живут в двух AZ: одной хватило бы, но ENI endpoint'а
# тарифицируется за AZ, а две — разумный компромисс между ценой и отказоустойчивостью.
locals {
  lambda_subnet_ids = slice(sort(data.aws_subnets.default.ids), 0, 2)
}

# --- Security groups -----------------------------------------------------------
# Кто с кем имеет право разговаривать. Три группы вместо одной — чтобы правила
# ссылались друг на друга по ID, а не по IP-диапазонам.

resource "aws_security_group" "lambda" {
  name = "${var.project}-lambda"
  # Описания security group AWS тоже принимает только в ASCII
  description = "Lambda user-migration: outbound to RDS and Secrets Manager endpoint"
  vpc_id      = data.aws_vpc.default.id

  # Описания правил AWS принимает только в ASCII, поэтому они по-английски
  egress {
    description = "All outbound: RDS and Secrets Manager endpoint inside the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project}-rds"
  description = "Legacy PostgreSQL: 5432 from Lambda and developer machine only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Lambda inside the VPC"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  ingress {
    description = "Developer machine: seeding 50 users and debugging"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  # Исходящих правил нет: базе некуда ходить самой
}

resource "aws_security_group" "vpce" {
  name        = "${var.project}-vpce"
  description = "Secrets Manager interface endpoint: 443 from Lambda only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "HTTPS from Lambda"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
}

# --- Приватный доступ к Secrets Manager ---------------------------------------
# Lambda внутри VPC не имеет выхода в интернет. Секрет она достаёт через эту
# приватную «дверь»: трафик не покидает сеть AWS. Альтернатива — NAT gateway,
# он дороже ($0,045/ч против ~$0,01/ч за ENI) и открывает наружу вообще всё.
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.lambda_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project}-secretsmanager"
  }
}
