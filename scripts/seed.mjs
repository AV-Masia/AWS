/**
 * Создаёт схему «старой базы» и засеивает 50 пользователей с bcrypt-хэшами.
 *
 * Запуск:  node seed.mjs
 * Повторный запуск безопасен: ON CONFLICT DO NOTHING.
 *
 * Пароль пользователя NN — LegacyPassNN! (например LegacyPass07!).
 * Это тестовые данные для демо миграции, реальных людей за ними нет.
 */
import bcrypt from 'bcryptjs'
import { connect } from './legacy-db.mjs'

const USER_COUNT = 50
// 10 раундов — компромисс: так хэшируют в реальных приложениях, и проверка
// укладывается в 5-секундный лимит Cognito на Lambda-триггер
const BCRYPT_ROUNDS = 10

const SCHEMA = `
  create table if not exists legacy_users (
    email         text primary key,
    password_hash text        not null,
    full_name     text,
    created_at    timestamptz not null default now()
  )
`

function pad(n) {
  return String(n).padStart(2, '0')
}

const client = await connect()

try {
  await client.query(SCHEMA)

  let inserted = 0
  for (let i = 1; i <= USER_COUNT; i++) {
    const nn = pad(i)
    const email = `user${nn}@example.com`
    const hash = await bcrypt.hash(`LegacyPass${nn}!`, BCRYPT_ROUNDS)

    const res = await client.query(
      `insert into legacy_users (email, password_hash, full_name)
       values ($1, $2, $3)
       on conflict (email) do nothing`,
      [email, hash, `Legacy User ${nn}`],
    )
    inserted += res.rowCount
  }

  const { rows } = await client.query(
    `select count(*)::int as total,
            count(*) filter (where password_hash like '$2%')::int as bcrypt_hashes
       from legacy_users`,
  )

  console.log(`inserted now: ${inserted}`)
  console.log(`total in legacy_users: ${rows[0].total}, with bcrypt hashes: ${rows[0].bcrypt_hashes}`)
} finally {
  await client.end()
}
