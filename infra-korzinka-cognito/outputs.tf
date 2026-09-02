output "user_pool_id" {
  description = "ID тестового эталонного пула Korzinka (phone + Google)"
  value       = aws_cognito_user_pool.korzinka.id
}

output "user_pool_client_id" {
  description = "client_id мобильного публичного клиента — идёт в конфиг приложения (AuthConfig.cognitoClientId, если тестируем provider=cognito)"
  value       = aws_cognito_user_pool_client.mobile.id
}

output "hosted_ui_domain" {
  description = "Домен Hosted UI для Google-логина (аналог AuthConfig.cognitoDomain)"
  value       = "https://${aws_cognito_user_pool_domain.korzinka.domain}.auth.${var.region}.amazoncognito.com"
}

output "lambda_function_names" {
  description = "Имена триггеров CUSTOM_AUTH — для aws lambda invoke / aws logs tail при отладке"
  value       = { for k, v in local.triggers : k => aws_lambda_function.trigger[k].function_name }
}
