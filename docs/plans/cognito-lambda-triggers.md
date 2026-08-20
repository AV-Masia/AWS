# Задание 2: Cognito + Lambda-триггеры — миграция без сброса паролей, honeypot, Zero-Trust логи

**Источник:** текстовая постановка заказчика (`New Text Document.txt`, пришла 18.08.2026, прочитана
из битой кодировки UTF-8→CP1252) + уточнение в чате: «…буду использовать PostgreSQL и 50 юзеров»
(первое слово уточнения нечитаемо из-за кодировки, смысл однозначен).
**Заказчик:** Андрей Антамошин · **Исполнитель:** Анастасия Васько
**Срок:** не назван. Рабочее допущение — 1 рабочий день, как в задании 1.
**Предыдущее задание:** [`cognito-idp-demo.md`](cognito-idp-demo.md) — сдано, пул `eu-central-1_QTI9GPqq3`
живёт, демо на https://av-masia.github.io/AWS/

**Критерий заказчика:** скорость за счёт максимального использования AI (прямая цитата в плане
задания 1). **Но** в этой постановке впервые появились требования к качеству, названные явно:
IaC обязателен, ручная настройка через консоль **не допускается**, PII в логах **запрещён**.
Значит: быстро — да, но по перечисленным пунктам углы не срезаем. Всё, чего в постановке нет,
идёт в `[опционально]` и делается только после рабочего демо.

---

## Что нужно сделать

Поднять **новый** Cognito User Pool целиком в Terraform и повесить на него два триггера:

1. **User Migration** — вход пользователя, которого в Cognito ещё нет: Lambda берёт креды legacy-БД
   из Secrets Manager, проверяет bcrypt-хэш в PostgreSQL, возвращает `SUCCESS` → Cognito сам создаёт
   пользователя с тем же паролем. Пользователь ничего не замечает, пароль не сбрасывается.
2. **Pre Sign-up** — honeypot-защита формы регистрации без капчи: скрытое поле `phone_confirm`
   заполнено → блок; от рендера формы до сабмита прошло < 1.5 с → блок с ошибкой
   `Automated traffic detected`.

Плюс сквозные требования: Secrets Manager для кредов legacy-БД, структурированный JSON-логинг
(Powertools), ноль PII/паролей/токенов в CloudWatch, логирование Cognito в CloudWatch, всё в IaC.

## Требования из постановки

| # | Требование | Метка |
|---|-----------|-------|
| 1 | Вся инфраструктура — Terraform или CDK; консоль не допускается | **явное** |
| 2 | Cognito User Pool + App Client | **явное** |
| 3 | Логирование Cognito в CloudWatch | **явное** |
| 4 | Secrets Manager для кредов legacy-БД | **явное** |
| 5 | Триггер User Migration: перехват `event.userName` / `event.password`, проверка bcrypt, `userAttributes` + `SUCCESS` | **явное** |
| 6 | Инициализация подключения к БД/Secrets Manager — **вне** handler (пулинг между вызовами) | **явное** |
| 7 | Триггер Pre Sign-up: honeypot `phone_confirm` + тайминг < 1.5 с → `Automated traffic detected` | **явное** |
| 8 | Данные читаются из `event.request.clientMetadata` | **явное** |
| 9 | Структурированный JSON-логинг во всех Lambda (рекомендация — Powertools) | **явное** |
| 10 | В CloudWatch не попадают пароли, токены, email, phone. Только метаданные и ID событий | **явное** |
| 11 | Legacy-БД — PostgreSQL, 50 пользователей (в постановке 100k + разрешён mock, уточнено в чате) | **явное** (уточнение) |
| 12 | Хэширование реалистичное — bcrypt | **явное** |
| 13 | Своя форма регистрации и входа в приложении | **выведено**: managed login не передаёт `clientMetadata` и не отдаёт пароль в `USER_PASSWORD_AUTH` — без своей формы пункты 5 и 7 не проверить |
| 14 | Регион `eu-central-1`, репозиторий и React-приложение из задания 1 | **выведено** |
| 15 | Демо доступно заказчику по ссылке (GitHub Pages), как в задании 1 | **предположение** → вопрос 4 |

## Критерии приёмки

Проверено 18.08.2026. Фактические ID: пул `eu-central-1_F3JBMc9Ld`, app client `jooc52jcone06i98bhme7anno`.

- [~] `terraform apply` поднимает всё: пул, app client, 2 Lambda, RDS, секрет, VPC endpoint, лог-группы,
      log delivery — **25 ресурсов** под управлением (плюс 7 data-источников),
      `terraform plan` после → `No changes`.
      **Хвост:** apply шёл инкрементально. Полный прогон с нуля **до** показа делать нельзя:
      новый пул получит другой ID, и придётся переписывать `.env.production`, README и пересобирать
      Pages. Проверяем после показа заказчика, вместе с `destroy`
- [x] Руками в консоли не создано ничего, кроме IAM-пользователя `terraform-admin` для Terraform
- [x] В legacy PostgreSQL 50 пользователей, у всех bcrypt-хэши: `total: 50, with bcrypt hashes: 50`
- [x] Вход легаси-юзером, которого нет в Cognito, отдаёт токены; пользователь появился в пуле:
      `UserStatus: CONFIRMED`, `email_verified: true`, и из старой базы подтянулось `name: Legacy User 07`.
      Welcome-письма не было (`messageAction: SUPPRESS`). Пока проверено через `initiate-auth` в CLI,
      своя форма — шаг 6
