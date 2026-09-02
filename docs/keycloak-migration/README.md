# Korzinka: миграция Cognito → Keycloak — рабочая папка

Здесь собраны заметки/статус по использованию dev-ресурсов этого AWS-репо
для миграции мобильного приложения Korzinka (отдельный репозиторий) с
Cognito на Keycloak. Подробный журнал изменений и обоснований — в самом
репозитории Korzinka: `docs/keycloak-migration/CHANGELOG.md` и
`docs/keycloak-migration/MIGRATION.md`.

Живые Terraform-стенды **не переносились** в эту папку — `infra/` и
`infra-keycloak/` остаются на месте, т.к. их `.tfstate` и относительные
пути (`../lambda/...`) привязаны к текущему расположению; перенос без
`terraform state mv`/переинициализации мог бы рассинхронить state с
реальными AWS-ресурсами. Эта папка — только для доков/трекинга статуса
использования ресурсов под миграцию.

## Что используется для dev/тестирования миграции

| Стенд | Расположение | Роль в миграции Korzinka | Статус |
|---|---|---|---|
| Keycloak (ECS/Aurora/Redis) + realm `korzinka-test` | `AWS/infra-keycloak` | Целевая система — тестируем ROPC/OTP-мок и (позже) Google-логин через неё | Применено, realm живой, Google IdP — плейсхолдер-креды |
| Cognito `cognito-legacy-migration` (email/password + legacy RDS migration) | `AWS/infra` | **Не аналог прод-пула Korzinka** (другой флоу входа, без Google IdP) — пересоздан по просьбе пользователя как учебный/тестовый Cognito-пул под собственными кредами, т.к. доступа к прод-пулу Korzinka нет | Пересоздан 2026-09-01, `user_pool_id = eu-central-1_cWjuqTwVy` |
| Прод Cognito Korzinka (`eu-north-1_g0gApsbuG`) | вне этого репозитория | Эталон поведения — недоступен, работаем по докам Korzinka (`docs/auth/auth.md` и т.д.) | Недоступен |

## Открытый вопрос

`cognito-legacy-migration` пул не воспроизводит phone+Google флоу Korzinka
(другой username attribute, нет Google broker). Если для параллельного
сравнения с Cognito понадобится именно phone+Google-пул — это отдельная
задача (новый Terraform под Korzinka-специфичный пул), ещё не начата.
