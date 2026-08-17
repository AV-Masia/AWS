import type { AuthProviderProps } from 'react-oidc-context'
import { WebStorageStateStore } from 'oidc-client-ts'

const env = import.meta.env

export const cognito = {
  region: env.VITE_COGNITO_REGION as string | undefined,
  userPoolId: env.VITE_COGNITO_USER_POOL_ID as string | undefined,
  clientId: env.VITE_COGNITO_CLIENT_ID as string | undefined,
  // Вида https://<prefix>.auth.<region>.amazoncognito.com — без слэша на конце
  domain: (env.VITE_COGNITO_DOMAIN as string | undefined)?.replace(/\/$/, ''),
  redirectUri: (env.VITE_REDIRECT_URI as string | undefined) ?? window.location.origin,
}

/** Чего не хватает в .env.local — показываем на экране, а не падаем молча. */
export const missingConfig = (
  [
    ['VITE_COGNITO_REGION', cognito.region],
    ['VITE_COGNITO_USER_POOL_ID', cognito.userPoolId],
    ['VITE_COGNITO_CLIENT_ID', cognito.clientId],
    ['VITE_COGNITO_DOMAIN', cognito.domain],
  ] as const
)
  .filter(([, value]) => !value)
  .map(([name]) => name)

export const isConfigured = missingConfig.length === 0

/**
 * Authorization code + PKCE — стандартный flow для SPA.
 * PKCE включается автоматически при response_type=code.
 */
export const oidcConfig: AuthProviderProps = {
  authority: `https://cognito-idp.${cognito.region}.amazonaws.com/${cognito.userPoolId}`,
  client_id: cognito.clientId ?? '',
  redirect_uri: cognito.redirectUri,
  response_type: 'code',
  // Только то, что реально нужно: openid — обязателен для OIDC, email — для отображения
  // пользователя. profile в app client не разрешён и не нужен: пул собирает лишь email,
  // так что имя/фамилия в токене всё равно были бы пустыми.
  scope: 'openid email',
  // Иначе сессия теряется при перезагрузке страницы
  userStore: new WebStorageStateStore({ store: window.localStorage }),
  // Убираем ?code=...&state=... из адресной строки после возврата из Cognito
  onSigninCallback: () => {
    window.history.replaceState({}, document.title, window.location.pathname)
  },
}

/**
 * Cognito не реализует OIDC end_session_endpoint, поэтому разлогин —
 * ручной редирект на его /logout. Перед вызовом нужен auth.removeUser().
 */
export function signOutRedirect() {
  const params = new URLSearchParams({
    client_id: cognito.clientId ?? '',
    logout_uri: cognito.redirectUri,
  })
  window.location.href = `${cognito.domain}/logout?${params.toString()}`
}