- [x] Второй вход того же юзера в legacy-БД не ходит: Lambda не вызывается (в логах на 2 входа
      user07 только одна запись миграции), время входа 3749 мс → 1807 мс
- [x] Неверный пароль легаси-юзера → `NotAuthorizedException: Incorrect username or password`,
      `admin-get-user` → `UserNotFoundException`
- [x] Регистрация с заполненным `phone_confirm` → `UserLambdaValidationException: PreSignUp failed
      with error Automated traffic detected.`, пользователь не создан
- [x] Регистрация быстрее 1.5 с → `UserLambdaValidationException: PreSignUp failed with error
      Automated traffic detected.` Проверено на живом API через `scripts/signup-probe.mjs`
      (SDK, timestamp формируется в том же процессе): 200 мс → отказ.
      Через `aws cli` этот сценарий не проверяется вообще: он сам стартует ~3 секунды, и Lambda
      честно видит «форму заполняли 3 с». Границы добраны локальными тестами (`node --test`, 9 из 9)
- [x] Честная регистрация проходит целиком: `SignUp` (форма заполнялась 5 с) → код письмом на
      реальный ящик → `ConfirmSignUp` → `InitiateAuth` отдаёт токены, статус `CONFIRMED`,
      `email_verified: true`
- [x] Логи обеих Lambda — JSON: `level`, `service`, `function_request_id`, `triggerSource`, `cold_start`.
      Работает благодаря `logging_config { log_format = "JSON" }`
- [x] Инициализация вне handler подтверждена: **одна** запись `init` (`secret_loaded`, `pool_created`,
      `init_ms: 88`) на все последующие вызовы; сама миграция — 269 мс
- [x] **Ноль PII в логах.** 13 записей выгружены целиком: `user07@example.com` — 0 совпадений,
      `LegacyPass` — 0, `@example.com` — 0. Единственное совпадение по `password` — код причины
      `"outcome":"bad_password"`
- [x] Логи Cognito уходят в CloudWatch: `userNotification` / `ERROR` →
      `/aws/vendedlogs/cognito/cognito-legacy-migration`
- [x] Наименьшие привилегии: у роли миграции ровно один statement —
      `secretsmanager:GetSecretValue` на конкретный ARN; у роли honeypot нет ни секретов, ни VPC.
      В порт 5432 пускают только `188.123.153.142/32` и SG Lambda
- [ ] README обновлён разделом про задание 2, PR смержен в `main`

## Не входит в задачу

- Реальные 100k пользователей и нагрузочное тестирование — по уточнению заказчика 50
- Продакшн-обвязка RDS: Multi-AZ, бэкапы, своё VPC с приватными подсетями, RDS Proxy
- Ротация секрета, MFA, threat protection, свой домен, SES
- Миграция пользователей, зарегистрированных в пуле задания 1, в новый пул
- Красивый UI: формы — минимально рабочие
- Terraform-import пула из задания 1 (см. «Решения»)

---

## Решения

| Развилка | Выбор | Почему |
|---|---|---|
| Terraform или CDK | **Terraform** | Постановка разрешает любой; Terraform не требует бутстрапа CDK и Docker-сборок, читается заказчиком без запуска |
| Новый пул или import пула из задания 1 | **Новый пул в Terraform**, консольный сначала не трогаем | Import консольного пула — возня со сверкой атрибутов и риск сломать работающее демо задания 1. Требование «всё в IaC» относится к тому, что сдаём сейчас |
| Что делать с двумя пулами после сдачи (решено 18.08.2026 по просьбе заказчика демо) | **Оставить один — Terraform-пул**, консольный `eu-central-1_QTI9GPqq3` удалить, оба задания перевести на общий пул | Два почти одинаковых пула путают: легаси-пользователь въезжает только в тот, где висят триггеры, а страница входа задания 1 вела в другой — на этом уже спотыкались при проверке. Terraform-пул умеет всё, что нужно заданию 1 (домен, OIDC code + PKCE, регистрация по email), и при этом описан кодом. Цена: в общем пуле включён `ALLOW_USER_PASSWORD_AUTH`, а пользователи консольного пула теряются вместе с ним |
| Legacy-БД | **RDS PostgreSQL** `db.t4g.micro`, single-AZ, 20 ГБ gp3 | Заказчик прямо назвал PostgreSQL. Mock в DynamoDB дешевле, но это уже не «legacy DB» |
| Как Lambda достаёт секрет | **Lambda в VPC + interface VPC endpoint для Secrets Manager** | Lambda в VPC не имеет выхода в интернет. Endpoint — ~$0,01/ч за ENI против NAT gateway $0,045/ч, и трафик не выходит из VPC (Zero-Trust) |
| Доступ к RDS с ноутбука для сева | `publicly_accessible = true` + security group **только** на свой `/32` | Иначе сеять 50 юзеров пришлось бы через одноразовую Lambda. В README — одна строка, как закрыть в проде |
| Форма входа/регистрации | **Своя форма** на `@aws-sdk/client-cognito-identity-provider` (`SignUp` + `InitiateAuth USER_PASSWORD_AUTH`); managed login задания 1 остаётся рядом | `clientMetadata` для pre sign-up приходит только из API-операций (`SignUp`, `AdminCreateUser`, `AdminRespondToAuthChallenge`, `ForgotPassword`) и с token endpoint — managed login honeypot передать не может. Плюс миграция требует флоу с паролем |
| bcrypt в Lambda | **`bcryptjs`** (чистый JS) | Нативный `bcrypt` надо собирать под Linux-рантайм; с Windows-машины это блокер, а не задача |
| Логирование Cognito | `aws_cognito_log_delivery_configuration`, `userNotification` / `ERROR` → CloudWatch | Второй тип, `userAuthEvents`, требует feature plan **Plus** + threat protection, а у Plus **нет** free tier ($0,020/MAU) |
| Логинг в Lambda | **`@aws-lambda-powertools/logger`** | Прямая рекомендация постановки; из коробки JSON, `function_request_id`, уровни |
| Пулинг | `pg.Pool` и клиент Secrets Manager создаются на уровне модуля, секрет кэшируется | Требование 6 постановки |
| Откуда пароль RDS | `random_password` в Terraform → в секрет и в `aws_db_instance` | Альтернатива `manage_master_user_password = true` отдаёт создание секрета самому RDS, и требование «развернуть Secrets Manager для кредов» выглядит невыполненным. Цена решения — пароль в `tfstate`, см. риски |
| Feature plan пула | **Essentials** | Как в задании 1; free tier 10 000 MAU тот же, что у Lite |

