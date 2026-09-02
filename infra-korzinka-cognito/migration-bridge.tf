# ──────────────────────────────────────────────────────────────────────────────
# Мост миграции Korzinka Cognito -> Keycloak, критерий переноса — номер
# телефона (см. korzinka/docs/keycloak-migration/MIGRATION.md, решение от
# 2026-09-01). Эта Lambda — единственная часть моста с прямым доступом к
# Cognito; Keycloak-провижининг в мобильном приложении дергает её перед
# созданием нового пользователя, чтобы узнать legacy sub по номеру телефона.
#
# ТЕСТОВЫЙ СТЕНД: Function URL публичный, авторизация — shared secret в
# заголовке (см. LOOKUP_SHARED_SECRET). Для прода это должно быть за
# настоящим backend, а не за URL с секретом внутри мобильного билда — тот же
# класс риска, что и у admin_cli provisioning (см. realm.tf в infra-keycloak).
# ──────────────────────────────────────────────────────────────────────────────

resource "random_password" "lookup_shared_secret" {
  length  = 32
  special = false
}

data "archive_file" "cognito_lookup_by_phone" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/korzinka-otp/cognito-lookup-by-phone"
  output_path = "${path.module}/build/cognito-lookup-by-phone.zip"
}

resource "aws_iam_role" "cognito_lookup_by_phone" {
  name               = "${var.project}-cognito-lookup-by-phone"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "cognito_lookup_by_phone_basic" {
  role       = aws_iam_role.cognito_lookup_by_phone.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Единственное дополнительное право: только ListUsers, только на этот
# конкретный (тестовый/legacy) пул — не "cognito-idp:*", не Resource = "*".
data "aws_iam_policy_document" "cognito_lookup_by_phone" {
  statement {
    sid       = "ListUsersInLegacyPool"
    actions   = ["cognito-idp:ListUsers"]
    resources = [aws_cognito_user_pool.korzinka.arn]
  }
}

resource "aws_iam_role_policy" "cognito_lookup_by_phone" {
  name   = "list-users-legacy-pool"
  role   = aws_iam_role.cognito_lookup_by_phone.id
  policy = data.aws_iam_policy_document.cognito_lookup_by_phone.json
}

resource "aws_cloudwatch_log_group" "cognito_lookup_by_phone" {
  name              = "/aws/lambda/${var.project}-cognito-lookup-by-phone"
  retention_in_days = 7
}

resource "aws_lambda_function" "cognito_lookup_by_phone" {
  function_name = "${var.project}-cognito-lookup-by-phone"
  role          = aws_iam_role.cognito_lookup_by_phone.arn
  runtime       = "nodejs22.x"
  handler       = "index.handler"
  architectures = ["arm64"]

  filename         = data.archive_file.cognito_lookup_by_phone.output_path
  source_code_hash = data.archive_file.cognito_lookup_by_phone.output_base64sha256

  timeout     = 5
  memory_size = 128

  environment {
    variables = {
      # ВРЕМЕННО: указывает на наш тестовый пул (эталон), а не на прод
      # Korzinka (недоступен нам напрямую). При реальной миграции — заменить.
      LEGACY_USER_POOL_ID  = aws_cognito_user_pool.korzinka.id
      LOOKUP_SHARED_SECRET = random_password.lookup_shared_secret.result
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.cognito_lookup_by_phone,
    aws_iam_role_policy_attachment.cognito_lookup_by_phone_basic,
    aws_iam_role_policy.cognito_lookup_by_phone,
  ]
}

resource "aws_lambda_function_url" "cognito_lookup_by_phone" {
  function_name      = aws_lambda_function.cognito_lookup_by_phone.function_name
  authorization_type = "NONE"
}

output "migration_bridge_lookup_url" {
  description = "Function URL моста миграции (поиск по номеру телефона в legacy Cognito)"
  value       = aws_lambda_function_url.cognito_lookup_by_phone.function_url
}

output "migration_bridge_lookup_secret" {
  description = "Shared secret для заголовка X-Lookup-Secret — ТОЛЬКО для теста"
  value       = random_password.lookup_shared_secret.result
  sensitive   = true
}
