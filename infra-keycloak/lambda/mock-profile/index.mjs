// Мок backend-профиля для проверки JWT-авторайзера Keycloak на API Gateway
// (см. api_mock.tf). Валидация токена (подпись/issuer/audience/exp) делает
// сам API Gateway HTTP API до вызова этой функции — сюда долетают только уже
// проверенные запросы, claims из токена доступны в requestContext.authorizer.
export const handler = async (event) => {
  // Lambda REQUEST authorizer (keycloak-authorizer) кладёт проверенные claims
  // сюда, а не в requestContext.authorizer.jwt.claims — issuer Keycloak
  // на http, нативный JWT-authorizer API Gateway такой не принимает
  // (см. api_mock.tf).
  const claims = event.requestContext?.authorizer?.lambda ?? {};

  const body = {
    userId: claims.sub ?? 'unknown',
    email: claims.email ?? null,
    phone: claims.preferred_username ?? claims.phone_number ?? null,
    isProfileComplete: true,
    name: 'Test',
    lastName: 'User',
    photo: null,
  };

  return {
    statusCode: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
};