## Стоимость (проверено 18.08.2026)

Аккаунт на **Free plan** (до 17.02.2027, $100 кредитов). Ключевое: Free plan даёт **только**
always-free сервисы и кредиты — 12-месячные trial-офферы (включая 750 ч RDS `db.t4g.micro`)
доступны лишь на Paid plan: *«Access to Always free services»* против *«Always free services and
short-term trial offers»* ([Choosing a plan](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html)).
Значит **RDS оплачивается кредитами**.

| Что | Цена | За 3 дня демо |
|---|---|---|
| Cognito Essentials | 10 000 MAU/мес бесплатно | $0 |
| Lambda | 1 млн запросов/мес бесплатно | $0 |
| Secrets Manager | $0,40/секрет/мес + $0,05/10k вызовов ([прайс](https://aws.amazon.com/secrets-manager/pricing/)) | ~$0,04 |
| VPC interface endpoint | ~$0,01/ч за ENI + $0,01/ГБ ([PrivateLink](https://aws.amazon.com/privatelink/pricing/)) | ~$0,7 |
| RDS `db.t4g.micro` PostgreSQL, Single-AZ, EU (Frankfurt) | **$0,019/ч** = $13,87/мес | ~$1,4 |
| Storage gp3 Single-AZ, 20 ГБ | **$0,137/ГБ-мес** = $2,74/мес | ~$0,3 |
| CloudWatch Logs | 5 ГБ/мес бесплатно, у нас единицы МБ | $0 |

Цены RDS — из официального прайс-фида AWS (`b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/rds/...`,
тот же источник, что у калькулятора; публикация фида 18.08.2026).

Итого **~$2,5 за трёхдневное демо из $100 кредитов**. Списаний с карты на Free plan не бывает by design,
но при исчерпании кредитов аккаунт закрывается — поэтому `terraform destroy` после демо.

---

## План

### 0. Окружение и доступы — блокер, делать первым

- [x] Terraform CLI — `v1.15.8` через `winget install --id Hashicorp.Terraform -e`.
      Лёг в `%LOCALAPPDATA%\Microsoft\WinGet\Packages\Hashicorp.Terraform_*\terraform.exe`,
      PATH подхватится только в новом терминале
- [x] AWS CLI v2 — `2.36.25` через `winget install --id Amazon.AWSCLI -e`, в `C:\Program Files\Amazon\AWSCLIV2`
- [x] IAM-пользователь `terraform-admin` с `AdministratorAccess` + access key (**не** root-ключи),
      `aws configure` с регионом `eu-central-1` — проверка: `aws sts get-caller-identity` → JSON с Account.
      **Делает Анастасия сама** в своём терминале: секретный ключ не должен попасть в чат и в логи сессии
- [x] Node уже стоит (`v24.19.0`, `C:\Program Files\nodejs`). В уже открытом терминале:
      `export PATH="/c/Program Files/nodejs:$PATH"` (bash)
- [x] Ветка `task2-triggers` создана от `main`
- [x] Посмотреть остаток кредитов: Billing → Credits — проверка: остаток > $10

### 1. Terraform-скелет + RDS (~40–60 мин, RDS создаётся 5–15 мин — запускать раньше остального)

- [x] `infra/providers.tf`: `aws ~> 6.5` (в 6.5.0 появился
      `aws_cognito_log_delivery_configuration`,
      [CHANGELOG 6.5.0 от 24.07.2025](https://github.com/hashicorp/terraform-provider-aws/blob/main/CHANGELOG.md)),
      регион и `my_ip` — переменные, `default_tags = { project = "cognito-legacy-migration" }`.
      Фактически поставился Terraform `v1.15.8`, провайдер `aws v6.60.0`
- [x] `infra/.gitignore`: `.terraform/`, `*.tfstate*`, `*.tfvars`. `.terraform.lock.hcl`, наоборот,
      **коммитим** — он фиксирует версии провайдеров
- [x] `infra/network.tf`: default VPC `vpc-0698f05ddcd4bdf03`, три подсети (три AZ), Lambda и endpoint
      живут в двух: `subnet-05f8b82555b341650`, `subnet-0a5da65f82aff75fa`.
      SG: `lambda` `sg-07381bbf9deb885dd`, `rds` `sg-036359964bdbe3104`, `vpce`.
      Interface endpoint `vpce-02ca7a9697039d721` — создавался 1 мин 3 с
- [x] `infra/rds.tf`: `aws_db_subnet_group` из подсетей default VPC (полагаться на группу `default`
      нельзя — она есть не в каждом аккаунте), затем
      `aws_db_instance` postgres **18**, `db.t4g.micro`, 20 ГБ gp3 (`storage_encrypted = true`),
      `publicly_accessible = true`, `backup_retention_period = 0`, `skip_final_snapshot = true`,
      `deletion_protection = false`. Инстанс создавался **5 мин 7 с**, endpoint:
      `cognito-legacy-migration-legacy.cx6k8y6gc6ri.eu-central-1.rds.amazonaws.com:5432`
- [x] `infra/secrets.tf`: `random_password` (32 символа, `special = false` — чтобы не ломать URI),
      `aws_secretsmanager_secret` (`recovery_window_in_days = 0`, иначе повторный `apply` упрётся
      в имя, «запланированное к удалению») + версия с JSON `{host, port, dbname, username, password}`
- [x] Проверка пройдена: `Apply complete! Resources: 6 added`; секрет читается;
      `terraform plan` → `No changes. Your infrastructure matches the configuration.`
- [x] **Гейт пройден:** RDS на Free plan создаётся, ограничений нет — fallback на внешний Postgres
      не понадобился

### 2. Legacy-БД: схема и 50 пользователей (~20–30 мин)

- [x] `scripts/seed.mjs` на `pg` + `bcryptjs` (cost 10): таблица
      `legacy_users(email text primary key, password_hash text not null, full_name text, created_at timestamptz default now())`,
      50 записей `user01@example.com … user50@example.com`, пароль `LegacyPass<NN>!`
- [x] Креды скрипт берёт из Secrets Manager по тому же ARN, что и Lambda (не из локального файла) —
      общий модуль `scripts/legacy-db.mjs`
- [x] **RDS требует TLS** (`rds.force_ssl = 1` в дефолтной группе параметров PostgreSQL).
      Сертификат проверяем по официальному бандлу `scripts/rds-global-bundle.pem`
      (`truststore.pki.rds.amazonaws.com/global/global-bundle.pem`, 108 сертификатов), а не через
      `rejectUnauthorized: false` — иначе TLS спасает только от пассивного прослушивания
- [x] Проверка: `node seed.mjs` → `inserted now: 50`, `total: 50, with bcrypt hashes: 50`;
      `node check.mjs user07@example.com 'LegacyPass07!'` → `true`, с неверным паролем → `false`,
      с несуществующим адресом → `false (user not found)`
- [x] Ловушка: только `bcryptjs`, не `bcrypt` — нативный модуль не соберётся под Linux с Windows-машины

### 3. Lambda `user-migration` (~40–60 мин)

- [x] `lambda/user-migration/index.mjs`. **Вне handler:** клиент Secrets Manager, чтение и кэш секрета,
      `new pg.Pool({ max: 2, connectionTimeoutMillis: 1500 })`
- [x] `UserMigration_Authentication`: `select password_hash, full_name from legacy_users where email = $1`,
      `bcrypt.compare(event.request.password, hash)`. Успех →
      `userAttributes = { email, email_verified: 'true' }`, `finalUserStatus = 'CONFIRMED'`,
      `messageAction = 'SUPPRESS'`, `desiredDeliveryMediums = ['EMAIL']`, вернуть `event`.
      Провал → `throw new Error('Bad credentials')`
- [x] `UserMigration_ForgotPassword`: пароля в событии нет — только lookup, вернуть `email` +
      `email_verified: 'true'` (иначе код сброса некуда отправить)
- [x] Любой другой `triggerSource` → `throw`
- [x] Powertools Logger. Логируем: `triggerSource`, `userPoolId`, `callerContext.clientId`,
      `sha256(email).slice(0,12)` как псевдо-ID, `outcome` (`migrated` / `rejected` / `not_found`), `duration_ms`.
      **Никогда** не логируем `event` целиком — доки прямо предупреждают: *«Do not log the entire request
      event object… passwords appear in CloudWatch Logs»*
      ([docs](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-import-using-lambda.html))
- [x] Настройки функции: рантайм `nodejs24.x` (свежий GA-рантайм, совпадает с локальным Node 24;
      `nodejs22.x` тоже поддерживается — до 30.04.2027), memory 1024 МБ (быстрее CPU → быстрее bcrypt и холодный
      старт), timeout 5 с, в VPC (SG `lambda`), IAM: `AWSLambdaVPCAccessExecutionRole` +
      `GetSecretValue` на ARN секрета, `logging_config { log_format = "JSON", application_log_level = "INFO",
      system_log_level = "WARN" }` — иначе `START/END/REPORT` в логах остаются текстом
- [x] Сборка: `npm ci --omit=dev` в папке функции + `archive_file` в Terraform — проверка: в zip есть
      `node_modules/pg` и `node_modules/bcryptjs`
- [x] Проверка: `aws lambda invoke` с тремя тестовыми событиями (верный пароль / неверный / несуществующий
      email) → в первом ответе `finalUserStatus: CONFIRMED`, в остальных ошибка; `aws logs tail` → JSON без PII

### 4. Lambda `pre-signup` — honeypot (~30–40 мин)

- [x] Эта функция — **вне VPC**, без доступа к секрету и к БД: ей нужны только `clientMetadata`
      и права на логи. Меньше прав и никакого риска не уложиться в 5 секунд на холодном старте
- [x] `triggerSource !== 'PreSignUp_SignUp'` → вернуть событие без изменений (не ломать
      `PreSignUp_AdminCreateUser` и `PreSignUp_ExternalProvider`)
- [x] **Проверено на фактах, вышло наоборот, чем я предполагала:** миграция **вызывает** pre-signup
      триггер — с источником `PreSignUp_AdminCreateUser`, через секунду после каждой успешной
      миграции (сверено по таймстампам в CloudWatch 18.08.2026). Cognito проводит созданного
      триггером пользователя как «созданного администратором».
      Значит фильтр по `triggerSource` — не перестраховка, а обязательное условие: без него
      honeypot блокировал бы **каждую** миграцию, потому что `clientMetadata` в этих событиях нет
- [x] Honeypot: `clientMetadata.phone_confirm` непустой → `throw new Error('Automated traffic detected')`
- [x] Тайминг: `elapsed = Date.now() - Number(clientMetadata.form_rendered_at)`; `0 <= elapsed < 1500` → тот же
      `throw`. `elapsed` отрицательный или > 24 ч, поле отсутствует или не число → **не блокируем**,
      пишем в лог `reason = 'metadata_invalid'` (иначе ломается регистрация через managed login,
      где `clientMetadata` не передаётся, и расходятся часы клиента)
- [x] Текст ошибки для обоих случаев одинаковый — боту не подсказываем, какая проверка сработала;
      различаются только `reason` в логах (`honeypot_filled` / `too_fast`)
- [x] Логируем: `triggerSource`, `clientId`, `decision`, `reason`, `elapsed_ms`. Email и пароль — нет
- [x] Проверка: 4 × `aws lambda invoke` (пустой honeypot + 3 с → пропуск; заполненный honeypot → ошибка;
      elapsed 300 мс → ошибка; без `clientMetadata` → пропуск)

### 5. Cognito через Terraform + подключение триггеров (~30–40 мин)

- [x] `aws_cognito_user_pool`: `username_attributes = ["email"]`, `auto_verified_attributes = ["email"]`,
      `user_pool_tier = "ESSENTIALS"`, self-registration включена,
      `lambda_config { user_migration = ..., pre_sign_up = ... }`
- [x] `aws_cognito_user_pool_client`: без секрета, `explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH",
      "ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]`, `prevent_user_existence_errors = "ENABLED"`,
      callback/logout — `http://localhost:5173` и `https://av-masia.github.io/AWS/`
- [x] `aws_lambda_permission` × 2: principal `cognito-idp.amazonaws.com`, `source_arn` = ARN пула
      (при создании триггера вне консоли Cognito ресурсную политику надо прописывать самому)
- [x] `aws_cloudwatch_log_group` на каждую Lambda с `retention_in_days = 7` (иначе логи вечные и платные)
      + группа для Cognito с именем `/aws/vendedlogs/cognito/<pool>` — доки требуют такой префикс,
      если resource-policy лог-группы вырастет больше 5120 символов
- [x] `aws_cognito_log_delivery_configuration`: `event_source = "userNotification"`, `log_level = "ERROR"`,
      `cloud_watch_logs_configuration { log_group_arn = ... }`
- [x] Проверка: `aws cognito-idp get-log-delivery-configuration --user-pool-id <id>` → конфиг на месте;
      `terraform plan` → `No changes`; `terraform output` отдаёт `user_pool_id` и `client_id` для фронта
- [x] **Сквозная проверка без фронтенда — здесь, а не после шага 6.** Тем же CLI закрываются
      почти все критерии приёмки:
      `aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id <id> --auth-parameters USERNAME=user07@example.com,PASSWORD='LegacyPass07!'`
      → в ответе `AuthenticationResult` с токенами, `admin-get-user` → `CONFIRMED`;
      тот же вызов с неверным паролем → `NotAuthorizedException`, юзера в пуле нет;
      `aws cognito-idp sign-up --client-id <id> --username <ящик> --password ... --client-metadata phone_confirm=bot`
      → `PreSignUp failed with error Automated traffic detected.`;
      то же с `form_rendered_at=<Date.now()>` → та же ошибка; с `form_rendered_at` на 5 секунд в прошлом
      → регистрация проходит
- [x] **Гейт:** пока эта проверка не прошла — во фронтенд не идти. Она и есть «работает насквозь»;
      шаг 6 добавляет к ней только витрину для заказчика

### 6. Фронтенд: своя форма регистрации и входа (~40–60 мин) — после гейта шага 5

Постановка фронтенд прямо не требует (в техтребованиях только IaC, две Lambda и логи), но заказчик
в задании 1 оценил живое демо по ссылке. Поэтому: делаем, но после того как всё доказано через CLI.

- [x] `npm i @aws-sdk/client-cognito-identity-provider` в `web/`
- [x] Ловушка: клиент создаётся как `new CognitoIdentityProviderClient({ region })` **без**
      `credentials`. `SignUp`, `ConfirmSignUp`, `ResendConfirmationCode`, `ForgotPassword` и
      `InitiateAuth` — unauthenticated-операции, доки прямо пишут: *«To send these requests in a public
      client that you developed with an AWS SDK, you don't need to configure any credentials»*
      ([список операций по модели авторизации](https://docs.aws.amazon.com/cognito/latest/developerguide/authentication-flows-public-server-side.html#user-pool-apis-auth-unauth)).
      Если начать прокидывать креды — упрёшься в поиск ключей в браузере.
      `RespondToAuthChallenge` (MFA/челленджи) авторизуется `Session`-токеном, не ключами
- [x] `web/src/legacy/LegacySignIn.tsx`: email + пароль → `InitiateAuth` с `AuthFlow: 'USER_PASSWORD_AUTH'`
      → показать `sub`, `email` и claims из ID-токена (переиспользовать вывод из задания 1)
- [x] `web/src/legacy/SignUpForm.tsx`: email + пароль, **скрытое** поле `phone_confirm`
      (`aria-hidden`, вне таб-порядка, спрятано CSS, а не `type="hidden"` — иначе бот его не заполнит),
      `formRenderedAt = useRef(Date.now())`, оба значения уходят в
      `ClientMetadata: { phone_confirm, form_rendered_at }`; экран ввода кода → `ConfirmSignUp`
- [x] Ошибку триггера показывать пользователю как есть — заказчик хочет видеть `Automated traffic detected`
- [x] Переключатель «OIDC-демо (задание 1) / Legacy-миграция (задание 2)» в `App.tsx`, без router
- [x] Новые env-переменные `VITE_COGNITO_V2_USER_POOL_ID` / `VITE_COGNITO_V2_CLIENT_ID` — **дописать**
      в `.env.example` / `.env.production`, старые не менять, чтобы демо задания 1 не сломалось
- [x] Проверка: `npm run build` проходит; локально 4 сценария из критериев приёмки; после мержа — то же
      на https://av-masia.github.io/AWS/

### 7. Проверка PII и Zero-Trust (~20 мин) — отдельный шаг, а не «заодно»

- [x] `aws logs filter-log-events --log-group-name /aws/lambda/user-migration --filter-pattern '"user07@example.com"'`
      → `"events": []`; то же по паролю `LegacyPass07!` и по строке `password`; то же для `pre-signup`
- [x] `aws iam get-role-policy` по обеим ролям → только `GetSecretValue` на ARN секрета
      (+ managed policy на ENI); никаких `*`
- [x] `aws ec2 describe-security-groups` → в SG RDS ingress только `my_ip/32` и SG Lambda
- [x] `git grep -i -e 'LegacyPass' -e <фрагмент пароля RDS>` → пусто; `git status` не показывает `tfstate`

### 8. Оформление и сдача (~30 мин)

- [x] README: раздел «Задание 2» — схема флоу миграции, таблица двух триггеров, что лежит в Secrets Manager,
      как устроен honeypot, стоимость, грабли
- [x] Отдельно и честно: почему managed login не годится для honeypot и почему после миграции
      надо возвращаться на SRP
- [ ] PR из `task2-triggers` в `main`, дождаться зелёного деплоя Pages — проверка: страница 200,
      новый таб работает
- [ ] Пингануть заказчика со ссылкой на демо и на README
- [ ] **Заказчик смотрит 19.08.2026** — значит инфраструктуру оставляем включённой, `terraform destroy`
      только после показа. Простой стоит ~$1,4 в сутки (RDS $0,019/ч + два ENI endpoint'а $0,01/ч
      + storage), это единицы долларов из $100 кредитов
- [ ] Перед показом: сбросить демо-состояние, чтобы миграцию было видно живьём —
      удалить из пула уже смигрировавших `userNN@example.com` (в legacy-БД они остаются).
      Иначе заказчик увидит обычный вход, а не миграцию
- [ ] Перед показом прогреть функцию одним `aws lambda invoke`: первый вход после простоя идёт
      3,7 с против 1,8 с на тёплой

### 9. `[опционально]` — только после сдачи шага 8

- [~] Unit-тесты обоих хэндлеров на `node:test` (мок `pg` и Secrets Manager) — быстро и заметно усиливает
- [ ] GitHub Actions: `terraform fmt -check` + `terraform validate` на PR
- [x] Ротация секрета, `manage_master_user_password`, RDS Proxy — назвать в README как
      «что сделать в проде», не делать

---

## Риски

| Риск | Что делать |
|---|---|
| **Cognito даёт триггеру 5 секунд** и это не настраивается ([docs](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-working-with-lambda-triggers.html), 18.08.2026). Холодный старт Lambda в VPC + чтение секрета + коннект к RDS + bcrypt могут не уложиться → первый вход упадёт | memory 1024 МБ, bcrypt cost 10, секрет и пул — вне handler, `connectionTimeoutMillis: 1500`. Перед демо прогреть функцию одним `aws lambda invoke`. Provisioned concurrency не берём — деньги. В README отметить как известное свойство |
| RDS недоступен на Free plan или съест кредиты | Проверяется на шаге 1 первым делом. Fallback по возрастанию усилий: внешний бесплатный Postgres (Neon) с кредами в том же секрете → mock-таблица DynamoDB (постановка её разрешает). Legacy-часть кода меняется в одном модуле |
| Пароль RDS лежит в `tfstate` открытым текстом | `*.tfstate*` в `.gitignore`, стейт локальный. В README — что в проде это S3 backend с шифрованием или `manage_master_user_password` |
| Lambda в VPC без интернета: любой сетевой вызов мимо VPC endpoint зависнет и сожрёт 5 секунд | В коде функций нет других внешних вызовов. Логи в CloudWatch работают без endpoint — их доставляет сам рантайм Lambda |
| `ALLOW_USER_PASSWORD_AUTH` шлёт пароль на API (внутри TLS) | Это неизбежно: SRP скрывает пароль и от Lambda тоже, миграция без него невозможна ([docs](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-import-using-lambda.html)). Доки прямо говорят: после миграции переходить на `USER_SRP_AUTH`. Записать в README |
| Honeypot заблокирует честную регистрацию через managed login, где `clientMetadata` не передаётся | Нет метаданных → пропускаем, `reason = 'metadata_invalid'` в логах. Проверить сценарий отдельно |
| Часы клиента врут → `form_rendered_at` из будущего | Отрицательный `elapsed` и `elapsed > 24 ч` считаем невалидными и не блокируем |
| Лимит 50 писем в сутки на весь аккаунт, сброс 09:00 UTC ([quotas](https://docs.aws.amazon.com/cognito/latest/developerguide/quotas.html), 18.08.2026) | Миграция писем не шлёт (`SUPPRESS`), тратит только обычная регистрация. Не гонять её десятками; для honeypot-проверок хватает `aws lambda invoke` |
| Пароли легаси-юзеров не проходят политику пула | Cognito **не** применяет свою политику при миграции — пользователь заедет с любым паролем. Наши сгенерированные пароли политику проходят, специально ничего не делаем; в README упомянуть |
| `aws_cognito_log_delivery_configuration` помечен в CHANGELOG провайдера как *«best effort, we ask for community help in testing»* — может не примениться | Если `apply` падает: fallback 1 — тот же ресурс через провайдер `awscc` (за ним CloudFormation-ресурс `AWS::Cognito::LogDeliveryConfiguration`), fallback 2 — `aws cognito-idp set-log-delivery-configuration` в `null_resource`, с честной пометкой в README, что этот кусок не декларативен |
| Кредиты кончатся → аккаунт закрывается | `terraform destroy` после демо, следить за Billing |
| **Сработало 18.08.2026:** AWS не принимает не-ASCII в `description` у security group и её правил — `apply` падает с `Character sets beyond ASCII are not supported` | Описания SG и правил пишем по-английски, русские пояснения — в комментариях HCL. В README как грабля |
| Домашний IP сменился → сев не подключается | `terraform apply -var my_ip=$(curl -s ifconfig.me)` |
| Демо задания 1 сломается из-за правок фронта | Старые env-переменные и OIDC-экран не трогаем, только добавляем. Перед PR проверить оба таба |

## Вопросы заказчику

1. **RDS PostgreSQL тратит кредиты (~$2,5 за 3 дня) и тянет за собой весь сетевой слой.** Из-за того, что RDS живёт
   в VPC, появляются: Lambda в VPC, три security group, interface VPC endpoint для Secrets Manager
   и риск не уложиться в 5-секундный лимит триггера на холодном старте. Цена вопроса — ~$2,5 за три дня
   ($0,019/ч инстанс + $0,137/ГБ-мес storage, Frankfurt). Внешний бесплатный PostgreSQL
   (Neon) убирает всё это целиком: Lambda вне VPC, ноль сетевого кода, $0, а требование
   «креды legacy-БД в Secrets Manager» выполняется так же — и для «старой БД вне AWS» это даже честнее.
   Что берём? — *Рабочее допущение: RDS (заказчик назвал PostgreSQL и ждёт AWS-native), после демо гасим.
   При первой же серьёзной пробуксовке — переключаемся на Neon, это правка в одном модуле.*
2. **50 пользователей вместо 100k** — подтверждено в чате, нагрузочную проверку не делаем.
   — *Рабочее допущение: демо-масштаб, в README отметить, что триггер масштабируется без изменений.*
3. **Honeypot требует свою форму** — managed login не передаёт `clientMetadata`. Значит в демо появляется
   вторая, самописная форма рядом с hosted UI задания 1. — *Рабочее допущение: делаем так.*
4. **Где смотреть демо** — публичный GitHub Pages, как в задании 1? — *Рабочее допущение: да,
   плюс localhost для полного флоу.*

## Дальше (следующие задания)

Заказчик о третьем задании не говорил. Наиболее вероятные продолжения — Pre token generation
(кастомные claims), федерация с Google, перевод пула на SES со своим доменом. Ничего из этого заранее
не делаем: критерий — скорость.

## История ревью

### 18.08.2026 (скил `plan-review`, сразу после составления)

- **[блокер]** Сквозная проверка появлялась только после фронтенда (шаг 6) → в шаг 5 добавлен
  end-to-end через CLI (`initiate-auth USER_PASSWORD_AUTH`, `sign-up --client-metadata`), он закрывает
  почти все критерии приёмки, и перед шагом 6 поставлен гейт. Фронтенд честно назван витриной:
  в техтребованиях постановки его нет.
- **[дефект]** Критерий «каждая строка логов парсится `JSON.parse`» был невыполним: платформенные
  `START/END/REPORT` — текст → в шаг 3 добавлен `logging_config { log_format = "JSON" }`, критерий уточнён.
- **[дефект]** Требование постановки №6 (инициализация вне handler) не имело проверяемого критерия →
  добавлен: в логах тёплого вызова нет записи `init`, `duration_ms` меньше.
- **[дефект]** Не был назван рантайм Lambda → `nodejs22.x`.
- **[дефект]** `aws_db_subnet_group` отсутствовал: полагаться на группу `default` нельзя, `apply` бы
  упал на создании RDS → добавлен в шаг 1.
- **[дефект]** Pre-signup-функция не была явно вынесена из VPC — тащила бы за собой ENI, лишние права
  и риск 5 секунд → в шаг 4 добавлено «вне VPC, только права на логи».
- **[дефект]** `aws_cognito_log_delivery_configuration` в CHANGELOG провайдера помечен как best-effort →
  добавлен риск с двумя fallback (`awscc`, CLI в `null_resource`).
- **[дефект]** Имя лог-группы для Cognito было произвольным → `/aws/vendedlogs/cognito/<pool>`, как
  требуют доки при большой resource-policy.
- **[дефект]** `admin-get-user` в критерии шёл без `--user-pool-id` — команда не запустилась бы.
- **[дефект]** Версия Terraform `>= 1.9` была взята из головы → заменена на «любая актуальная»,
  ограничение оставлено только на версию провайдера (>= 6.5.0, проверено по CHANGELOG).
- **[улучшение]** Вопрос про RDS переформулирован: показано, что весь сетевой слой (Lambda в VPC,
  3 SG, VPC endpoint, риск 5 секунд) существует только из-за RDS, и назван fallback на внешний Postgres.
- **[улучшение]** В шаг 6 добавлена ловушка: клиент AWS SDK в браузере создаётся без `credentials`.
- **[улучшение]** В шаг 4 добавлено, что миграция не проходит через pre sign-up — чтобы не искать
  несуществующий конфликт триггеров.
- **отклонено:** выносить unit-тесты в основной объём — их нет в постановке, остаются в шаге 9.
- **отклонено:** RDS Proxy как «правильный» пулинг — стоит денег, а постановка требует именно
  инициализации вне handler, что и сделано.
- **отклонено:** import пула из задания 1 в Terraform — работающее демо ценнее галочки «весь аккаунт в IaC».
- **чисто:** потерянных требований постановки не найдено (все 12 явных пунктов есть в критериях
  приёмки и шагах); порядок шагов после правки блокера претензий не вызывает; статусы `[x]`
  отсутствуют — план новый.

### 18.08.2026, второй проход — проверка того, что в первом было взято на веру

- **[дефект]** Цена RDS стояла как «не проверено, ориентир ~$0,02/ч» → достал официальный прайс-фид
  (`b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/rds/...`, тот же источник, что у калькулятора):
  `db.t4g.micro` PostgreSQL Single-AZ во Frankfurt — **$0,019/ч**, storage gp3 Single-AZ — **$0,137/ГБ-мес**.
  Итог по демо уточнён: **~$2,5 за три дня**, а не «единицы долларов».
- **[дефект]** Рантайм `nodejs22.x` был выбран по привычке → по таблице поддерживаемых рантаймов
  свежий GA — **`nodejs24.x`** (deprecation 30.04.2028), он же совпадает с локальным Node 24.
  `nodejs20.x` уже deprecated (30.04.2026) — если бы взяли его, Lambda не дала бы создать функцию.
- **[улучшение]** Ловушка «SDK в браузере без credentials» была утверждением без ссылки → подтверждена
  официальным списком unauthenticated-операций (`SignUp`, `ConfirmSignUp`, `ResendConfirmationCode`,
  `ForgotPassword`, `InitiateAuth`) с прямой цитатой; отдельно отмечено, что `RespondToAuthChallenge`
  авторизуется `Session`-токеном.
- **проверено, правок не потребовалось:** `user_pool_tier` (значения `LITE` / `ESSENTIALS` / `PLUS`),
  вложенные `lambda_config.user_migration` и `lambda_config.pre_sign_up`, `username_attributes`,
  `auto_verified_attributes` — существуют в `aws_cognito_user_pool` ровно с такими именами;
  `logging_config { log_format, application_log_level, system_log_level }` в `aws_lambda_function`
  тоже совпадает с докой провайдера дословно.
