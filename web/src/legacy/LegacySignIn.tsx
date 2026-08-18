import { useState } from 'react'
import { decodeJwt, signIn, type Tokens } from './cognito'

/**
 * Вход пользователя, которого в Cognito нет — он есть только в старой PostgreSQL.
 * Первый вход проходит через триггер миграции, дальше пользователь живёт в Cognito.
 */
export function LegacySignIn() {
  // Подставлен пользователь, которого ещё нет в Cognito, — иначе демо покажет
  // обычный вход вместо миграции. Уже смигрировавших видно в консоли пула
  const [email, setEmail] = useState('user12@example.com')
  const [password, setPassword] = useState('LegacyPass12!')
  const [busy, setBusy] = useState(false)
  const [elapsed, setElapsed] = useState<number | null>(null)
  const [tokens, setTokens] = useState<Tokens | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function submit(event: React.FormEvent) {
    event.preventDefault()
    setBusy(true)
    setError(null)
    setTokens(null)

    const started = performance.now()
    try {
      setTokens(await signIn(email.trim().toLowerCase(), password))
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setElapsed(Math.round(performance.now() - started))
      setBusy(false)
    }
  }

  const claims = tokens ? decodeJwt(tokens.idToken) : null

  return (
    <section>
      <p className="muted">
        В старой базе 50 пользователей: <code>user01@example.com</code> … <code>user50@example.com</code>,
        пароль <code>LegacyPassNN!</code> (номер совпадает с логином). В Cognito их нет — до первого входа.
      </p>
      <p className="hint">
        Эта форма никуда не редиректит: пароль уходит прямо на API Cognito, а тот спрашивает Lambda.
        Триггер висит на пуле, а не на форме, поэтому тот же легаси-пользователь въедет и через
        страницу входа Cognito на третьей вкладке.
      </p>

      <form onSubmit={submit}>
        <label>
          Email
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        </label>
        <label>
          Пароль из старой системы
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
        </label>
        <button type="submit" disabled={busy}>
          {busy ? 'Проверяем в старой базе…' : 'Войти'}
        </button>
      </form>

      {error && (
        <>
          <h2>Отказ</h2>
          <pre className="error">{error}</pre>
          <p className="muted">
            Так выглядит неверный пароль: Cognito отвечает <code>NotAuthorizedException</code>,
            и профиль в пуле не создаётся. Причина отказа (нет такого пользователя или не совпал
            хэш) остаётся только в логах Lambda.
          </p>
        </>
      )}

      {tokens && claims && (
        <>
          <h2>Вход выполнен{elapsed !== null && <span className="muted"> · {elapsed} мс</span>}</h2>
          <p className="email">{String(claims.email ?? '—')}</p>
          <p className="muted">
            Пароль не менялся и не сбрасывался. Профиль в Cognito создан триггером миграции:
            <code>email_verified</code> уже <code>true</code>, а <code>name</code> перенесён из старой базы.
            Повторный вход этого пользователя в старую базу уже не пойдёт.
          </p>

          <table className="claims">
            <tbody>
              {Object.entries(claims).map(([key, value]) => (
                <tr key={key}>
                  <th>{key}</th>
                  <td>{typeof value === 'object' ? JSON.stringify(value) : String(value)}</td>
                </tr>
              ))}
            </tbody>
          </table>

          <details>
            <summary>Сырой ID-токен</summary>
            <pre className="token">{tokens.idToken}</pre>
          </details>
        </>
      )}
    </section>
  )
}
