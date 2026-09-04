#!/usr/bin/env bash
set -euo pipefail

# Разворачивает realm korzinka-test в локальном docker-compose Keycloak
# (docker-compose.dev.yml) для проверки SPI korzinka-auth-provider без
# rebuild+push+deploy на ECS.

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

# Снимаем required с email/firstName/lastName и включаем unmanaged-атрибуты
docker cp "$SCRIPT_DIR/user-profile.json" "$KC_CONTAINER":/tmp/user-profile.json
kcadm update users/profile -r korzinka-test -f //tmp/user-profile.json

kcadm create components -r korzinka-test \
  -s name=korzinka-phone-storage \
  -s providerId=korzinka-phone-storage \
  -s providerType=org.keycloak.storage.UserStorageProvider

kcadm create clients -r korzinka-test \
  -s clientId=korzinka-mobile \
  -s publicClient=true \
  -s standardFlowEnabled=true \
  -s directAccessGrantsEnabled=true \
  -s 'redirectUris=["myapp://callback"]'

cat <<EOF

Realm korzinka-test готов на http://localhost:18080.

Проверка ROPC-логина:
  curl -s http://localhost:18080/realms/korzinka-test/protocol/openid-connect/token \\
    -d grant_type=password -d client_id=korzinka-mobile \\
    -d username=+998911112222 -d password=$MOCK_OTP_CODE | jq

  curl -s http://localhost:18080/realms/korzinka-test/protocol/openid-connect/token \\
    -d grant_type=password -d client_id=korzinka-mobile \\
    -d username=+15550009999 -d password=$MOCK_OTP_CODE | jq

Проверить созданного пользователя:
  kcadm get users -r korzinka-test -q username=+998911112222
EOF

