/**
 * Локальные тесты honeypot-триггера: node --test test.mjs
 *
 * Зачем локально, а не через aws lambda invoke: проверка тайминга измеряет
 * миллисекунды, а сам AWS CLI стартует ~2 секунды — через него граничные случаи
 * не проверить. Здесь событие собирается прямо перед вызовом.
 */
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { handler } from './index.mjs'

const CONTEXT = { awsRequestId: 'local-test', functionName: 'pre-signup-local' }

function event({ clientMetadata, triggerSource = 'PreSignUp_SignUp' } = {}) {
  return {
    version: '1',
    triggerSource,
    region: 'eu-central-1',
    userPoolId: 'eu-central-1_TEST',
    userName: 'someone@example.com',
    callerContext: { awsSdkVersion: 'test', clientId: 'test-client' },
    request: {
      userAttributes: { email: 'someone@example.com' },
      ...(clientMetadata === undefined ? {} : { clientMetadata }),
    },
    response: { autoConfirmUser: false, autoVerifyEmail: false, autoVerifyPhone: false },
  }
}

const filledForm = (elapsedMs) => ({
  phone_confirm: '',
  form_rendered_at: String(Date.now() - elapsedMs),
})

test('заполненный honeypot блокирует регистрацию', async () => {
  await assert.rejects(
    handler(event({ clientMetadata: { ...filledForm(5000), phone_confirm: 'bot' } }), CONTEXT),
    /Automated traffic detected/,
  )
})

test('форма отправлена за 300 мс — блок', async () => {
  await assert.rejects(handler(event({ clientMetadata: filledForm(300) }), CONTEXT), /Automated traffic detected/)
})

test('1400 мс — всё ещё блок (чуть ниже границы)', async () => {
  // Ровно 1499 брать нельзя: пока тест доходит до handler, проходит ещё пара
  // миллисекунд, и проверка честно пропустит событие. Отсюда запас
  await assert.rejects(handler(event({ clientMetadata: filledForm(1400) }), CONTEXT), /Automated traffic detected/)
})

test('3 секунды на заполнение — пропускаем', async () => {
  const res = await handler(event({ clientMetadata: filledForm(3000) }), CONTEXT)
  assert.equal(res.response.autoConfirmUser, false)
})

test('часы клиента впереди серверных — не блокируем', async () => {
  // elapsed отрицательный: подделкой это не считаем, у людей врут часы
  const res = await handler(event({ clientMetadata: filledForm(-5000) }), CONTEXT)
  assert.equal(res.triggerSource, 'PreSignUp_SignUp')
})

test('форма висела открытой неделю — не блокируем', async () => {
  const res = await handler(event({ clientMetadata: filledForm(7 * 24 * 60 * 60 * 1000) }), CONTEXT)
  assert.equal(res.triggerSource, 'PreSignUp_SignUp')
})

test('метаданных нет вообще (managed login) — пропускаем', async () => {
  const res = await handler(event(), CONTEXT)
  assert.equal(res.triggerSource, 'PreSignUp_SignUp')
})

test('form_rendered_at не число — пропускаем, но не молча', async () => {
  const res = await handler(event({ clientMetadata: { phone_confirm: '', form_rendered_at: 'вчера' } }), CONTEXT)
  assert.equal(res.triggerSource, 'PreSignUp_SignUp')
})

test('пользователя создал администратор — проверки не применяются', async () => {
  const res = await handler(
    event({ triggerSource: 'PreSignUp_AdminCreateUser', clientMetadata: { phone_confirm: 'bot' } }),
    CONTEXT,
  )
  assert.equal(res.triggerSource, 'PreSignUp_AdminCreateUser')
})
