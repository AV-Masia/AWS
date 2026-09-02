variable "region" {
  description = "Регион AWS"
  type        = string
  default     = "eu-central-1"
}

variable "project" {
  description = "Префикс имён и тег для всех ресурсов Keycloak-стенда"
  type        = string
  default     = "keycloak-aws"
}

variable "keycloak_image_tag" {
  description = "Тег кастомного образа Keycloak в ECR (AWS JDBC Wrapper + IAM auth к Aurora, собирается из docker/)"
  type        = string
  default     = "aurora-iam-v1"
}

variable "keycloak_admin_username" {
  description = "Логин первого администратора Keycloak (bootstrap-admin)"
  type        = string
  default     = "admin"
}

# Реальный admin-пароль Keycloak (создан один раз при bootstrap базы Aurora).
# Раньше провайдер брал пароль из random_password.keycloak_admin, но тот
# разошёлся с фактическим паролем в БД (секрет менялся уже после того, как
# Keycloak создал admin-пользователя, а смена секрета задним числом пароль в
# БД не меняет). Решили: используем этот реальный пароль как источник
# истины и синхронизируем под него Secrets Manager, а не наоборот.
# Задаётся через TF_VAR_keycloak_admin_password — см. .env (не коммитить).
# См. docs/keycloak-migration/CHANGELOG.md в репозитории korzinka.
variable "keycloak_admin_password" {
  description = "Реальный admin-пароль Keycloak. Задавать через env (.env/TF_VAR_keycloak_admin_password), не коммитить в tfvars."
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Имя базы Keycloak внутри Aurora-кластера (совпадает с тем, что создано в консоли — по умолчанию у Aurora PostgreSQL это 'postgres')"
  type        = string
  default     = "postgres"
}

variable "db_username" {
  description = "Мастер-пользователь Aurora (совпадает с тем, что создано в консоли)"
  type        = string
  default     = "postgres"
}

variable "redis_node_type" {
  description = "Тип узла ElastiCache. t4g.micro — самый дешёвый, для демо достаточно"
  type        = string
  default     = "cache.t4g.micro"
}

variable "task_cpu" {
  description = "CPU units задачи ECS Fargate (1 vCPU = 1024)"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Память задачи ECS Fargate, MiB"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Число задач Keycloak за ALB. 1 — демо, без отказоустойчивости"
  type        = number
  default     = 1
}

# --- Korzinka test-migration realm -------------------------------------------------

variable "korzinka_realm_name" {
  description = "Имя тестового реалма под миграцию Korzinka с Cognito"
  type        = string
  default     = "korzinka-test"
}

variable "korzinka_mobile_redirect_uri" {
  description = "Redirect URI мобильного клиента (совпадает с текущим Cognito-клиентом)"
  type        = string
  default     = "myapp://callback"
}

variable "google_idp_client_id" {
  description = "Google OAuth client_id для брокера входа через Google в Keycloak (тот же проект Google Cloud, что и у текущего Cognito Hosted UI)"
  type        = string
  sensitive   = true
}

variable "google_idp_client_secret" {
  description = "Google OAuth client_secret для брокера входа через Google в Keycloak"
  type        = string
  sensitive   = true
}

# --- SPI моста миграции Cognito -> Keycloak (см. docker/cognito-migration-federation/) ----

variable "cognito_lookup_url" {
  description = "Function URL Lambda cognito-lookup-by-phone (AWS/infra-korzinka-cognito, output migration_bridge_lookup_url)"
  type        = string
}

variable "cognito_lookup_secret" {
  description = "Shared secret для заголовка X-Lookup-Secret (output migration_bridge_lookup_secret) — TEST ONLY"
  type        = string
  sensitive   = true
}

variable "mock_otp_code" {
  description = "Мок-код вместо реального SMS OTP, выставляется SPI как пароль новых пользователей — TEST ONLY"
  type        = string
  default     = "123456"
}
