# ──────────────────────────────────────────────────────────────────────────────
# Единственный пул проекта, целиком в коде. Он обслуживает оба задания: и вход
# через страницу Cognito (OIDC code + PKCE), и триггеры миграции с honeypot.
# Консольный пул задания 1 (eu-central-1_QTI9GPqq3) удалён как дубль.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cognito_user_pool" "main" {
  name = "${var.project}-pool"

  # Вход по email вместо отдельного имени пользователя
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Essentials — как в задании 1: тот же free tier 10 000 MAU, но доступен
  # managed login. Логи userAuthEvents требовали бы Plus, а у него free tier нет
  user_pool_tier = "ESSENTIALS"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  # Самостоятельная регистрация включена — иначе honeypot нечего защищать
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Оба триггера задания
  lambda_config {
    user_migration = aws_lambda_function.user_migration.arn
    pre_sign_up    = aws_lambda_function.pre_signup.arn
  }

  deletion_protection = "INACTIVE"
}

# Создавая триггер вне консоли Cognito, ресурсную политику функции нужно прописать
# самому: консоль делает это неявно, Terraform — нет. Условия по source_arn и
# source_account сужают доступ до одного конкретного пула в одном аккаунте.
resource "aws_lambda_permission" "cognito_user_migration" {
  statement_id   = "AllowCognitoUserMigration"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.user_migration.function_name
  principal      = "cognito-idp.amazonaws.com"
  source_arn     = aws_cognito_user_pool.main.arn
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_lambda_permission" "cognito_pre_signup" {
  statement_id   = "AllowCognitoPreSignUp"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.pre_signup.function_name
  principal      = "cognito-idp.amazonaws.com"
  source_arn     = aws_cognito_user_pool.main.arn
  source_account = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {}

# ──────────────────────────────────────────────────────────────────────────────
# App client. Публичный, без секрета — он живёт в браузере.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.project}-web"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  # ALLOW_USER_PASSWORD_AUTH обязателен для миграции: SRP скрывает пароль
  # и от Lambda тоже, а ей нужно проверить его в старой базе.
  # После миграции пользователей правильно переходить на SRP — так пишут доки.
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # «Неверный логин или пароль» вместо «такого пользователя нет» —
  # чтобы нельзя было перебором узнать, кто зарегистрирован
  prevent_user_existence_errors = "ENABLED"

  callback_urls = ["http://localhost:5173", "https://av-masia.github.io/AWS/"]
  logout_urls   = ["http://localhost:5173", "https://av-masia.github.io/AWS/"]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]
  supported_identity_providers         = ["COGNITO"]
}

# Страница входа Cognito на этом пуле — не для основного демо, а чтобы проверить,
# что honeypot не ломает регистрацию оттуда (managed login clientMetadata не передаёт)
resource "aws_cognito_user_pool_domain" "main" {
  # Имя домена не может содержать зарезервированные слова: cognito, aws, amazon.
  # Поэтому не var.project (в нём есть «cognito»), а отдельный префикс.
  domain       = "legacy-migration-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# ──────────────────────────────────────────────────────────────────────────────
# Логирование Cognito в CloudWatch
# userNotification/ERROR — ошибки доставки писем и SMS. Доступно на любом тарифе.
# Второй тип, userAuthEvents (активность входов), требует Plus + threat protection.
# Префикс /aws/vendedlogs — рекомендация доков для логов, которые пишет сам сервис.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "cognito" {
  name              = "/aws/vendedlogs/cognito/${var.project}"
  retention_in_days = 7
}

resource "aws_cognito_log_delivery_configuration" "main" {
  user_pool_id = aws_cognito_user_pool.main.id

  log_configurations {
    event_source = "userNotification"
    log_level    = "ERROR"

    cloud_watch_logs_configuration {
      log_group_arn = aws_cloudwatch_log_group.cognito.arn
    }
  }
}
