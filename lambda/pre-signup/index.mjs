/**
 * Cognito Pre Sign-up trigger: защита формы регистрации от ботов без капчи.
 *
 * Две проверки, обе по данным из event.request.clientMetadata — их передаёт
 * фронтенд в параметре ClientMetadata вызова SignUp:
 *
 *   1. honeypot: скрытое поле phone_confirm. Человек его не видит и не заполняет,
 *      автозаполнялка бота — заполняет.
 *   2. тайминг: form_rendered_at — момент отрисовки формы. Если от рендера до
 *      сабмита прошло меньше 1.5 секунд, человек физически не успел бы ввести
 *      email и пароль.
 *
 * Текст ошибки в обоих случаях одинаковый: боту не подсказываем, какая именно
 * проверка его поймала. Различие остаётся в логах, в поле reason.
 *
 * В логи не попадают ни email, ни пароль — только решение и метаданные.
 * Функция работает вне VPC и не имеет доступа ни к базе, ни к секретам:
 * ей это не нужно, а меньше прав — меньше поверхность атаки.
 */
import { Logger } from '@aws-lambda-powertools/logger'

const logger = new Logger({ serviceName: 'pre-signup' })

/** Минимальное правдоподобное время заполнения формы. */
const MIN_FORM_FILL_MS = 1500

/** Метаданные старше суток считаем мусором, а не попыткой обмана. */
const MAX_PLAUSIBLE_AGE_MS = 24 * 60 * 60 * 1000

const BLOCK_MESSAGE = 'Automated traffic detected'

/**
 * @returns {{ decision: 'allow' | 'block', reason: string, elapsed_ms: number | null }}
 */
function evaluate(clientMetadata) {
  if (!clientMetadata || Object.keys(clientMetadata).length === 0) {
    // Регистрация не из нашей формы: managed login ClientMetadata не передаёт.
    // Блокировать нельзя — иначе сломаем штатный сценарий из задания 1.
    return { decision: 'allow', reason: 'metadata_absent', elapsed_ms: null }
  }

  if (String(clientMetadata.phone_confirm ?? '').trim() !== '') {
    return { decision: 'block', reason: 'honeypot_filled', elapsed_ms: null }
  }

  const renderedAt = Number(clientMetadata.form_rendered_at)
  if (!Number.isFinite(renderedAt)) {
    return { decision: 'allow', reason: 'timestamp_invalid', elapsed_ms: null }
  }

  const elapsed = Date.now() - renderedAt

  // Отрицательное значение — часы клиента впереди серверных; слишком большое —
  // форма висела открытой сутками. И то и другое не доказывает ботовость.
  if (elapsed < 0 || elapsed > MAX_PLAUSIBLE_AGE_MS) {
    return { decision: 'allow', reason: 'timestamp_implausible', elapsed_ms: elapsed }
  }

  if (elapsed < MIN_FORM_FILL_MS) {
    return { decision: 'block', reason: 'too_fast', elapsed_ms: elapsed }
  }

  return { decision: 'allow', reason: 'checks_passed', elapsed_ms: elapsed }
}

export const handler = async (event, context) => {
  logger.addContext(context)

  const log = {
    event_id: 'pre_signup',
    triggerSource: event.triggerSource,
    userPoolId: event.userPoolId,
    clientId: event.callerContext?.clientId,
  }

  // Проверяем только самостоятельную регистрацию. Пользователей, созданных
  // администратором (PreSignUp_AdminCreateUser), и первый вход федеративного
  // пользователя (PreSignUp_ExternalProvider) пропускаем без вопросов.
  if (event.triggerSource !== 'PreSignUp_SignUp') {
    logger.info('skipped: not a self sign-up', { ...log, decision: 'allow', reason: 'other_trigger_source' })
    return event
  }

  const { decision, reason, elapsed_ms } = evaluate(event.request?.clientMetadata)

  if (decision === 'block') {
    logger.warn('sign-up blocked', { ...log, decision, reason, elapsed_ms })
    throw new Error(BLOCK_MESSAGE)
  }

  logger.info('sign-up allowed', { ...log, decision, reason, elapsed_ms })
  return event
}
