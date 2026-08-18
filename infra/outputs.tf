output "db_endpoint" {
  description = "Хост:порт legacy PostgreSQL"
  value       = "${aws_db_instance.legacy.address}:${aws_db_instance.legacy.port}"
}

output "secret_arn" {
  description = "ARN секрета с кредами legacy-БД — его читают и Lambda, и скрипт сева"
  value       = aws_secretsmanager_secret.legacy_db.arn
}

output "secret_name" {
  description = "Имя секрета для aws secretsmanager get-secret-value"
  value       = aws_secretsmanager_secret.legacy_db.name
}

output "lambda_subnet_ids" {
  description = "Подсети, в которых работают Lambda и interface endpoint"
  value       = local.lambda_subnet_ids
}

output "lambda_security_group_id" {
  description = "Security group для Lambda в VPC"
  value       = aws_security_group.lambda.id
}

output "user_pool_id" {
  description = "ID нового пула — идёт в конфиг фронтенда"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  description = "ID публичного app client — идёт в конфиг фронтенда"
  value       = aws_cognito_user_pool_client.web.id
}

output "managed_login_domain" {
  description = "Домен страницы входа Cognito на новом пуле"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
}

output "lambda_function_names" {
  description = "Имена функций — для aws lambda invoke и aws logs tail"
  value = {
    user_migration = aws_lambda_function.user_migration.function_name
    pre_signup     = aws_lambda_function.pre_signup.function_name
  }
}
