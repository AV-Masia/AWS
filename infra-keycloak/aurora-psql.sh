#!/usr/bin/env bash
# Интерактивный psql к Aurora-кластеру Keycloak через IAM DB auth.
#
# Aurora настроена на iam_database_authentication_enabled=true (см. aurora.tf/ecs.tf) —
# статический master_password в Secrets Manager разошёлся с реальным паролем кластера
# (PAM authentication failed), поэтому подключаемся тем же способом, что и ECS-таск
# Keycloak: IAM auth token вместо пароля. Токен живёт 15 минут — генерируется заново
# при каждом запуске этого скрипта, отдельно хранить/кешировать его не нужно.
#
# Требует: docker, aws cli с правами rds-db:connect на этот кластер (arn — см. ecs.tf,
# task_rds_iam_auth policy; учётка terraform-admin их уже имеет).
#
# Использование:
#   ./aurora-psql.sh              # интерактивная psql-сессия
#   ./aurora-psql.sh -c "\dt"     # разовая команда

set -euo pipefail

HOST="database-1.cluster-cx6k8y6gc6ri.eu-central-1.rds.amazonaws.com"
PORT=5432
USER="postgres"
DB="postgres"
REGION="eu-central-1"

TOKEN=$(aws rds generate-db-auth-token --hostname "$HOST" --port "$PORT" --username "$USER" --region "$REGION")

DOCKER_TTY_FLAGS="-i"
if [ -t 0 ] && [ -t 1 ]; then
  DOCKER_TTY_FLAGS="-it"
fi

docker run --rm $DOCKER_TTY_FLAGS \
  -e PGPASSWORD="$TOKEN" \
  postgres:16 psql "host=$HOST port=$PORT user=$USER dbname=$DB sslmode=require" "$@"
