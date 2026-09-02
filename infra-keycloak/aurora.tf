# Пароль генерирует Terraform: special = false, чтобы не ломать строки подключения.
resource "random_password" "db" {
  length  = 32
  special = false
}

# Настоящая Aurora: создана вручную через консоль (Standard create) из-за
# FreeTierRestrictionError при попытке создать через API/Terraform напрямую,
# затем импортирована в state. Идентификаторы, версия и master_username ниже
# подогнаны под то, что реально создалось в консоли (см. terraform import).
#
# ВАЖНО: этот кластер создан БЕЗ VPC (упрощённая сетевая модель Aurora —
# "Internet access gateway" вместо VPC security group). ModifyDBCluster
# с vpc_security_group_ids отклоняется API ("VPC networking is disabled"),
# поэтому в отличие от остального стенда изоляция на уровне security group
# для Aurora невозможна — доступ защищён только паролем/IAM-аутентификацией.
# aws_db_subnet_group.aurora и aws_security_group.aurora по этой же причине
# убраны: их некуда прикрепить.
resource "aws_rds_cluster" "keycloak" {
  cluster_identifier = "database-1"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "17.7"

  database_name   = var.db_name
  master_username = var.db_username
  master_password = random_password.db.result

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 1
  }

  # Реальный кластер создан не зашифрованным — включить шифрование постфактум
  # нельзя без пересоздания, поэтому код отражает факт, а не желаемое.
  storage_encrypted                   = false
  iam_database_authentication_enabled = true
  backup_retention_period             = 1
  skip_final_snapshot                 = true
  deletion_protection                 = false
  apply_immediately                   = true

  # database_name — ForceNew-атрибут, который API при describe отдаёт не так,
  # как ожидает провайдер после import: план показывает его как "появившийся
  # из null" и требует пересоздания кластера. Значение уже верно по факту
  # (см. консоль) — просто не даём Terraform предлагать замену настоящей
  # Aurora из-за артефакта импорта.
  lifecycle {
    ignore_changes = [database_name]
  }
}

resource "aws_rds_cluster_instance" "keycloak" {
  identifier         = "database-1-instance-1"
  cluster_identifier = aws_rds_cluster.keycloak.id
  engine             = aws_rds_cluster.keycloak.engine
  engine_version     = aws_rds_cluster.keycloak.engine_version
  instance_class     = "db.serverless"

  publicly_accessible          = false
  performance_insights_enabled = false
  apply_immediately            = true
}
