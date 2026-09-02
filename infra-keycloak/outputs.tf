output "keycloak_url" {
  description = "Публичный URL Keycloak (HTTP, без своего домена/сертификата)"
  value       = "http://${aws_lb.keycloak.dns_name}"
}

output "keycloak_admin_secret_name" {
  description = "Имя секрета с логином/паролем первого администратора Keycloak"
  value       = aws_secretsmanager_secret.keycloak_admin.name
}

output "aurora_endpoint" {
  description = "Хост:порт Aurora PostgreSQL для Keycloak"
  value       = "${aws_rds_cluster.keycloak.endpoint}:${aws_rds_cluster.keycloak.port}"
}

output "aurora_secret_name" {
  description = "Имя секрета с кредами Aurora"
  value       = aws_secretsmanager_secret.aurora_db.name
}

output "redis_endpoint" {
  description = "Endpoint ElastiCache Redis (host:port)"
  value       = "${aws_elasticache_cluster.keycloak.cache_nodes[0].address}:${aws_elasticache_cluster.keycloak.cache_nodes[0].port}"
}

# --- Korzinka test-migration realm -------------------------------------------------

output "keycloak_realm_issuer" {
  description = "OIDC issuer тестового реалма Korzinka — использовать как issuer в API Gateway JWT authorizer и в KeycloakAuthService (Flutter)"
  value       = "http://${aws_lb.keycloak.dns_name}/realms/${keycloak_realm.korzinka.realm}"
}

output "keycloak_mobile_client_id" {
  description = "client_id публичного мобильного клиента Korzinka в Keycloak"
  value       = keycloak_openid_client.mobile.client_id
}

output "keycloak_admin_cli_client_id" {
  description = "client_id тестового service-account клиента для provisioning OTP-пользователей (см. предупреждение в realm.tf — только для теста)"
  value       = keycloak_openid_client.admin_cli.client_id
}

output "keycloak_admin_cli_client_secret" {
  description = "client_secret тестового service-account клиента — только для теста, не должен попадать в прод-билд"
  value       = keycloak_openid_client.admin_cli.client_secret
  sensitive   = true
}

# --- Собственный мок-backend с JWT-авторайзером на Keycloak (api_mock.tf) --------

output "mock_backend_url" {
  description = "Базовый URL собственного тестового API Gateway (GET /profile), защищённого JWT-авторайзером на Keycloak"
  value       = aws_apigatewayv2_api.backend.api_endpoint
}
