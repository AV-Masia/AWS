/**
 * Cognito Create Auth Challenge trigger — генерирует OTP-код для CUSTOM_AUTH.
 *
 * ТЕСТОВЫЙ СТЕНД: реальная отправка SMS не реализована (это дорого и не
 * нужно для проверки миграции) — код всегда фиксированный, задаётся через
 * MOCK_OTP_CODE (по умолчанию тот же '123456', что и в мок-OTP на стороне
 * Keycloak, см. AuthConfig.mockOtpCode в приложении Korzinka). НЕ переносить
 * это поведение в прод — там нужна настоящая интеграция с SMS-провайдером.
 */

const MOCK_OTP_CODE = process.env.MOCK_OTP_CODE || '123456'

export const handler = async (event) => {
  console.log(
    JSON.stringify({
      event: 'otp_issued_mock',
      phone: event.request.userAttributes?.phone_number,
      note: 'test stand — no real SMS sent, code is fixed via MOCK_OTP_CODE',
    }),
  )

  event.response.publicChallengeParameters = {}
  event.response.privateChallengeParameters = { answer: MOCK_OTP_CODE }
  event.response.challengeMetadata = 'MOCK_OTP'

  return event
}
