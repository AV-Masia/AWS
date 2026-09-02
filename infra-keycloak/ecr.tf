# Кастомный образ Keycloak (AWS JDBC Wrapper + IAM auth к Aurora) — собирается
# и пушится вручную (см. docker/), Terraform только держит репозиторий.
# Нужен, потому что этот Aurora-кластер в аккаунте создаётся только в
# Express-режиме (без VPC) и принимает исключительно IAM DB auth token,
# а не статический пароль — стандартный образ Keycloak с quay.io это не умеет.
resource "aws_ecr_repository" "keycloak" {
  name                 = "${var.project}-keycloak"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
