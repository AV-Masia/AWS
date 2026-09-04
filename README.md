# Korzinka Auth Infrastructure (Keycloak on AWS)

Репозиторий инфраструктуры аутентификации для мобильного приложения Korzinka на базе **Keycloak 26**, развёрнутого в AWS.

---

## Архитектура

- **Keycloak 26 on AWS ECS Fargate** (`infra-keycloak/`):
  - Кластер ECS Fargate за Application Load Balancer (ALB).
  - База данных: Amazon Aurora PostgreSQL (Serverless v2 / Provisioned) с IAM Database Authentication через AWS JDBC Driver Wrapper.
  - Кэширование и сессии: Amazon ElastiCache Redis.
  - Секреты: AWS Secrets Manager.
- **Custom Keycloak SPI** (`infra-keycloak/docker/korzinka-auth-provider/`):
  - **`KorzinkaUserStorageProvider`**: автономный провайдер создания пользователей по номеру телефона в Keycloak.
  - **`KorzinkaOtpResourceProvider`**: кастомный REST-провайдер для OTP-аутентификации:
    - `POST /realms/{realm}/otp/send` — генерация и отправка OTP.
    - `POST /realms/{realm}/otp/verify` — валидация OTP и выпуск токенов (ROPC).
- **API Gateway Mock & Authorizer** (`infra-keycloak/lambda/`):
  - `keycloak-authorizer`: Lambda JWT-авторайзер для проверки токенов Keycloak по JWKS.
  - `mock-profile`: Lambda-мок сервиса профиля пользователя.

---

## Структура репозитория

```
.
├── infra-keycloak/               # Terraform-манифесты Keycloak на AWS ECS/Aurora/Redis/ALB
│   ├── docker/
│   │   ├── korzinka-auth-provider/ # Java Keycloak SPI (User Storage & OTP Resource Providers)
│   │   ├── dev/                  # Локальные скрипты настройки realm (bootstrap-realm.sh)
│   │   ├── Dockerfile            # Multi-stage сборка кастомного Keycloak с SPI и AWS JDBC
│   │   └── docker-compose.dev.yml # Локальный стенд разработки Keycloak + Postgres
│   ├── lambda/                   # Lambda-функции JWT-авторайзера и мока профиля
│   ├── realm.tf                  # Конфигурация Realm, клиентов и Identity Providers
│   ├── ecs.tf                    # ECS Task Definition и Service
│   ├── aurora.tf                 # Aurora PostgreSQL
│   ├── redis.tf                  # ElastiCache Redis
│   └── api_mock.tf               # Тестовый API Gateway с JWT-авторайзером
└── scripts/                      # Вспомогательные скрипты
```

---

## Локальная разработка

Для локального запуска Keycloak:

```bash
cd infra-keycloak/docker
docker compose -f docker-compose.dev.yml up --build -d
./dev/bootstrap-realm.sh
```

После старта Keycloak доступен по адресу `http://localhost:18080`.
