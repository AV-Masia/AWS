/**
 * Cognito Define Auth Challenge trigger: управляет ходом CUSTOM_AUTH для
 * phone-OTP логина Korzinka (тестовый эталонный пул, см.
 * korzinka/docs/keycloak-migration/CHANGELOG.md).
 *
 * Одна попытка challenge за раз, максимум 3 попытки — после этого
 * failAuthentication, чтобы не позволять бесконечный перебор кода.
 */

const MAX_ATTEMPTS = 3

export const handler = async (event) => {
  const session = event.request.session || []

  if (session.length === 0) {
    event.response.issueTokens = false
    event.response.failAuthentication = false
    event.response.challengeName = 'CUSTOM_CHALLENGE'
    return event
  }

  const last = session[session.length - 1]

  if (last.challengeName === 'CUSTOM_CHALLENGE' && last.challengeResult === true) {
    event.response.issueTokens = true
    event.response.failAuthentication = false
    return event
  }

  if (session.length >= MAX_ATTEMPTS) {
    event.response.issueTokens = false
    event.response.failAuthentication = true
    return event
  }

  event.response.issueTokens = false
  event.response.failAuthentication = false
  event.response.challengeName = 'CUSTOM_CHALLENGE'
  return event
}
