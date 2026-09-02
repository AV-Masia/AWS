/**
 * Мост миграции Korzinka Cognito -> Keycloak.
 *
 * Критерий переноса — номер телефона (см. korzinka/docs/keycloak-migration/
 * MIGRATION.md, решение от 2026-09-01). Эта функция — единственная часть
 * моста, которой физически нужен доступ к Cognito: она ищет пользователя
 * по phone_number в исходном (legacy) пуле и, если находит, отдаёт его
 * sub — Keycloak-провижининг (см. AuthService._ensureKeycloakTestUser в
 * приложении) кладёт этот sub в атрибут legacy_cognito_sub нового
 * Keycloak-пользователя, чтобы backend впоследствии мог связать историю
 * заказов со старым Cognito-аккаунтом.
 *
 * ТЕСТОВЫЙ СТЕНД: вызывается напрямую из мобильного приложения через
 * Function URL с shared-secret заголовком — так же, как и admin_cli
 * provisioning (см. предупреждение в AWS/infra-keycloak/realm.tf). Для
 * прода это должно быть за настоящим backend, не за публичным URL с
 * секретом в APK.
 *
 * Пул, в котором ищем, задаётся переменной окружения LEGACY_USER_POOL_ID —
 * сейчас это наш тестовый Cognito-пул (эталон, см.
 * AWS/infra-korzinka-cognito), а не прод-пул Korzinka (недоступен нам
 * напрямую). При реальной миграции значение нужно будет заменить на прод.
 */

import {
  CognitoIdentityProviderClient,
  ListUsersCommand,
} from '@aws-sdk/client-cognito-identity-provider'

const client = new CognitoIdentityProviderClient({})
const LEGACY_USER_POOL_ID = process.env.LEGACY_USER_POOL_ID
const SHARED_SECRET = process.env.LOOKUP_SHARED_SECRET

function json(statusCode, body) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }
}

export const handler = async (event) => {
  const providedSecret = event.headers?.['x-lookup-secret'] ?? event.headers?.['X-Lookup-Secret']
  if (!SHARED_SECRET || providedSecret !== SHARED_SECRET) {
    return json(401, { error: 'unauthorized' })
  }

  let phoneNumber
  try {
    const body = JSON.parse(event.body ?? '{}')
    phoneNumber = body.phoneNumber
  } catch {
    return json(400, { error: 'invalid_json_body' })
  }

  if (!phoneNumber || typeof phoneNumber !== 'string') {
    return json(400, { error: 'phoneNumber_required' })
  }

  const escaped = phoneNumber.replace(/"/g, '\\"')
  const result = await client.send(
    new ListUsersCommand({
      UserPoolId: LEGACY_USER_POOL_ID,
      Filter: `phone_number = "${escaped}"`,
      Limit: 1,
    }),
  )

  const user = result.Users?.[0]
  if (!user) {
    return json(200, { found: false })
  }

  const sub = user.Attributes?.find((a) => a.Name === 'sub')?.Value
  return json(200, {
    found: true,
    legacyCognitoSub: sub,
    userStatus: user.UserStatus,
  })
}
