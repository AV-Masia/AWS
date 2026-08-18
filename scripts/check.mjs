/**
 * Проверяет пару email/пароль по legacy-базе — та же логика, что потом в Lambda.
 * Нужен, чтобы убедиться: хэши в базе рабочие, и дело не в них, если миграция упадёт.
 *
 * Запуск:  node check.mjs user07@example.com 'LegacyPass07!'
 */
import bcrypt from 'bcryptjs'
import { connect } from './legacy-db.mjs'

const [email, password] = process.argv.slice(2)

if (!email || !password) {
  console.error("usage: node check.mjs <email> '<password>'")
  process.exit(2)
}

const client = await connect()

try {
  const { rows } = await client.query('select password_hash from legacy_users where email = $1', [email])

  if (rows.length === 0) {
    console.log('false (user not found)')
    process.exit(1)
  }

  console.log(await bcrypt.compare(password, rows[0].password_hash))
} finally {
  await client.end()
}
