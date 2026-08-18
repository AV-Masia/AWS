/**
 * Проверка pre-signup триггера через настоящий API Cognito.
 *
 * Зачем отдельный скрипт: через aws cli проверку тайминга не сделать — он сам
 * стартует несколько секунд, и Lambda видит «форму заполняли 3 секунды».
 * Здесь timestamp формируется в том же процессе, что и запрос, — как в браузере.
 *
 * Запуск:
 *   node signup-probe.mjs <email> <elapsed_ms> [honeypot]
 * Примеры:
 *   node signup-probe.mjs bot@example.com 200          # должно заблокировать: слишком быстро
 *   node signup-probe.mjs bot@example.com 5000 filled  # должно заблокировать: honeypot
 */
import { CognitoIdentityProviderClient, SignUpCommand } from '@aws-sdk/client-cognito-identity-provider'

const [email, elapsedArg, honeypot] = process.argv.slice(2)

if (!email || !elapsedArg) {
  console.error('usage: node signup-probe.mjs <email> <elapsed_ms> [honeypot]')
  process.exit(2)
}

const REGION = process.env.AWS_REGION ?? 'eu-central-1'
const CLIENT_ID = process.env.COGNITO_CLIENT_ID

if (!CLIENT_ID) {
  console.error('нужен COGNITO_CLIENT_ID (terraform output user_pool_client_id)')
  process.exit(2)
}

// Клиент без credentials: SignUp — публичная операция, подписи не требует
const cognito = new CognitoIdentityProviderClient({ region: REGION })

try {
  await cognito.send(
    new SignUpCommand({
      ClientId: CLIENT_ID,
      Username: email,
      Password: 'ProbePass2026!',
      UserAttributes: [{ Name: 'email', Value: email }],
      ClientMetadata: {
        phone_confirm: honeypot ?? '',
        form_rendered_at: String(Date.now() - Number(elapsedArg)),
      },
    }),
  )
  console.log('РЕГИСТРАЦИЯ ПРОШЛА (триггер пропустил)')
} catch (error) {
  console.log(`ОТКАЗ: ${error.name}: ${error.message}`)
}
