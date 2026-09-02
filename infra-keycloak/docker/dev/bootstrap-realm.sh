#!/usr/bin/env bash
set -euo pipefail

# Разворачивает realm korzinka-test в локальном docker-compose Keycloak
# (docker-compose.dev.yml) для проверки SPI cognito-migration-federation без
# rebuild+push+deploy на ECS. См. korzinka/docs/keycloak-migration/MIGRATION.md.
#
# COGNITO_LOOKUP_URL/COGNITO_LOOKUP_SECRET — значения из
# `terraform output migration_bridge_lookup_url/migration_bridge_lookup_secret`
# в AWS/infra-korzinka-cognito (реальная, уже задеплоенная Lambda).

: "${COGNITO_LOOKUP_URL:?set to migration_bridge_lookup_url terraform output}"
: "${COGNITO_LOOKUP_SECRET:?set to migration_bridge_lookup_secret terraform output}"
MOCK_OTP_CODE="${MOCK_OTP_CODE:-123456}"
KC_CONTAINER="${KC_CONTAINER:-docker-keycloak-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kcadm() {
  # Двойной слеш — чтобы Git Bash на Windows не конвертировал этот путь в
  # C:\... (он всё равно предназначен для контейнера, не для хоста).
  docker exec "$KC_CONTAINER" //opt/keycloak/bin/kcadm.sh "$@"
}

kcadm config credentials --server http://localhost:8080 --realm master --user admin --password admin

kcadm create realms -s realm=korzinka-test -s enabled=true -s sslRequired=NONE -s registrationAllowed=false

# Снимаем required с email/firstName/lastName и включаем unmanaged-атрибуты —
# без этого Admin API молча отбрасывает phone_number/legacy_cognito_sub (см.
# CHANGELOG.md, "Мост миграции по номеру телефона" — тот же баг, что уже
# нашли на реальном ECS-стенде, здесь фиксируем сразу).
docker cp "$SCRIPT_DIR/user-profile.json" "$KC_CONTAINER":/tmp/user-profile.json
kcadm update users/profile -r korzinka-test -f //tmp/user-profile.json

kcadm create components -r korzinka-test \
  -s name=cognito-migration-federation \
  -s providerId=cognito-migration-federation \
  -s providerType=org.keycloak.storage.UserStorageProvider \
  -s 'config.lookupUrl=["'"$COGNITO_LOOKUP_URL"'"]' \
  -s 'config.lookupSecret=["'"$COGNITO_LOOKUP_SECRET"'"]' \
  -s 'config.mockOtpCode=["'"$MOCK_OTP_CODE"'"]'

kcadm create clients -r korzinka-test \
  -s clientId=korzinka-mobile \
  -s publicClient=true \
  -s standardFlowEnabled=true \
  -s directAccessGrantsEnabled=true \
  -s 'redirectUris=["myapp://callback"]'

cat <<EOF

Realm korzinka-test готов на http://localhost:18080.

Известный мигрант (см. CHANGELOG.md, есть в тестовом Cognito-пуле):
  curl -s http://localhost:18080/realms/korzinka-test/protocol/openid-connect/token \\
    -d grant_type=password -d client_id=korzinka-mobile \\
    -d username=+998911112222 -d password=$MOCK_OTP_CODE | jq

Новый номер (нет ни в Keycloak, ни в Cognito):
  curl -s http://localhost:18080/realms/korzinka-test/protocol/openid-connect/token \\
    -d grant_type=password -d client_id=korzinka-mobile \\
    -d username=+15550009999 -d password=$MOCK_OTP_CODE | jq

Проверить legacy_cognito_sub у созданного пользователя:
  kcadm get users -r korzinka-test -q username=+998911112222
EOF
