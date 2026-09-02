resource "aws_secretsmanager_secret" "keycloak_admin" {
  name                    = "${var.project}/keycloak-admin"
  description             = "Пароль первого администратора Keycloak"
  recovery_window_in_days = 0
}

# secret_string держим равным реальному паролю в Keycloak (var.keycloak_admin_password),
# а не сгенерированному random_password — см. variables.tf, история рассинхрона в
# docs/keycloak-migration/CHANGELOG.md (репозиторий korzinka).
resource "aws_secretsmanager_secret_version" "keycloak_admin" {
  secret_id = aws_secretsmanager_secret.keycloak_admin.id
  secret_string = jsonencode({
    username = var.keycloak_admin_username
    password = var.keycloak_admin_password
  })
}

resource "aws_secretsmanager_secret" "aurora_db" {
  name                    = "${var.project}/aurora-db"
  description             = "Креды Aurora PostgreSQL для Keycloak"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "aurora_db" {
  secret_id = aws_secretsmanager_secret.aurora_db.id
  secret_string = jsonencode({
    host     = aws_rds_cluster.keycloak.endpoint
    port     = aws_rds_cluster.keycloak.port
    dbname   = var.db_name
    username = var.db_username
    password = random_password.db.result
  })
}
