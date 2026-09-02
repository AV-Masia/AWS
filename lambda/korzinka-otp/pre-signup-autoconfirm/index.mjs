/**
 * Cognito Pre Sign-up trigger — авто-подтверждение при самостоятельной
 * регистрации по номеру телефона.
 *
 * ТЕСТОВЫЙ СТЕНД: мобильное приложение (AuthService.sendOTP) на
 * UserNotFoundException само вызывает userPool.signUp(), а затем сразу
 * initiateAuth(CUSTOM_AUTH) — без отдельного шага confirmSignUp. Без
 * авто-подтверждения пользователь остался бы в UNCONFIRMED и CUSTOM_AUTH
 * бы не прошёл. В реальном проде подтверждение обычно и есть сам факт
 * успешного прохождения OTP, но так как OTP-проверка здесь замокана
 * (см. create-auth-challenge), подтверждаем сразу.
 */

export const handler = async (event) => {
  if (event.triggerSource === 'PreSignUp_SignUp') {
    event.response.autoConfirmUser = true
    event.response.autoVerifyPhone = true
  }
  return event
}
