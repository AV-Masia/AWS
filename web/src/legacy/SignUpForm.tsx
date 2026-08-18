import { useRef, useState } from 'react'
import { confirmSignUp, signUp } from './cognito'

/**
 * Регистрация с антибот-защитой без капчи.
 *
 * Два сигнала уходят в pre-signup триггер через ClientMetadata:
 *
 *   phone_confirm    — скрытое поле. Человек его не видит; автозаполнялка бота видит
 *                      и заполняет, потому что оно есть в разметке и похоже на телефон.
 *   form_rendered_at — момент отрисовки формы. Если от рендера до отправки прошло
 *                      меньше 1.5 секунд, человек не успел бы ничего набрать.
 *
 * Поле спрятано CSS, а не через type="hidden" и не через display:none в некоторых
 * реализациях: цель — чтобы бот его нашёл и заполнил, а человек не увидел и не задел
 * табом (отсюда tabIndex=-1 и aria-hidden).
 */
export function SignUpForm() {
  // Ref, а не state: значение нужно один раз на монтирование формы и не должно
  // сбрасываться на каждый ввод символа
  const formRenderedAt = useRef(Date.now())

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [honeypot, setHoneypot] = useState('')
  const [code, setCode] = useState('')
  const [stage, setStage] = useState<'form' | 'confirm' | 'done'>('form')
  const [sentTo, setSentTo] = useState<string | undefined>()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  /** Только для наглядности демо: показываем, сколько «видит» триггер. */
  const [lastElapsed, setLastElapsed] = useState<number | null>(null)

  async function submitSignUp(event: React.FormEvent) {
    event.preventDefault()
    setBusy(true)
    setError(null)
    setLastElapsed(Date.now() - formRenderedAt.current)

    try {
      const { codeSentTo } = await signUp({
        email: email.trim().toLowerCase(),
        password,
        honeypot,
        formRenderedAt: formRenderedAt.current,
      })
      setSentTo(codeSentTo)
      setStage('confirm')
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function submitCode(event: React.FormEvent) {
    event.preventDefault()
    setBusy(true)
    setError(null)

    try {
      await confirmSignUp(email.trim().toLowerCase(), code.trim())
      setStage('done')
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  /** Имитация бота: заполняем скрытое поле и отправляем форму мгновенно. */
  function actLikeBot() {
    setHoneypot('+7 999 000-00-00')
    setEmail(`bot${Date.now()}@example.com`)
    setPassword('BotPass123!')
    formRenderedAt.current = Date.now()
  }

  if (stage === 'done') {
    return (
      <section>
        <h2>Регистрация завершена</h2>
        <p className="muted">
          Адрес подтверждён кодом из письма. Этот пользователь создан прямо в Cognito, старая база
          для него не при чём — войти им можно любым из трёх способов.
        </p>
      </section>
    )
  }

  if (stage === 'confirm') {
    return (
      <section>
        <h2>Код из письма</h2>
        <p className="muted">
          Cognito отправил код на {sentTo ?? 'указанный адрес'}. Письмо приходит от{' '}
          <code>no-reply@verificationemail.com</code> — проверьте папку «Спам».
        </p>
        <form onSubmit={submitCode}>
          <label>
            Код подтверждения
            <input value={code} onChange={(e) => setCode(e.target.value)} required inputMode="numeric" />
          </label>
          <button type="submit" disabled={busy}>
            {busy ? 'Проверяем…' : 'Подтвердить'}
          </button>
        </form>
        {error && <pre className="error">{error}</pre>}
      </section>
    )
  }

  return (
    <section>
      <p className="muted">
        Обычная форма регистрации. Защита незаметна: ни капчи, ни галочек — конверсия не страдает.
      </p>

      <form onSubmit={submitSignUp}>
        <label>
          Email
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        </label>
        <label>
          Пароль
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            minLength={8}
          />
          <span className="hint">Минимум 8 символов, буквы разных регистров и цифра</span>
        </label>

        {/* Ловушка для ботов. Для человека невидима и недостижима табом. */}
        <div className="honeypot" aria-hidden="true">
          <label htmlFor="phone_confirm">Подтвердите телефон</label>
          <input
            id="phone_confirm"
            name="phone_confirm"
            type="text"
            tabIndex={-1}
            autoComplete="off"
            value={honeypot}
            onChange={(e) => setHoneypot(e.target.value)}
          />
        </div>

        <button type="submit" disabled={busy}>
          {busy ? 'Отправляем…' : 'Зарегистрироваться'}
        </button>
      </form>

      <button type="button" className="secondary" onClick={actLikeBot}>
        Прикинуться ботом
      </button>
      <p className="hint">
        Кнопка заполняет скрытое поле и обнуляет таймер формы — то есть делает ровно то, что делает бот.
        После неё жмите «Зарегистрироваться»: триггер ответит отказом.
      </p>

      {lastElapsed !== null && (
        <p className="muted">
          Последняя попытка: форма заполнялась <strong>{lastElapsed} мс</strong>
          {lastElapsed < 1500 ? ' — это меньше порога 1.5 с' : ' — порог 1.5 с пройден'}
          {honeypot !== '' && ', скрытое поле заполнено'}
        </p>
      )}

      {error && (
        <>
          <h2>Регистрация отклонена</h2>
          <pre className="error">{error}</pre>
          <p className="muted">
            Текст <code>Automated traffic detected</code> одинаков для обеих проверок — боту
            не подсказываем, на чём он попался. Что именно сработало (<code>honeypot_filled</code> или{' '}
            <code>too_fast</code>), видно только в логах CloudWatch.
          </p>
        </>
      )}
    </section>
  )
}
