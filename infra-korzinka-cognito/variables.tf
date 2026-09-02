variable "region" {
  description = "Регион AWS — совпадает с прод-пулом Korzinka (eu-north-1)"
  type        = string
  default     = "eu-north-1"
}

variable "project" {
  description = "Префикс имён и тег для ресурсов этого тестового стенда"
  type        = string
  default     = "korzinka-cognito-test"
}

variable "mobile_redirect_uri" {
  description = "Redirect URI мобильного приложения — совпадает с текущим Cognito-клиентом и Keycloak-стендом"
  type        = string
  default     = "myapp://callback"
}

variable "mock_otp_code" {
  description = "Фиксированный OTP-код для create-auth-challenge (тестовый стенд, реальный SMS не отправляется) — совпадает с AuthConfig.mockOtpCode в приложении"
  type        = string
  default     = "123456"
}

# Тот же Google Cloud проект, что зарегистрирован в консоли AWS для текущего
# Cognito Hosted UI прод-пула Korzinka (см. README приложения).
variable "google_idp_client_id" {
  description = "Google OAuth client_id для входа через Google на Hosted UI"
  type        = string
  sensitive   = true
}

variable "google_idp_client_secret" {
  description = "Google OAuth client_secret для входа через Google на Hosted UI"
  type        = string
  sensitive   = true
}
