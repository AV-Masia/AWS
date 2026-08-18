# Пароль генерирует Terraform, человек его не видит и никуда не вставляет руками.
# special = false осознанно: спецсимволы в пароле ломают строки подключения вида
# postgres://user:pass@host, а 32 символа [A-Za-z0-9] — это ~190 бит энтропии.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "legacy_db" {
  name        = var.secret_name
  description = "Креды legacy PostgreSQL для Lambda user-migration"

  # 0 — чтобы terraform destroy действительно удалял секрет, а не «планировал
  # удаление на 30 дней». Иначе повторный apply упрётся в занятое имя.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "legacy_db" {
  secret_id = aws_secretsmanager_secret.legacy_db.id

  secret_string = jsonencode({
    host     = aws_db_instance.legacy.address
    port     = aws_db_instance.legacy.port
    dbname   = var.db_name
    username = var.db_username
    password = random_password.db.result
  })
}
