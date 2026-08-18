import { cognito } from '../authConfig'
import { LegacySignIn } from './LegacySignIn'

/**
 * Задание 2, вход: миграция без сброса пароля.
 * Регистрация с honeypot вынесена в отдельную вкладку — она про другой триггер.
 */
export function LegacyDemo() {
  return (
    <section>
      <h2>Вход пользователя из старой базы</h2>
      <LegacySignIn />

      <p className="hint">
        Пул <code>{cognito.userPoolId}</code>. Пароль уходит на API Cognito (внутри TLS) — это условие
        работы триггера миграции: SRP скрыл бы пароль и от Lambda тоже. Когда все переедут,
        штатным флоу становится SRP, а этот можно выключить.
      </p>
    </section>
  )
}
