/**
 * Прямые вызовы API Cognito из браузера.
 *
 * Клиент создаётся БЕЗ credentials: SignUp, ConfirmSignUp и InitiateAuth —
 * публичные (unauthenticated) операции, подписи ключами AWS они не требуют.
 * Если начать прокидывать креды, сборка полезет искать их в браузере и упадёт.
 *
 * Почему здесь USER_PASSWORD_AUTH, а не SRP, как в задании 1: триггеру миграции
 * нужен сам пароль, чтобы проверить его в старой базе. SRP скрывает пароль
 * от всех, включая нашу Lambda. После миграции пользователей правильно
 * переходить на SRP — так прямо сказано в документации AWS.
 */
import {
  CognitoIdentityProviderClient,
  ConfirmSignUpCommand,
  InitiateAuthCommand,
  SignUpCommand,
} from '@aws-sdk/client-cognito-identity-provider'
import { legacyPool } from './config'

const client = new CognitoIdentityProviderClient({ region: legacyPool.region })

export type Tokens = {
  idToken: string
  accessToken: string
  expiresIn: number
}

export async function signIn(email: string, password: string): Promise<Tokens> {
  const res = await client.send(
    new InitiateAuthCommand({
      ClientId: legacyPool.clientId,
      AuthFlow: 'USER_PASSWORD_AUTH',
      AuthParameters: { USERNAME: email, PASSWORD: password },
    }),
  )

  const result = res.AuthenticationResult
  if (!result?.IdToken) {
    throw new Error(`Cognito вернул челлендж вместо токенов: ${res.ChallengeName ?? 'неизвестный'}`)
  }

  return {
    idToken: result.IdToken,
    accessToken: result.AccessToken ?? '',
    expiresIn: result.ExpiresIn ?? 0,
  }
}

/**
 * Регистрация. honeypot и formRenderedAt уходят в ClientMetadata — единственный
 * способ передать свои данные в pre-signup триггер. Страница входа Cognito
 * этого не умеет, поэтому для honeypot нужна своя форма.
 */
export async function signUp(params: {
  email: string
  password: string
  honeypot: string
  formRenderedAt: number
}): Promise<{ codeSentTo: string | undefined }> {
  const res = await client.send(
    new SignUpCommand({
      ClientId: legacyPool.clientId,
      Username: params.email,
      Password: params.password,
      UserAttributes: [{ Name: 'email', Value: params.email }],
      ClientMetadata: {
        phone_confirm: params.honeypot,
        form_rendered_at: String(params.formRenderedAt),
      },
    }),
  )

  return { codeSentTo: res.CodeDeliveryDetails?.Destination }
}

export async function confirmSignUp(email: string, code: string): Promise<void> {
  await client.send(
    new ConfirmSignUpCommand({
      ClientId: legacyPool.clientId,
      Username: email,
      ConfirmationCode: code,
    }),
  )
}

/** Разбор JWT без библиотек: подпись здесь не проверяем, токен только показываем. */
export function decodeJwt(token: string): Record<string, unknown> {
  const payload = token.split('.')[1]
  const json = atob(payload.replace(/-/g, '+').replace(/_/g, '/'))
  return JSON.parse(decodeURIComponent(escape(json)))
}
