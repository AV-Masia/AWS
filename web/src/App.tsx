import { useEffect, useState } from 'react'
import { useAuth } from 'react-oidc-context'
import { cognito, isConfigured, missingConfig, signOutRedirect } from './authConfig'
import { LegacyDemo } from './legacy/LegacyDemo'
import { SignUpForm } from './legacy/SignUpForm'
import './auth-ui.css'

function Setup() {
  return (
    <main className="card">
      <h1>Нужен конфиг Cognito</h1>
      <p>
        Скопируй <code>.env.example</code> в <code>.env.local</code> и заполни значениями из{' '}
        <code>terraform output</code>. Не хватает:
      </p>
      <ul>
        {missingConfig.map((name) => (
          <li key={name}>
            <code>{name}</code>
          </li>
        ))}
      </ul>
      <p className="muted">После правки .env.local перезапусти dev-сервер.</p>
    </main>
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

/** Вход на странице Cognito: OIDC Authorization code + PKCE. */
function HostedUiSignIn() {
  const auth = useAuth()

  if (auth.isLoading) return <p>Загрузка…</p>

  if (auth.error) {
    return (
      <section>
        <h2>Ошибка авторизации</h2>
        <pre className="error">{auth.error.message}</pre>
        <p className="muted">
          Частые причины: <code>redirect_mismatch</code> — callback URL в app client не совпадает
          с <code>{cognito.redirectUri}</code> посимвольно; <code>invalid_scope</code> — запрошенный
          scope не разрешён в app client.
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
        <h2>Вход на странице Cognito</h2>
        <p className="muted">
          Приложение отправляет пользователя на домен Cognito, тот сам показывает форму, обрабатывает
          регистрацию, коды подтверждения и восстановление пароля, а возвращает подписанный токен.
          Пароль в наше приложение не попадает никогда — в этом и смысл выноса аутентификации в IDP.
        </p>
        <p className="hint">
          Authorization code + PKCE: приложение заранее генерирует случайный verifier, отправляет
          в Cognito его хэш, а код меняет на токены, предъявив оригинал. Перехваченный код без
          verifier бесполезен — для SPA это обязательная практика, потому что секрет клиента
          в браузере спрятать негде.
        </p>
        <button type="button" onClick={() => void auth.signinRedirect()}>
          Войти через Cognito
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
  { id: 'migration', label: 'Вход из старой базы', hint: 'триггер User Migration' },
  { id: 'signup', label: 'Регистрация', hint: 'триггер Pre Sign-up, honeypot' },
  { id: 'hosted', label: 'Страница входа Cognito', hint: 'OIDC code + PKCE' },
] as const

type TabId = (typeof TABS)[number]['id']

function App() {
  const auth = useAuth()
  const [tab, setTab] = useState<TabId>('migration')

  // После возврата с редиректа показываем результат, а не форму миграции
  useEffect(() => {
    if (auth.isAuthenticated) setTab('hosted')
  }, [auth.isAuthenticated])

  if (!isConfigured) return <Setup />

  return (
    <main className="card">
      <h1>AWS Cognito: миграция без сброса паролей и защита от ботов</h1>
      <p className="muted">
        Один User Pool, поднятый Terraform, и три способа войти в него. Первые два — свои формы
        приложения, они нужны для Lambda-триггеров; третий — готовая страница входа Cognito.
      </p>

      <nav className="tabs">
        {TABS.map(({ id, label, hint }) => (
          <button
            key={id}
            type="button"
            className={tab === id ? 'tab active' : 'tab'}
            onClick={() => setTab(id)}
            title={hint}
          >
            {label}
          </button>
        ))}
      </nav>

      {tab === 'migration' && <LegacyDemo />}
      {tab === 'signup' && (
        <section>
          <h2>Регистрация с невидимой защитой от ботов</h2>
          <SignUpForm />
        </section>
      )}
      {tab === 'hosted' && <HostedUiSignIn />}

      <p className="hint">
        Пул <code>{cognito.userPoolId}</code>, регион <code>{cognito.region}</code>. Оба Lambda-триггера
        висят на этом же пуле, поэтому вход из старой базы работает и здесь, и на странице Cognito.
      </p>
    </main>
  )
}

export default App
