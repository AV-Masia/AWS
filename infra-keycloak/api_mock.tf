# --- Собственный API Gateway с JWT-авторайзером на Keycloak ---------------------
#
# Реальный backend (owi2dv5fta.execute-api.eu-north-1.amazonaws.com) живёт в
# чужом AWS-аккаунте и до сих пор валидирует токены против старого Cognito
# User Pool — мы не можем поправить его авторайзер отсюда. Этот стек — свой
# тестовый HTTP API в аккаунте infra-keycloak с JWT authorizer, который
# проверяет issuer/audience/подпись/exp токена Keycloak НА УРОВНЕ ГЕЙТВЕЯ
# (до вызова Lambda) — так подтверждаем, что токен из cognito-otp/verify
# реально принимается ресурс-сервером, защищённым Keycloak JWKS.
#
# Роут: GET /profile -> Lambda-мок (lambda/mock-profile) с данными из claims
# токена, не из реальной БД.

data "archive_file" "mock_profile" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/mock-profile"
  output_path = "${path.module}/lambda/mock-profile.zip"
}

data "archive_file" "keycloak_authorizer" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/keycloak-authorizer"
  output_path = "${path.module}/lambda/keycloak-authorizer.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mock_profile_lambda" {
  name               = "${var.project}-mock-profile-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "mock_profile_lambda_logs" {
  role       = aws_iam_role.mock_profile_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "mock_profile" {
  function_name    = "${var.project}-mock-profile"
  role             = aws_iam_role.mock_profile_lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.mock_profile.output_path
  source_code_hash = data.archive_file.mock_profile.output_base64sha256
  timeout          = 5
}

resource "aws_iam_role" "keycloak_authorizer_lambda" {
  name               = "${var.project}-kc-authorizer-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "keycloak_authorizer_lambda_logs" {
  role       = aws_iam_role.keycloak_authorizer_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Ручная проверка JWT (issuer/audience/exp/подпись по JWKS Keycloak) —
# нативный JWT-authorizer API Gateway требует issuer по HTTPS, а Keycloak
# здесь на голом ALB без домена/сертификата (см. комментарий выше в файле).
resource "aws_lambda_function" "keycloak_authorizer" {
  function_name    = "${var.project}-kc-authorizer"
  role             = aws_iam_role.keycloak_authorizer_lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.keycloak_authorizer.output_path
  source_code_hash = data.archive_file.keycloak_authorizer.output_base64sha256
  timeout          = 5

  environment {
    variables = {
      KEYCLOAK_ISSUER    = "http://${aws_lb.keycloak.dns_name}/realms/${keycloak_realm.korzinka.realm}"
      EXPECTED_AUDIENCE  = keycloak_openid_client.mobile.client_id
    }
  }
}

resource "aws_apigatewayv2_api" "backend" {
  name          = "${var.project}-backend-mock"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "keycloak_jwt" {
  api_id                            = aws_apigatewayv2_api.backend.id
  authorizer_type                   = "REQUEST"
  name                              = "keycloak-jwt"
  authorizer_uri                    = aws_lambda_function.keycloak_authorizer.invoke_arn
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  identity_sources                  = ["$request.header.Authorization"]
}

resource "aws_lambda_permission" "apigw_keycloak_authorizer" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.keycloak_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.backend.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.keycloak_jwt.id}"
}

resource "aws_apigatewayv2_integration" "mock_profile" {
  api_id                 = aws_apigatewayv2_api.backend.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.mock_profile.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_profile" {
  api_id             = aws_apigatewayv2_api.backend.id
  route_key          = "GET /profile"
  target             = "integrations/${aws_apigatewayv2_integration.mock_profile.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.keycloak_jwt.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.backend.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw_mock_profile" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mock_profile.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.backend.execution_arn}/*/*"
}
