import { useState } from 'react'
import { useAuth } from 'react-oidc-context'
import { cognito, isConfigured, missingConfig, signOutRedirect } from './authConfig'
import { LegacyDemo } from './legacy/LegacyDemo'
import './auth-ui.css'

function Setup() {
  return (
    <section>
      <h2>Нужен конфиг Cognito</h2>
      <p>
        Скопируй <code>.env.example</code> в <code>.env.local</code> и заполни значениями
        из созданного User Pool. Не хватает:
      </p>
      <ul>
        {missingConfig.map((name) => (
          <li key={name}>
            <code>{name}</code>
          </li>
        ))}
      </ul>
      <p className="muted">После правки .env.local перезапусти dev-сервер.</p>
    </section>
  )
}

function Claims({ claims }: { claims: Record<string, unknown> }) {
  return (
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
  )
}

/** Задание 1: вход на странице Cognito по OIDC Authorization code + PKCE. */
function OidcDemo() {
  const auth = useAuth()

  if (!isConfigured) return <Setup />

  if (auth.isLoading) return <p>Загрузка…</p>

  if (auth.error) {
    return (
      <section>
        <h2>Ошибка авторизации</h2>
        <pre className="error">{auth.error.message}</pre>
        <p className="muted">
          Частые причины: <code>redirect_mismatch</code> — callback URL в app client Cognito
          не совпадает с <code>{cognito.redirectUri}</code> посимвольно;{' '}
          <code>invalid_scope</code> — запрошенный scope не разрешён в app client
          (раздел App clients → Login pages → OpenID Connect scopes).
        </p>
        <button type="button" onClick={() => void auth.signinRedirect()}>
          Попробовать снова
        </button>
      </section>
    )
  }

  if (!auth.isAuthenticated) {
    return (
      <section>
        <p className="muted">
          Authorization code + PKCE: пароль вводится на домене Cognito, приложение его не видит
          никогда и получает только подписанный токен.
        </p>
        <button type="button" onClick={() => void auth.signinRedirect()}>
          Войти
        </button>
      </section>
    )
  }

  const profile = auth.user?.profile

  return (
    <section>
      <h2>Вход выполнен</h2>
      <p className="email">{String(profile?.email ?? '—')}</p>

      <h2>Claims из ID-токена</h2>
      <Claims claims={(profile ?? {}) as Record<string, unknown>} />

      <details>
        <summary>Сырой ID-токен</summary>
        <pre className="token">{auth.user?.id_token}</pre>
      </details>

      <button
        type="button"
        onClick={() => {
          void auth.removeUser().then(signOutRedirect)
        }}
      >
        Выйти
      </button>
    </section>
  )
}

const TABS = [
  { id: 'legacy', label: 'Задание 2: миграция и honeypot' },
  { id: 'oidc', label: 'Задание 1: логин через Cognito' },
] as const

function App() {
  // По умолчанию — задание 2: это то, что сдаётся сейчас
  const [tab, setTab] = useState<(typeof TABS)[number]['id']>('legacy')

  return (
    <main className="card">
      <h1>AWS Cognito: демо тестовых заданий</h1>

      <nav className="tabs">
        {TABS.map(({ id, label }) => (
          <button
            key={id}
            type="button"
            className={tab === id ? 'tab active' : 'tab'}
            onClick={() => setTab(id)}
          >
            {label}
          </button>
        ))}
      </nav>

      {tab === 'legacy' ? <LegacyDemo /> : <OidcDemo />}
    </main>
  )
}

export default App
