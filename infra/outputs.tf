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

