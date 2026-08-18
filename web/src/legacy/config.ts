/**
 * Конфиг пула из задания 2 — того, что поднят Terraform и с двумя Lambda-триггерами.
 * Пул задания 1 живёт отдельно в authConfig.ts и не трогается.
 */
const env = import.meta.env

export const legacyPool = {
  region: (env.VITE_COGNITO_V2_REGION as string | undefined) ?? (env.VITE_COGNITO_REGION as string | undefined),
  userPoolId: env.VITE_COGNITO_V2_USER_POOL_ID as string | undefined,
  clientId: env.VITE_COGNITO_V2_CLIENT_ID as string | undefined,
}

export const legacyMissingConfig = (
  [
    ['VITE_COGNITO_V2_USER_POOL_ID', legacyPool.userPoolId],
    ['VITE_COGNITO_V2_CLIENT_ID', legacyPool.clientId],
  ] as const
)
  .filter(([, value]) => !value)
  .map(([name]) => name)

export const isLegacyConfigured = legacyMissingConfig.length === 0
