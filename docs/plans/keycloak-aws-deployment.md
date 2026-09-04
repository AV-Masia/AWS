# Keycloak на AWS + Aurora PostgreSQL + ElastiCache Redis

## Что нужно сделать

Развернуть Keycloak в AWS, подключить его к Aurora (PostgreSQL-совместимая, вместо БД
внутри контейнера) и к кэшу (ElastiCache Redis). Код — в `infra-keycloak/`.


## Архитектура

```
Интернет → ALB (:80) → ECS Fargate task (Keycloak, :8080/:9000)
                              │              │
                              │              └── Aurora PostgreSQL Serverless v2 (:5432)
                              └── ElastiCache Redis (:6379)
```

- **Compute:** ECS Fargate, 1 задача (`desired_count = 1`), без своего EC2 — меньше
  забот с патчингом хоста.
- **БД:** Aurora PostgreSQL Serverless v2, `min_capacity = 0.5 ACU`, `max_capacity = 2 ACU`.
  Дешевле фиксированного `db.t4g.micro`, когда стенд простаивает.
- **Кэш:** ElastiCache Redis, одна нода `cache.t4g.micro`, без реплики.
- **Секреты:** пароль Aurora и пароль первого админа Keycloak генерируются Terraform'ом
  и лежат в Secrets Manager; ECS execution role читает их при старте задачи
  (`secrets`, а не `environment`, в task definition — в логи и `describe-task` они не попадают).
- **Сеть:** default VPC, как и в `infra/` — не поднимаем свою, чтобы не решать про route
  tables/IGW. ALB и Keycloak-таска в публичных подсетях (демо, без NAT), Aurora и Redis
  закрыты security group на доступ только от Keycloak-таски.
- **TLS:** сознательно не подключён — ALB слушает только `:80`. Для домена и
  ACM-сертификата нужен Route 53 hosted zone, которой в задаче нет.

## ⚠️ Про Redis и Keycloak — важная оговорка

Keycloak **не использует Redis** для кэша сессий/аутентификации «из коробки» — у него
свой встроенный кэш на Infinispan (embedded, внутри JVM). Подключить внешний Redis вместо
Infinispan можно только через кастомный SPI-провайдер (community-проекты вроде
`keycloak-redis-cache`), которого в этом задании нет и который надо отдельно писать и
поддерживать.

Поэтому ElastiCache здесь поднят **как отдельный, независимый от Keycloak кэш общего
назначения** — на случай если он нужен приложениям, которые сидят за Keycloak (rate-limit,
кэш профилей и т.п.). Его endpoint пробрасывается в контейнер переменными `REDIS_HOST` /
`REDIS_PORT`, но сам Keycloak их не читает.

Если бизнес-требование — именно «Keycloak должен кэшировать в Redis», это отдельная
задача с написанием/интеграцией SPI-провайдера — дайте знать, распишу отдельно.

## Как поднять

Нужны `terraform` и `aws configure` с рабочими ключами (на этой машине оба сейчас не
установлены — `terraform -version` и `aws --version` вернули `CommandNotFoundException`).

```
cd infra-keycloak
terraform init
terraform apply
```

После apply:

```
terraform output keycloak_url                 # открыть в браузере
terraform output keycloak_admin_secret_name   # aws secretsmanager get-secret-value --secret-id <имя>
```

Первый вход — по логину/паролю из секрета `keycloak-aws/keycloak-admin`.

## Стоимость (ориентир, eu-central-1)

| Ресурс | Простаивает (0.5 ACU, 1 нода) | Замечание |
|---|---|---|
| Aurora Serverless v2 | ~$0,07/ч (0.5 ACU × $0,145) | + storage, копейки на демо-объёме |
| ElastiCache `cache.t4g.micro` | ~$0,016/ч | |
| ECS Fargate (0.5 vCPU / 1 GB) | ~$0,02/ч | |
| ALB | ~$0,025/ч + LCU | |
| **Итого** | **~$0,13/ч** (~$3/сутки) | Погасить: `terraform destroy` |

## Критерии приёмки

- [ ] `terraform apply` в `infra-keycloak/` проходит без ошибок
- [ ] `keycloak_url` открывается, форма логина в админ-консоль доступна
- [ ] Вход под учёткой из `keycloak-admin` секрета работает
- [ ] В логах Keycloak (`aws logs tail /ecs/keycloak-aws --follow`) виден успешный коннект к Aurora
- [ ] Redis-эндпоинт создан и security group пускает к нему только Keycloak-таску
- [ ] `terraform destroy` гасит всё до нуля

## Открытые вопросы к заказчику

1. Нужен ли HTTPS/свой домен (Route 53 + ACM), или демо по HTTP через ALB DNS достаточно?
2. Нужна ли реальная интеграция Keycloak с Redis (кастомный SPI), или Redis — для сторонних
   сервисов рядом с Keycloak?
3. Realm/клиенты создавать заранее через `terraform`/`keycloak_realm` (провайдер
   `mrparkers/keycloak`), или руками через админ-консоль после первого старта?
