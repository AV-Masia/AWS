# ──────────────────────────────────────────────────────────────────────────────
# 4 триггера CUSTOM_AUTH + auto-confirm PreSignUp для phone-OTP флоу Korzinka.
# Без внешних зависимостей (только .mjs), поэтому npm install не нужен —
# archive_file просто зипует папку с исходником.
# ──────────────────────────────────────────────────────────────────────────────

locals {
  triggers = {
    define_auth_challenge     = "define-auth-challenge"
    create_auth_challenge     = "create-auth-challenge"
    verify_auth_challenge     = "verify-auth-challenge-response"
    pre_signup_autoconfirm    = "pre-signup-autoconfirm"
  }
}

data "archive_file" "trigger" {
  for_each = local.triggers

  type        = "zip"
  source_dir  = "${path.module}/../lambda/korzinka-otp/${each.value}"
  output_path = "${path.module}/build/${each.value}.zip"
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

resource "aws_iam_role" "trigger" {
  for_each = local.triggers

  name               = "${var.project}-${each.value}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "trigger_basic" {
  for_each = local.triggers

  role       = aws_iam_role.trigger[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "trigger" {
  for_each = local.triggers

  name              = "/aws/lambda/${var.project}-${each.value}"
  retention_in_days = 7
}

resource "aws_lambda_function" "trigger" {
  for_each = local.triggers

  function_name = "${var.project}-${each.value}"
  role          = aws_iam_role.trigger[each.key].arn
  runtime       = "nodejs22.x"
  handler       = "index.handler"
  architectures = ["arm64"]

  filename         = data.archive_file.trigger[each.key].output_path
  source_code_hash = data.archive_file.trigger[each.key].output_base64sha256

  timeout     = 5
  memory_size = 128

  environment {
    variables = each.key == "create_auth_challenge" ? {
      MOCK_OTP_CODE = var.mock_otp_code
    } : {}
  }

  depends_on = [
    aws_cloudwatch_log_group.trigger,
    aws_iam_role_policy_attachment.trigger_basic,
  ]
}

resource "aws_lambda_permission" "cognito_invoke" {
  for_each = local.triggers

  statement_id   = "AllowCognitoInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.trigger[each.key].function_name
  principal      = "cognito-idp.amazonaws.com"
  source_arn     = aws_cognito_user_pool.korzinka.arn
  source_account = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {}
