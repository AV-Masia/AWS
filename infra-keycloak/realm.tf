# ──────────────────────────────────────────────────────────────────────────────
# Реалм для авторизации Korzinka на Keycloak (см. korzinka/).
# ──────────────────────────────────────────────────────────────────────────────

resource "keycloak_realm" "korzinka" {
  realm   = var.korzinka_realm_name
  enabled = true

  # Демо-стенд по HTTP без своего домена/ACM — как и весь остальной Keycloak-стенд.
  ssl_required = "none"

  registration_allowed = false
}

# По умолчанию Keycloak (декларативный User Profile) требует email/firstName/
# lastName для роли "user". Найдено на реальном тесте ROPC-логина: provisioning
# тестового OTP-пользователя (см. korzinka/lib/services/auth_service.dart,
# _ensureKeycloakTestUser) заполняет только username=телефон — без этих полей
# ROPC падает с "invalid_grant: Account is not fully set up". Вход у Korzinka
# только по телефону/Google, email и имя на этом этапе не собираются — поэтому
# снимаем required с email/firstName/lastName, а не подсовываем фиктивные
# значения из мобильного кода.
resource "keycloak_realm_user_profile" "korzinka" {
  realm_id = keycloak_realm.korzinka.id

  # Без этого Keycloak молча отбрасывает любые атрибуты, не объявленные ниже явно
  # (attributes блоков) — в том числе phone_number, которые мобильное приложение
  # проставляет через API. С "ENABLED" произвольные атрибуты сохраняются,
  # не будучи объявленными по отдельности.
  unmanaged_attribute_policy = "ENABLED"

  attribute {
    name         = "username"
    display_name = "$${username}"

    permissions {
      view = ["admin", "user"]
      edit = ["admin", "user"]
    }
  }

  attribute {
    name         = "email"
    display_name = "$${email}"

    permissions {
      view = ["admin", "user"]
      edit = ["admin", "user"]
    }

    validator {
      name = "email"
    }
  }

  attribute {
    name         = "firstName"
    display_name = "$${firstName}"

    permissions {
      view = ["admin", "user"]
      edit = ["admin", "user"]
    }
  }

  attribute {
    name         = "lastName"
    display_name = "$${lastName}"

    permissions {
      view = ["admin", "user"]
      edit = ["admin", "user"]
    }
  }
}

# Публичный клиент мобильного приложения. standard_flow — для Google-брокера
# (authorization code + PKCE), direct_access_grants —
# для OTP-логина (ROPC, см. korzinka/lib/services/keycloak_auth_service.dart).
resource "keycloak_openid_client" "mobile" {
  realm_id  = keycloak_realm.korzinka.id
  client_id = "korzinka-mobile"
  name      = "Korzinka Mobile (test)"

  access_type = "PUBLIC"

  standard_flow_enabled        = true
  direct_access_grants_enabled = true
  service_accounts_enabled     = false

  valid_redirect_uris = [var.korzinka_mobile_redirect_uri]
  web_origins         = ["+"]
}

# Кастомный флоу первого входа через брокера: автоматически связывает
# Google-аккаунт с существующим пользователем по совпадению email (trust_email = true)
# БЕЗ запроса пароля Keycloak (т.к. у пользователей нет пароля в Keycloak).
resource "keycloak_authentication_flow" "first_broker_login_auto_link" {
  realm_id = keycloak_realm.korzinka.id
  alias    = "first broker login auto link"
}

resource "keycloak_authentication_execution" "detect_existing_user" {
  realm_id          = keycloak_realm.korzinka.id
  parent_flow_alias = keycloak_authentication_flow.first_broker_login_auto_link.alias
  authenticator     = "idp-detect-existing-broker-user"
  requirement       = "REQUIRED"
}

resource "keycloak_authentication_execution" "auto_link" {
  realm_id          = keycloak_realm.korzinka.id
  parent_flow_alias = keycloak_authentication_flow.first_broker_login_auto_link.alias
  authenticator     = "idp-auto-link"
  requirement       = "REQUIRED"
  depends_on        = [keycloak_authentication_execution.detect_existing_user]
}

# Google identity provider broker — обеспечивает вход через Google.
# client_id/secret — проект Google Cloud, значения только
# через terraform.tfvars (не коммитить).
resource "keycloak_oidc_google_identity_provider" "google" {
  realm                        = keycloak_realm.korzinka.id
  client_id                    = var.google_idp_client_id
  client_secret                = var.google_idp_client_secret
  trust_email                  = true
  first_broker_login_flow_alias = keycloak_authentication_flow.first_broker_login_auto_link.alias
}

# ──────────────────────────────────────────────────────────────────────────────
# ТОЛЬКО ДЛЯ ТЕСТА. Service-account клиент с правом manage-users — мобильное
# приложение использует его, чтобы на лету завести пользователя по номеру
# телефона перед мокнутым ROPC-логином (в Keycloak нет встроенного SMS OTP).
# В проде креды этого клиента НЕ должны попадать в мобильный билд — реальная
# аутентификация использует встроенный OTP SPI эндпоинт.
# ──────────────────────────────────────────────────────────────────────────────
resource "keycloak_openid_client" "admin_cli" {
  realm_id  = keycloak_realm.korzinka.id
  client_id = "korzinka-admin-cli-TEST-ONLY"
  name      = "Korzinka test OTP provisioning (INSECURE — test only)"

  access_type               = "CONFIDENTIAL"
  service_accounts_enabled  = true
  standard_flow_enabled     = false
  direct_access_grants_enabled = false
}

# manage-users — встроенная роль клиента realm-management (не admin_cli), его
# и запрашиваем ролью service-account'а.
data "keycloak_openid_client" "realm_management" {
  realm_id  = keycloak_realm.korzinka.id
  client_id = "realm-management"
}

data "keycloak_role" "realm_manage_users" {
  realm_id  = keycloak_realm.korzinka.id
  client_id = data.keycloak_openid_client.realm_management.id
  name      = "manage-users"
}

resource "keycloak_openid_client_service_account_role" "admin_cli_manage_users" {
  realm_id                = keycloak_realm.korzinka.id
  service_account_user_id = keycloak_openid_client.admin_cli.service_account_user_id
  client_id                = data.keycloak_openid_client.realm_management.id
  role                     = data.keycloak_role.realm_manage_users.name
}

# ──────────────────────────────────────────────────────────────────────────────
# Провайдер создания пользователей по номеру телефона (см.
# docker/korzinka-auth-provider/). Провижининг пользователя делает сам
# Keycloak при первом ROPC-логине или OTP-запросе по неизвестному номеру.
# ──────────────────────────────────────────────────────────────────────────────
resource "keycloak_custom_user_federation" "korzinka_phone_storage" {
  name        = "korzinka-phone-storage"
  realm_id    = keycloak_realm.korzinka.id
  provider_id = "korzinka-phone-storage"
  enabled     = true
  priority    = 0
}


