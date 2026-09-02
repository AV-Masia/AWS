# ВАЖНО: сам Keycloak кэш сессий/аутентификации хранит во встроенном Infinispan,
# а не в Redis, и «из коробки» подключить Redis как замену Infinispan нельзя —
# это потребовало бы кастомный SPI-провайдер (в задании его нет, code вести некому).
# ElastiCache здесь поднят как отдельный кэш общего назначения — для приложений,
# которые сидят за Keycloak и хотят внешний Redis (rate-limit, кэш профилей и т.п.).
# Одна нода без реплики — дешевле всего для демо.
resource "aws_elasticache_subnet_group" "keycloak" {
  name       = "${var.project}-redis"
  subnet_ids = local.subnet_ids
}

resource "aws_elasticache_cluster" "keycloak" {
  cluster_id           = "${var.project}-redis"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.keycloak.name
  security_group_ids   = [aws_security_group.redis.id]
  apply_immediately    = true
}
