/**
 * Вход легаси-пользователя тем же путём, каким это делает браузер:
 * InitiateAuth USER_PASSWORD_AUTH через SDK, без AWS-ключей.
 *
 * Нужен для двух вещей: диагностика («дело в приложении или в Cognito?»)
 * и прогрев функции перед демо — первый вход после простоя идёт дольше.
 *
 * Запуск:
 *   COGNITO_CLIENT_ID=<client> node signin-probe.mjs user30@example.com 'LegacyPass30!'
 */
import { CognitoIdentityProviderClient, InitiateAuthCommand } from '@aws-sdk/client-cognito-identity-provider'

const [email, password] = process.argv.slice(2)

if (!email || !password) {
  console.error("usage: node signin-probe.mjs <email> '<password>'")
  process.exit(2)
}

const CLIENT_ID = process.env.COGNITO_CLIENT_ID
if (!CLIENT_ID) {
  console.error('нужен COGNITO_CLIENT_ID (terraform output user_pool_client_id)')
  process.exit(2)
}

const cognito = new CognitoIdentityProviderClient({ region: process.env.AWS_REGION ?? 'eu-central-1' })

const started = Date.now()

try {
  const res = await cognito.send(
    new InitiateAuthCommand({
      ClientId: CLIENT_ID,
      AuthFlow: 'USER_PASSWORD_AUTH',
      AuthParameters: { USERNAME: email, PASSWORD: password },
    }),
  )

  const idToken = res.AuthenticationResult?.IdToken
  if (!idToken) {
    console.log(`ЧЕЛЛЕНДЖ вместо токенов: ${res.ChallengeName}`)
  } else {
    const claims = JSON.parse(Buffer.from(idToken.split('.')[1], 'base64url').toString('utf8'))
    console.log(`ВХОД OK за ${Date.now() - started} мс`)
    console.log(`  email:          ${claims.email}`)
    console.log(`  email_verified: ${claims.email_verified}`)
    console.log(`  name:           ${claims.name ?? '(нет)'}`)
    console.log(`  sub:            ${claims.sub}`)
  }
} catch (error) {
  console.log(`ОТКАЗ за ${Date.now() - started} мс: ${error.name}: ${error.message}`)
}
