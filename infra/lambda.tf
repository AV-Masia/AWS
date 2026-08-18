# ──────────────────────────────────────────────────────────────────────────────
# Сборка пакетов
# Зависимости ставятся до terraform apply: npm install --omit=dev в каждой папке.
# Хэш архива попадает в source_code_hash, поэтому правка кода приводит к обновлению
# функции, а неизменный код не даёт лишнего diff в plan.
# ──────────────────────────────────────────────────────────────────────────────
data "archive_file" "user_migration" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/user-migration"
  output_path = "${path.module}/build/user-migration.zip"
}

data "archive_file" "pre_signup" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/pre-signup"
  output_path = "${path.module}/build/pre-signup.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# user-migration: в VPC, с доступом к секрету
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "user_migration" {
  name               = "${var.project}-user-migration"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Права на создание ENI в VPC + запись логов
resource "aws_iam_role_policy_attachment" "user_migration_vpc" {
  role       = aws_iam_role.user_migration.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Единственное дополнительное право: прочитать один конкретный секрет.
# Ни "secretsmanager:*", ни Resource = "*" — принцип наименьших привилегий.
data "aws_iam_policy_document" "read_legacy_secret" {
  statement {
    sid       = "ReadLegacyDbSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.legacy_db.arn]
  }
}

resource "aws_iam_role_policy" "user_migration_secret" {
  name   = "read-legacy-db-secret"
  role   = aws_iam_role.user_migration.id
  policy = data.aws_iam_policy_document.read_legacy_secret.json
}

# Лог-группу создаём сами: иначе её создаст Lambda со сроком хранения "навсегда"
resource "aws_cloudwatch_log_group" "user_migration" {
  name              = "/aws/lambda/${var.project}-user-migration"
  retention_in_days = 7
}

resource "aws_lambda_function" "user_migration" {
  function_name = "${var.project}-user-migration"
  role          = aws_iam_role.user_migration.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  architectures = ["arm64"]

  filename         = data.archive_file.user_migration.output_path
  source_code_hash = data.archive_file.user_migration.output_base64sha256

  # Cognito всё равно ждёт ответ не дольше 5 секунд — брать больше смысла нет.
  # Память щедрая не ради памяти, а ради CPU: от неё зависит скорость bcrypt.
  timeout     = 5
  memory_size = 1024

  vpc_config {
    subnet_ids         = local.lambda_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      LEGACY_DB_SECRET        = aws_secretsmanager_secret.legacy_db.name
      POWERTOOLS_SERVICE_NAME = "user-migration"
      POWERTOOLS_LOG_LEVEL    = "INFO"
    }
  }

  # Без этого START/END/REPORT остаются текстовыми строками, и «все логи — JSON»
  # перестаёт быть правдой
  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }

  depends_on = [
    aws_cloudwatch_log_group.user_migration,
    aws_iam_role_policy_attachment.user_migration_vpc,
    aws_iam_role_policy.user_migration_secret,
  ]
}

# ──────────────────────────────────────────────────────────────────────────────
# pre-signup: вне VPC, без доступа к секретам и базе — ей нужны только метаданные
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "pre_signup" {
  name               = "${var.project}-pre-signup"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "pre_signup_basic" {
  role       = aws_iam_role.pre_signup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "pre_signup" {
  name              = "/aws/lambda/${var.project}-pre-signup"
  retention_in_days = 7
}

resource "aws_lambda_function" "pre_signup" {
  function_name = "${var.project}-pre-signup"
  role          = aws_iam_role.pre_signup.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  architectures = ["arm64"]

  filename         = data.archive_file.pre_signup.output_path
  source_code_hash = data.archive_file.pre_signup.output_base64sha256

  timeout     = 5
  memory_size = 256

  environment {
    variables = {
      POWERTOOLS_SERVICE_NAME = "pre-signup"
      POWERTOOLS_LOG_LEVEL    = "INFO"
    }
  }

  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }

  depends_on = [
    aws_cloudwatch_log_group.pre_signup,
    aws_iam_role_policy_attachment.pre_signup_basic,
  ]
}
