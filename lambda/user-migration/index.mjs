/**
 * Cognito User Migration trigger.
 *
 * Срабатывает, когда пользователь пытается войти, а в пуле его ещё нет.
 * Функция проверяет пароль по «старой» базе и, если он верный, отдаёт Cognito
 * атрибуты пользователя со статусом CONFIRMED — Cognito сам создаёт профиль
 * с тем же паролем. Пользователь ничего не замечает, сбрасывать пароль не нужно.
 *
 * Про логи. В event приходит открытый пароль (event.request.password), поэтому
 * событие целиком не логируется никогда — доки AWS предупреждают об этом прямым
 * текстом. Email тоже не пишем: вместо него — необратимый псевдо-ID.
 *
 * Про 5 секунд. Cognito ждёт ответ от триггера максимум 5 секунд, и это значение
 * изменить нельзя. Поэтому чтение секрета и пул соединений создаются на уровне
 * модуля: между вызовами тёплой функции они переиспользуются, и в бюджет попадает
 * только SQL-запрос плюс сравнение bcrypt.
 */
import { Logger } from '@aws-lambda-powertools/logger'
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager'
import bcrypt from 'bcryptjs'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import pg from 'pg'

const logger = new Logger({ serviceName: 'user-migration' })

// ──────────────────────────────────────────────────────────────────────────────
// Инициализация вне handler: выполняется один раз за холодный старт
// ──────────────────────────────────────────────────────────────────────────────
const initStarted = Date.now()

const SECRET_ID = process.env.LEGACY_DB_SECRET
const RDS_CA = readFileSync(new URL('./rds-global-bundle.pem', import.meta.url), 'utf8')

const secretsManager = new SecretsManagerClient({})
const { SecretString } = await secretsManager.send(new GetSecretValueCommand({ SecretId: SECRET_ID }))
const secret = JSON.parse(SecretString)

const pool = new pg.Pool({
  host: secret.host,
  port: Number(secret.port),
  database: secret.dbname,
  user: secret.username,
  password: secret.password,
  // Сертификат RDS проверяем по официальному CA-бандлу, а не отключаем проверку
  ssl: { ca: RDS_CA },
  // Больше двух соединений одному контейнеру не нужно: Cognito зовёт функцию
  // синхронно и по одному событию за раз
  max: 2,
  connectionTimeoutMillis: 1500,
  idleTimeoutMillis: 60_000,
})

logger.info('cold start init complete', {
  event_id: 'init',
  secret_loaded: true,
  pool_created: true,
  init_ms: Date.now() - initStarted,
})

// ──────────────────────────────────────────────────────────────────────────────

/**
 * Необратимая метка пользователя для логов: по ней можно связать записи между
 * собой, но нельзя восстановить email. Соль — ID пула, чтобы одинаковые адреса
 * в разных пулах давали разные метки.
 */
function pseudoId(userName, userPoolId) {
  return createHash('sha256').update(`${userPoolId}:${userName}`).digest('hex').slice(0, 12)
}

async function findLegacyUser(email) {
  const { rows } = await pool.query(
    'select email, password_hash, full_name from legacy_users where email = $1',
    [email],
  )
  return rows[0]
}

/** Атрибуты, которые Cognito запишет в новый профиль. */
function migratedAttributes(user) {
  return {
    email: user.email,
    // Адрес уже подтверждён в старой системе — второй раз пользователя не мучаем
    email_verified: 'true',
    ...(user.full_name ? { name: user.full_name } : {}),
  }
}

export const handler = async (event, context) => {
  logger.addContext(context)

  const started = Date.now()
  const email = String(event.userName ?? '').trim().toLowerCase()
  const log = {
    event_id: 'user_migration',
    triggerSource: event.triggerSource,
    userPoolId: event.userPoolId,
    clientId: event.callerContext?.clientId,
    userRef: pseudoId(email, event.userPoolId),
  }

  try {
    if (event.triggerSource === 'UserMigration_Authentication') {
      const user = await findLegacyUser(email)

      if (!user) {
        logger.info('sign-in rejected', { ...log, outcome: 'not_found', duration_ms: Date.now() - started })
        throw new Error('Bad credentials')
      }

      if (!(await bcrypt.compare(event.request.password ?? '', user.password_hash))) {
        logger.info('sign-in rejected', { ...log, outcome: 'bad_password', duration_ms: Date.now() - started })
        throw new Error('Bad credentials')
      }

      event.response.userAttributes = migratedAttributes(user)
      // CONFIRMED — иначе Cognito потребует сброс пароля при первом входе,
      // а вся задача как раз в том, чтобы этого не произошло
      event.response.finalUserStatus = 'CONFIRMED'
      // Приветственное письмо не нужно: для пользователя ничего не изменилось
      event.response.messageAction = 'SUPPRESS'
      event.response.desiredDeliveryMediums = ['EMAIL']

      logger.info('user migrated', { ...log, outcome: 'migrated', duration_ms: Date.now() - started })
      return event
    }

    if (event.triggerSource === 'UserMigration_ForgotPassword') {
      // В этом сценарии пароля в событии нет — только ищем пользователя,
      // чтобы Cognito знал, куда отправить код сброса
      const user = await findLegacyUser(email)

      if (!user) {
        logger.info('reset rejected', { ...log, outcome: 'not_found', duration_ms: Date.now() - started })
        throw new Error('User not found')
      }

      event.response.userAttributes = migratedAttributes(user)
      event.response.messageAction = 'SUPPRESS'

      logger.info('user migrated for password reset', { ...log, outcome: 'migrated_for_reset', duration_ms: Date.now() - started })
      return event
    }

    logger.warn('unsupported trigger source', { ...log, outcome: 'unsupported' })
    throw new Error('Unsupported trigger source')
  } catch (error) {
    // Сообщение ошибки Cognito показывает пользователю, поэтому оно нейтральное.
    // Причина остаётся в логах выше — без пароля и без email.
    logger.error('migration failed', { ...log, reason: error.message, duration_ms: Date.now() - started })
    throw error
  }
}
