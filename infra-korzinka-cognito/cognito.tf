# ──────────────────────────────────────────────────────────────────────────────
# Тестовый эталонный пул под миграцию Korzinka с Cognito на Keycloak
# (см. korzinka/docs/keycloak-migration/CHANGELOG.md и MIGRATION.md).
# В отличие от AWS/infra (другой, несвязанный проект — email/password +
# legacy-migration), этот пул воспроизводит именно прод-флоу Korzinka:
# вход по номеру телефона (CUSTOM_AUTH, мок-OTP) + Google Hosted UI.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_cognito_user_pool" "korzinka" {
  name = "${var.project}-pool"

  username_attributes = ["phone_number"]

  # Самостоятельная регистрация нужна: мобильное приложение при первом входе
  # само вызывает signUp() на UserNotFoundException (см. AuthService.sendOTP).
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  lambda_config {
    define_auth_challenge          = aws_lambda_function.trigger["define_auth_challenge"].arn
    create_auth_challenge          = aws_lambda_function.trigger["create_auth_challenge"].arn
    verify_auth_challenge_response = aws_lambda_function.trigger["verify_auth_challenge"].arn
    pre_sign_up                    = aws_lambda_function.trigger["pre_signup_autoconfirm"].arn
  }

  deletion_protection = "INACTIVE"
}

resource "aws_cognito_identity_provider" "google" {
  user_pool_id  = aws_cognito_user_pool.korzinka.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.google_idp_client_id
    client_secret     = var.google_idp_client_secret
    authorize_scopes  = "openid email profile"
  }

  attribute_mapping = {
    email    = "email"
    name     = "name"
    username = "sub"
  }
}

resource "aws_cognito_user_pool_client" "mobile" {
  name         = "${var.project}-mobile"
  user_pool_id = aws_cognito_user_pool.korzinka.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # ВАЖНО: НЕ "ENABLED". С этой защитой Cognito не бросает UserNotFoundException
  # на initiateAuth для несуществующего пользователя (чтобы нельзя было
  # перебором узнать, кто зарегистрирован) — а именно на этом исключении
  # держится автосоздание пользователя в AuthService.sendOTP() (см.
  # auth_service.dart: catch на UserNotFoundException -> signUp()). С
  # "ENABLED" Cognito молча выдаёт CUSTOM_CHALLENGE для любого username,
  # signUp() не вызывается, и логин падает на RespondToAuthChallenge с
  # "NotAuthorizedException: Incorrect username or password" — реально
  # воспроизведено при тестировании на устройстве, см.
  # docs/keycloak-migration/CHANGELOG.md в репозитории korzinka.
  prevent_user_existence_errors = "LEGACY"

  callback_urls = [var.mobile_redirect_uri]
  logout_urls   = [var.mobile_redirect_uri]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO", aws_cognito_identity_provider.google.provider_name]
}

resource "aws_cognito_user_pool_domain" "korzinka" {
  # Домен не может содержать "cognito"/"aws"/"amazon" — в var.project есть
  # "cognito", поэтому отдельный префикс, как и в infra-keycloak/cognito.tf
  # соседнего проекта (там та же оговорка).
  domain       = "korzinka-otp-test-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.korzinka.id
}
