/**
 * Подключение к legacy PostgreSQL по кредам из Secrets Manager.
 * Общий модуль для seed.mjs и check.mjs.
 *
 * Пароль в коде и в переменных окружения не появляется никогда: скрипт берёт его
 * из того же секрета, что и Lambda в проде.
 */
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'

const HERE = dirname(fileURLToPath(import.meta.url))

const REGION = process.env.AWS_REGION ?? 'eu-central-1'
const SECRET_ID = process.env.LEGACY_DB_SECRET ?? 'legacy-db/postgres'

/** RDS требует TLS (rds.force_ssl=1 в дефолтной группе параметров PostgreSQL). */
const RDS_CA = readFileSync(join(HERE, 'rds-global-bundle.pem'), 'utf8')

export async function getSecret() {
  const sm = new SecretsManagerClient({ region: REGION })
  const { SecretString } = await sm.send(new GetSecretValueCommand({ SecretId: SECRET_ID }))
  return JSON.parse(SecretString)
}

export async function connect() {
  const secret = await getSecret()

  const client = new pg.Client({
    host: secret.host,
    port: Number(secret.port),
    database: secret.dbname,
    user: secret.username,
    password: secret.password,
    // Сертификат сервера проверяем по официальному CA-бандлу RDS,
    // а не отключаем проверку — иначе TLS защищает только от пассивного слушателя
    ssl: { ca: RDS_CA },
  })

  await client.connect()
  return client
}
