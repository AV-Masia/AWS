import { useState } from 'react'
import { isLegacyConfigured, legacyMissingConfig, legacyPool } from './config'
import { LegacySignIn } from './LegacySignIn'
import { SignUpForm } from './SignUpForm'

type Tab = 'signin' | 'signup'

/** Демо задания 2: миграция без сброса паролей и honeypot вместо капчи. */
export function LegacyDemo() {
  const [tab, setTab] = useState<Tab>('signin')

  if (!isLegacyConfigured) {
    return (
      <section>
        <h2>Нужен конфиг пула задания 2</h2>
        <p>Не хватает переменных:</p>
        <ul>
          {legacyMissingConfig.map((name) => (
            <li key={name}>
              <code>{name}</code>
            </li>
          ))}
        </ul>
        <p className="muted">
          Значения берутся из <code>terraform output</code> в папке <code>infra/</code>.
        </p>
      </section>
    )
  }

  return (
    <section>
      <div className="subtabs">
        <button
          type="button"
          className={tab === 'signin' ? 'subtab active' : 'subtab'}
          onClick={() => setTab('signin')}
        >
          Вход через миграцию
        </button>
        <button
          type="button"
          className={tab === 'signup' ? 'subtab active' : 'subtab'}
          onClick={() => setTab('signup')}
        >
          Регистрация с honeypot
        </button>
      </div>

      {tab === 'signin' ? <LegacySignIn /> : <SignUpForm />}

      <p className="hint">
        Пул <code>{legacyPool.userPoolId}</code>, регион <code>{legacyPool.region}</code>. Пароль
        уходит на API Cognito (внутри TLS) — это условие работы триггера миграции: SRP скрыл бы
        пароль и от Lambda тоже. После миграции пользователей штатный флоу — SRP.
      </p>
    </section>
  )
}
