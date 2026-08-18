# AWS Cognito: два тестовых задания

**Задание 1** (ниже) — поднять в AWS cloud-native identity provider, выбрать самый
распространённый тип аутентификации, прикрутить его к минимальному приложению
и ответить, можно ли это бесплатно.

**Задание 2** ([перейти к разделу](#задание-2-миграция-без-сброса-паролей-и-honeypot-вместо-капчи)) —
бесшовная миграция 100k пользователей из старой PostgreSQL без сброса паролей, антибот-защита
формы регистрации без капчи и Zero-Trust логирование. Всё в Terraform, без консоли.

Живое демо обоих заданий: **https://av-masia.github.io/AWS/** — переключается вкладками.

---

## Задание 1: логин через Cognito

**Результат:** React-приложение на `localhost:5173` с логином через **Amazon Cognito User Pool**
по протоколу **OIDC Authorization Code + PKCE**. Регистрация по email с подтверждением кодом
из письма, вход, отображение claims из ID-токена, выход — всё проверено сквозняком.
Стоимость — **$0**.

---

## Что поднято в AWS

| Ресурс | Значение |
|---|---|
| Регион | `eu-central-1` (Frankfurt) |
| User Pool ID | `eu-central-1_QTI9GPqq3` |
| App client ID | `5ejvgg30eac9icrkis1l0q4s0r` (public client, без секрета) |
| Домен страницы входа | `https://eu-central-1qti9gpqq3.auth.eu-central-1.amazoncognito.com` |
| Callback / sign-out URL | `https://av-masia.github.io/AWS/` и `http://localhost:5173` |
| Scopes | `openid`, `email` |

Ресурсы созданы через консоль AWS, мастером `Create user pool → Define your application →
Single-page application (SPA)`. Он сразу создаёт публичного клиента без секрета с grant type
`Authorization code` и домен для страницы входа.

## Как это работает

```
Браузер (localhost:5173)          Cognito                        Почта
        │                            │                             │
        │ 1. «Войти»                 │                             │
        ├───────────────────────────>│                             │
        │   /oauth2/authorize        │                             │
        │                            │  2. форма входа Cognito     │
        │                            │     (регистрация → код)     │
        │                            ├────────────────────────────>│
        │                            │                             │
        │ 3. возврат с ?code=...     │                             │
        │<───────────────────────────┤                             │
        │                            │                             │
        │ 4. code + verifier → токены│                             │
        ├───────────────────────────>│                             │
        │   /oauth2/token            │                             │
        │<───────────────────────────┤                             │
        │   id_token, access_token, refresh_token                  │
```

Ключевое: **пароль вводится на домене Cognito, а не в нашем приложении**. Приложение пароля
не видит никогда — оно получает только подписанный токен. Это и есть смысл вынесения
аутентификации в IDP.

PKCE (шаг 4) защищает от перехвата кода: приложение заранее генерирует случайный `verifier`,
отправляет в Cognito его хэш, а при обмене кода на токены предъявляет оригинал. Перехваченный
код без `verifier` бесполезен. Для SPA это обязательная практика, потому что секрет клиента
в браузере спрятать физически негде.

## Как запустить

```bash
cd web
npm install
cp .env.example .env.local   # заполнить значениями из таблицы выше
npm run dev                  # http://localhost:5173
```

`.env.local` в `.gitignore`. Секретов в нём нет — `client_id` и домен по своей природе публичны,
они видны в адресной строке при входе, — но привязка к конкретному аккаунту AWS в репозитории
лишняя.

Vite читает переменные окружения только при старте: после правки `.env.local` нужен рестарт
dev-сервера.

Структура:

- [`web/src/authConfig.ts`](web/src/authConfig.ts) — конфиг OIDC, разлогин, проверка заполненности env
- [`web/src/App.tsx`](web/src/App.tsx) — кнопки входа/выхода, защищённый экран, вывод claims
- [`docs/plans/cognito-idp-demo.md`](docs/plans/cognito-idp-demo.md) — рабочий план с историей решений

## Живое демо

**https://av-masia.github.io/AWS/**

Открывается без установки: нажать «Войти» → зарегистрироваться на любой email → код
приходит письмом (проверить папку «Спам», отправитель `no-reply@verificationemail.com`) →
после входа видны email и claims из ID-токена.

Страница собирается и публикуется автоматически из ветки `main` —
[`.github/workflows/deploy-pages.yml`](.github/workflows/deploy-pages.yml).

В app client Cognito разрешены два адреса возврата: публичный и `http://localhost:5173`
для локальной разработки.

---

## Типы аутентификации в Cognito и почему выбран Authorization Code + PKCE

Cognito предлагает два принципиально разных подхода, и их важно не путать.

### Подход 1: страница входа Cognito (managed login / hosted UI)

Приложение редиректит пользователя на домен Cognito, тот сам показывает форму, сам обрабатывает
регистрацию, подтверждение кода, восстановление пароля и MFA, а обратно возвращает токен.
Взаимодействие идёт по стандарту OIDC, поверх OAuth 2.0:

| Flow | Где применяется |
|---|---|
| **Authorization Code + PKCE** | **Выбран.** SPA и мобильные приложения — отраслевой стандарт |
| Authorization Code + client secret | Серверные приложения, где секрет можно хранить безопасно |
| Implicit grant | Устаревший, токен светится в адресной строке; AWS не рекомендует |
| Client credentials | Машина-машина, без пользователя вообще |

### Подход 2: своя форма входа через API Cognito

Приложение рисует форму само и вызывает API. Именно эти флоу перечислены в app client
в блоке **Authentication flows**:

| Flow | Что делает | В нашем пуле |
|---|---|---|
| `ALLOW_USER_SRP_AUTH` | Secure Remote Password — пароль не передаётся по сети даже в шифрованном виде, вместо него криптографическое доказательство знания | включён (дефолт) |
| `ALLOW_USER_AUTH` | Choice-based: пользователь выбирает способ — пароль, код на email, SMS, passkey. Основа passwordless-сценариев | включён (дефолт) |
| `ALLOW_REFRESH_TOKEN_AUTH` | Обновление токенов без повторного входа | включён (дефолт) |
| `ALLOW_USER_PASSWORD_AUTH` | Пароль уходит на API в открытом виде (внутри TLS). Легаси, для миграций | выключен |
| `ALLOW_ADMIN_USER_PASSWORD_AUTH` | То же, но серверным вызовом от имени администратора | выключен |
| `ALLOW_CUSTOM_AUTH` | Произвольная логика на Lambda-триггерах | выключен |

Отдельно от флоу настраивается **федерация** — вход через Google, Facebook, Apple, Amazon,
а также корпоративный через SAML 2.0 и OIDC. Она работает поверх страницы Cognito и не требует
менять приложение.

### Почему именно Authorization Code + PKCE

- **Самый распространённый.** Это рекомендация OAuth 2.1 и AWS для любого публичного клиента;
  SRP используется, только если нужна своя форма входа.
- **Приложение не касается пароля** — снимается целый класс рисков и требований к коду.
- **Регистрация, коды подтверждения, сброс пароля, MFA, вход через Google** уже реализованы
  на стороне Cognito. Своя форма означала бы реализовывать это руками.
- **Готовая библиотека.** Консоль Cognito сама предлагает сниппет под `react-oidc-context` —
  ровно то, что здесь используется.

Что показательно: AWS по умолчанию **не включает** `ALLOW_USER_PASSWORD_AUTH` — флоу с передачей
пароля на API. Умолчания настроены на более безопасные варианты.

---

## Можно ли бесплатно

**Да, для этой задачи выходит $0.**

### Free tier Cognito

| План | Free tier | Дальше |
|---|---|---|
| **Lite** | 10 000 MAU/мес | $0,0055/MAU (первые 90 000) |
| **Essentials** (используется здесь) | 10 000 MAU/мес | $0,015/MAU |
| **Plus** (threat protection) | нет | $0,020/MAU |
| Федерация SAML/OIDC | 50 MAU/мес на любом плане | $0,015/MAU |
| AWS Lambda (для бонусного триггера) | 1 000 000 запросов + 400 000 GB-с в месяц | по прайсу |

MAU — monthly active user, пользователь, совершивший хотя бы одно действие за месяц. У демо
их один. До 10 000 — бесплатно.

Важно: free tier Cognito и Lambda **бессрочные**, а не «первые 12 месяцев» — страница цен Cognito
говорит прямо, что он «does not automatically expire at the end of your 12-month AWS Free Tier term».

### Подписки в кабинете AWS

Заказчик спрашивал, какие вообще бывают тарифы. В кабинете их два независимых уровня.

**1. План аккаунта** — выбирается один раз при регистрации:

| | Free plan (выбран) | Paid plan |
|---|---|---|
| Стартовые кредиты | $100 + до $100 за обучающие активности | те же |
| Always free сервисы (в т.ч. Cognito) | есть | есть |
| Списания с карты | невозможны | всё сверх кредитов по прайсу |
| Срок | 6 месяцев или до конца кредитов, потом аккаунт закрывается | бессрочно |
| Доступ к сервисам | урезан (нет Savings Plans, Reserved Instances, части Marketplace) | полный |

Аккаунт этого демо на Free plan, срок — **до 17 февраля 2027**. Переход на Paid возможен
в любой момент, обратно — нет.

**2. Feature plan самого пула Cognito** — Lite / Essentials / Plus, переключается у каждого пула
отдельно. Влияет на функциональность (passwordless, managed login, threat protection),
но free tier в 10 000 MAU одинаков у Lite и Essentials, поэтому на стоимость демо выбор не влияет.

**Организационный момент:** карта нужна даже для полностью бесплатного аккаунта — при регистрации
холдируется ~$1 и возвращается.

Источники: [Cognito pricing](https://aws.amazon.com/cognito/pricing/),
[Lambda pricing](https://aws.amazon.com/lambda/pricing/),
[Choosing a plan](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html) —
проверено 17.08.2026.

---

## Грабли, на которые наступили

Не входило в задание, но экономит время тому, кто будет повторять.

| Проблема | Причина и решение |
|---|---|
| В консоли рядом два мастера: **Identity pool** и **User pool** | Разные сервисы. Identity pool меняет токен на временные ключи доступа к самой инфраструктуре AWS (S3, DynamoDB). Для логина в приложение нужен **User pool** |
| `invalid_scope` на редиректе, ещё до формы входа | App client разрешал `openid`, `email`, `phone`, но не `profile`. Убрали `profile` из запроса: пул собирает только email, профильные claims всё равно были бы пустыми. Запрашивать только нужное — правильнее и по существу |
| После «Выйти» — страница ошибки Cognito | Мастер спрашивает callback URL, но **не** sign-out URL. `Allowed sign-out URLs` добавляется вручную в App clients → Login pages |
| Не приходит письмо с кодом | Лежало в «Спаме». Отправитель — `no-reply@verificationemail.com`, чужой домен. Диагностика без консоли: вызвать `ResendConfirmationCode` публичным API — если в ответе есть `CodeDeliveryDetails`, Cognito письмо отдал, и дело только в доставке |
| «User is not confirmed», а форму ввода кода страница уже не показывает | Регистрация начата в прошлой сессии браузера. Лечится вызовом `ConfirmSignUp` с кодом из письма или админским `Confirm user` в консоли |
| Лимит писем | Дефолтный отправитель Cognito — **50 писем в сутки на весь AWS-аккаунт**, сброс в 09:00 UTC, не повышается. Не жать «Resend» подряд. В проде пул переключают на Amazon SES со своим доменом |
| Опечатка в email при регистрации | Hard bounce кладёт адрес в suppression list AWS, и на дефолтном отправителе снять его оттуда нельзя |

---

## Что осталось за рамками задания 1

Сознательно, по договорённости — задача на скорость, а не на полноту:

- продакшн-рассылка через Amazon SES со своим доменом вместо дефолтного отправителя
- MFA, свой домен для страницы входа, кастомный брендинг
- Lambda-триггер `Pre token generation` для кастомных claims в токене

IaC и Lambda-триггеры перестали быть «за рамками» — это и есть задание 2.

---

# Задание 2: миграция без сброса паролей и honeypot вместо капчи

Второй пул поднят **целиком в Terraform**, консоль не использовалась. Пул задания 1 остался как есть.

| Ресурс | Значение |
|---|---|
| User Pool | `eu-central-1_F3JBMc9Ld` (feature plan Essentials) |
| App client | `jooc52jcone06i98bhme7anno` (публичный, без секрета) |
| Legacy DB | RDS PostgreSQL 18, `db.t4g.micro`, 50 пользователей с bcrypt-хэшами |
| Секрет | `legacy-db/postgres` в Secrets Manager, пароль сгенерирован Terraform |
| Триггеры | `user-migration` (в VPC), `pre-signup` (вне VPC) |
| Логи Cognito | `userNotification`/`ERROR` → `/aws/vendedlogs/cognito/cognito-legacy-migration` |
| Приватный доступ к секретам | interface VPC endpoint, трафик не выходит из сети AWS |

Код: [`infra/`](infra/) — Terraform, [`lambda/`](lambda/) — функции, [`scripts/`](scripts/) — сев
и проверка legacy-БД. План с историей решений и ревью:
[`docs/plans/cognito-lambda-triggers.md`](docs/plans/cognito-lambda-triggers.md).

## Как работает миграция

```
Браузер                     Cognito                  Lambda                Legacy PostgreSQL
   │                           │                        │                         │
   │ 1. email + пароль         │                        │                         │
   ├──────────────────────────>│                        │                         │
   │   InitiateAuth            │                        │                         │
   │   USER_PASSWORD_AUTH      │                        │                         │
   │                           │ 2. такого юзера нет →  │                         │
   │                           │    User Migration      │                         │
   │                           ├───────────────────────>│                         │
   │                           │                        │ 3. креды из Secrets     │
   │                           │                        │    Manager (один раз    │
   │                           │                        │    на контейнер)        │
   │                           │                        ├────────────────────────>│
   │                           │                        │ 4. bcrypt.compare       │
   │                           │ 5. userAttributes +    │<────────────────────────┤
   │                           │    finalUserStatus     │                         │
   │                           │    CONFIRMED           │                         │
   │                           │<───────────────────────┤                         │
   │ 6. id/access/refresh      │                        │                         │
   │<──────────────────────────┤ Cognito сам создал     │                         │
   │                           │ профиль с тем же       │                         │
   │                           │ паролем                │                         │
```

Пользователь не заметил ничего: тот же пароль, никакого «придумайте новый». Второй вход
идёт уже мимо старой базы — Lambda не вызывается вообще.

**Почему `USER_PASSWORD_AUTH`, а не SRP.** Триггеру нужен сам пароль, чтобы сверить его с хэшем
в старой базе. SRP скрывает пароль от всех, включая нашу Lambda, — с ним миграция невозможна.
Это прямо написано в
[документации](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-import-using-lambda.html),
там же рекомендация: после переезда пользователей переходить на SRP. Пароль при этом уходит
на API Cognito внутри TLS и в приложении не хранится.

**Про 5 секунд.** Cognito ждёт ответа триггера максимум 5 секунд, и это значение изменить нельзя.
Поэтому чтение секрета и `pg.Pool` создаются **вне handler**: они переиспользуются между вызовами
тёплого контейнера. В логах это видно как одна запись `init` на все последующие вызовы.

Замеры на живом пуле:

| Что | Время |
|---|---|
| Инициализация (секрет + пул соединений), один раз на контейнер | 88 мс |
| Работа самой Lambda (SQL + bcrypt) | 269 мс |
| Первый вход целиком, с холодным старом в VPC | 3749 мс |
| Повторный вход (пользователь уже в Cognito, Lambda не вызывается) | 1807 мс |

## Как работает honeypot

Два сигнала уходят в `pre-signup` триггер через `ClientMetadata` вызова `SignUp`:

1. **`phone_confirm`** — скрытое поле формы. Человек его не видит (убрано за границу экрана,
   `tabIndex=-1`, `aria-hidden`), автозаполнялка бота — заполняет.
2. **`form_rendered_at`** — момент отрисовки формы. Если от рендера до отправки прошло меньше
   **1.5 секунд**, человек физически не успел бы набрать email и пароль.

Отказ выглядит так: `PreSignUp failed with error Automated traffic detected.` Текст **одинаковый**
для обеих проверок — боту не подсказываем, на чём он попался. Различие (`honeypot_filled` или
`too_fast`) остаётся только в логах.

Три случая, когда мы осознанно **не** блокируем:

- `clientMetadata` нет вообще — так приходит регистрация со страницы входа Cognito, она эти данные
  передавать не умеет. Иначе сломался бы штатный флоу задания 1;
- `form_rendered_at` из будущего (часы клиента спешат) или старше суток (форма висела открытой);
- `triggerSource` не `PreSignUp_SignUp` — пользователей, созданных администратором, и первый вход
  федеративного пользователя не проверяем.

**Почему honeypot нельзя сделать на странице входа Cognito.** `clientMetadata` приходит в триггер
только из API-операций (`SignUp`, `AdminCreateUser`, `AdminRespondToAuthChallenge`, `ForgotPassword`)
и с token endpoint. Managed login его не передаёт — поэтому для этого задания нужна своя форма.
Она же нужна и для миграции: там требуется флоу с паролем.

Границы проверены локальными тестами: [`lambda/pre-signup/test.mjs`](lambda/pre-signup/test.mjs),
9 случаев, `node --test`.

## Логи: ни паролей, ни PII

Строгое правило задания выполнено: в CloudWatch не попадает ничего личного.

- Событие целиком **не логируется никогда** — в нём лежит открытый пароль. Об этом прямо
  предупреждает документация AWS.
- Вместо email — необратимая метка `userRef`: первые 12 символов от `sha256(userPoolId + email)`.
  По ней можно связать записи между собой, но нельзя восстановить адрес.
- Дальше только метаданные: `triggerSource`, `userPoolId`, `clientId`, код результата
  (`migrated` / `bad_password` / `not_found`), длительность.

Так выглядит запись о миграции:

```json
{
  "level": "INFO", "message": "user migrated", "service": "user-migration",
  "function_request_id": "...", "cold_start": false,
  "event_id": "user_migration", "triggerSource": "UserMigration_Authentication",
  "userPoolId": "eu-central-1_F3JBMc9Ld", "clientId": "jooc52jcone06i98bhme7anno",
  "userRef": "d69bb6c6e931", "outcome": "migrated", "duration_ms": 269
}
```

JSON во всех записях, включая платформенные `START`/`END`/`REPORT` — за это отвечает
`logging_config { log_format = "JSON" }` у функции. Структурированный логинг — на
[Powertools for AWS Lambda](https://docs.powertools.aws.dev/lambda/typescript/latest/).

Проверка: все записи выгружены и просмотрены поиском — `user07@example.com` 0 совпадений,
`LegacyPass` 0, `@example.com` 0. Единственное совпадение по слову `password` — код причины
`"outcome":"bad_password"`.

## Zero-Trust: доступы

- У роли миграции **ровно одно** право поверх стандартного: `secretsmanager:GetSecretValue`
  на конкретный ARN секрета. Ни `secretsmanager:*`, ни `Resource: "*"`.
- У honeypot-функции нет доступа ни к секретам, ни к базе, ни к VPC: ей нужны только метаданные
  формы. Меньше прав — меньше поверхность атаки.
- Порт 5432 legacy-БД открыт только для security group Lambda и одного IP разработчика
  (нужен, чтобы засеять 50 пользователей). В проде `publicly_accessible = false` — одна строка.
- Lambda в VPC не имеет выхода в интернет вообще: секрет достаётся через interface VPC endpoint.
- TLS к базе с **проверкой сертификата** по официальному CA-бандлу RDS, а не
  `rejectUnauthorized: false`: иначе шифрование защищает только от пассивного прослушивания.
- Ресурсная политика Lambda сужена условиями `SourceArn` и `SourceAccount` до одного пула
  в одном аккаунте. При создании триггера не из консоли Cognito её нужно прописывать самому.
- Стейт Terraform и `tfplan` в репозиторий не попадают: в них пароль RDS открытым текстом.
  В проде вместо этого — S3 backend с шифрованием.

## Что проверено

| Сценарий | Результат |
|---|---|
| Вход легаси-юзером, которого нет в Cognito | токены выданы, профиль создан: `CONFIRMED`, `email_verified: true`, из старой базы перенесено `name` |
| Приветственное письмо при миграции | не отправляется (`messageAction: SUPPRESS`) |
| Повторный вход того же юзера | Lambda не вызывается, старая база не опрашивается |
| Неверный пароль легаси-юзера | `NotAuthorizedException`, профиль в пуле не создан |
| Регистрация с заполненным `phone_confirm` | `PreSignUp failed with error Automated traffic detected.` |
| Регистрация за 200 мс | тот же отказ |
| Честная регистрация | код письмом → `ConfirmSignUp` → вход с токенами |
| Регистрация без `clientMetadata` | проходит: не ломаем страницу входа Cognito |
| `terraform plan` после `apply` | `No changes` |

## Как повторить

```bash
# 1. Инфраструктура
cd infra
cp terraform.tfvars.example terraform.tfvars   # вписать свой IP: curl -s https://checkip.amazonaws.com
terraform init
terraform apply

# 2. Зависимости функций — до apply, они уходят в zip
cd ../lambda/user-migration && npm install --omit=dev
cd ../pre-signup && npm install --omit=dev

# 3. Засеять «старую базу» 50 пользователями
cd ../../scripts && npm install && node seed.mjs

# 4. Конфиг фронтенда
cd ../infra && terraform output          # user_pool_id, user_pool_client_id → web/.env.local
```

Проверки без браузера:

```bash
# вход легаси-пользователя (пройдёт через триггер миграции)
aws cognito-idp initiate-auth --client-id <client> --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=user07@example.com,PASSWORD='LegacyPass07!'

# honeypot и тайминг на живом API
cd scripts && COGNITO_CLIENT_ID=<client> node signup-probe.mjs bot@example.com 200
```

## Стоимость задания 2

Cognito (10 000 MAU/мес), Lambda (1 млн запросов/мес) и CloudWatch (5 ГБ/мес) укладываются
в бессрочный free tier — $0. Платное только это:

| Что | Цена | За сутки |
|---|---|---|
| RDS `db.t4g.micro` PostgreSQL Single-AZ, EU (Frankfurt) | $0,019/ч | ~$0,46 |
| Storage gp3, 20 ГБ | $0,137/ГБ-мес | ~$0,09 |
| Interface VPC endpoint, 2 ENI | ~$0,01/ч за ENI | ~$0,48 |
| Секрет в Secrets Manager | $0,40/мес | ~$0,01 |

Итого **~$1 в сутки**, и это из кредитов, а не с карты. Цены RDS — из официального прайс-фида AWS
(`b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/rds/...`), проверено 18.08.2026.

Важное про новые аккаунты: на **Free plan** доступны только always-free сервисы и кредиты —
12-месячные trial-офферы (в том числе 750 часов RDS) идут лишь на Paid plan
([Choosing a plan](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html)).
Так что RDS оплачивается кредитами. Приятный побочный эффект: за создание RDS и Lambda AWS
начислил ещё $40 кредитов сверх стартовых $100.

После демо инфраструктура гасится одной командой: `cd infra && terraform destroy`.

## Грабли задания 2

| Проблема | Причина и решение |
|---|---|
| `terraform apply` падает: `Character sets beyond ASCII are not supported` | AWS не принимает не-ASCII в `description` у security group и её правил. Описания — по-английски, пояснения — в комментариях HCL |
| `Domain cannot contain reserved word: cognito` | В имени домена страницы входа запрещены `cognito`, `aws`, `amazon`. А проект назывался `cognito-legacy-migration` |
| Проверка «регистрация быстрее 1.5 с» не срабатывает через `aws cli` | Сам CLI на Python стартует ~3 секунды, и триггер честно видит «форму заполняли 3 с». Компенсировать сдвигом timestamp бессмысленно — задержка каждый раз разная. Решение: [`scripts/signup-probe.mjs`](scripts/signup-probe.mjs) на SDK, где timestamp формируется в том же процессе, что и запрос |
| `pg` не подключается к RDS | В дефолтной группе параметров PostgreSQL включён `rds.force_ssl=1`. Нужен TLS, а сертификат стоит проверять по CA-бандлу RDS |
| Нативный `bcrypt` не собирается | С Windows-машины пакет под Linux-рантайм Lambda не соберётся. `bcryptjs` — чистый JS, работает как есть |
| Повторный `terraform apply` после `destroy` спорит об имени секрета | Secrets Manager удаляет секреты с задержкой. `recovery_window_in_days = 0` убирает проблему |
| AWS SDK в браузере требует ключи | Не требует: `SignUp`, `ConfirmSignUp`, `InitiateAuth` — публичные операции, подписи не требуют. Клиент создаётся как `new CognitoIdentityProviderClient({ region })` без `credentials`. Проверено запуском вообще без доступных кредов |

## Что осталось за рамками задания 2

- Реальные 100k пользователей: в демо 50, по договорённости. Триггер от количества не зависит
- Продакшн-обвязка RDS: Multi-AZ, бэкапы, своё VPC с приватными подсетями, RDS Proxy
- Ротация секрета, MFA, threat protection (нужен feature plan Plus), логи `userAuthEvents`
- Экспорт логов входов: требует Plus, а у него нет free tier
