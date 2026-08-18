# Группа подсетей обязательна, и в ней нужно минимум две AZ — даже для Single-AZ
# инстанса. На группу «default» полагаться нельзя: она есть не в каждом аккаунте.
resource "aws_db_subnet_group" "legacy" {
  name       = "${var.project}-legacy"
  subnet_ids = data.aws_subnets.default.ids
}

# «Старая база» из постановки задания. Демо-конфигурация: Single-AZ, без бэкапов,
# без защиты от удаления — чтобы terraform destroy проходил без сюрпризов.
resource "aws_db_instance" "legacy" {
  identifier     = "${var.project}-legacy"
  engine         = "postgres"
  engine_version = "18"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.legacy.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Публичный endpoint нужен, чтобы засеять 50 пользователей с ноутбука.
  # Доступ ограничен security group'ой на один IP; в проде здесь false.
  publicly_accessible = true

  backup_retention_period    = 0
  skip_final_snapshot        = true
  deletion_protection        = false
  auto_minor_version_upgrade = true
  apply_immediately          = true

  # Performance Insights и Enhanced Monitoring на t4g.micro не нужны и стоят денег
  performance_insights_enabled = false
}
