// Lambda REQUEST authorizer для API Gateway HTTP API.
//
// Нативный встроенный JWT-authorizer API Gateway требует issuer с HTTPS
// (делает OIDC discovery по https) — наш Keycloak сидит на ALB без домена и
// сертификата, поэтому issuer только http://. AWS отвечает "Invalid issuer:
// Issuer is not a valid URL for JWT Authorizer" на любой http-issuer. Эта
// функция — обходной путь: та же проверка (issuer/audience/exp/подпись по
// JWKS Keycloak), но выполненная вручную, без ограничения на схему.
import crypto from 'node:crypto';
import http from 'node:http';

const ISSUER = process.env.KEYCLOAK_ISSUER;
const AUDIENCE = process.env.EXPECTED_AUDIENCE;
const JWKS_URL = `${ISSUER}/protocol/openid-connect/certs`;

let cachedJwks = null;
let cachedAt = 0;

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    http
      .get(url, (res) => {
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            reject(e);
          }
        });
      })
      .on('error', reject);
  });
}

async function getJwks() {
  const now = Date.now();
  if (cachedJwks && now - cachedAt < 5 * 60 * 1000) return cachedJwks;
  cachedJwks = await fetchJson(JWKS_URL);
  cachedAt = now;
  return cachedJwks;
}

function base64UrlDecode(str) {
  return Buffer.from(str.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

const deny = { isAuthorized: false };

export const handler = async (event) => {
  try {
    const authHeader =
      event.headers?.authorization ?? event.headers?.Authorization;
    if (!authHeader?.startsWith('Bearer ')) return deny;

    const token = authHeader.slice('Bearer '.length);
    const [headerB64, payloadB64, sigB64] = token.split('.');
    if (!headerB64 || !payloadB64 || !sigB64) return deny;

    const header = JSON.parse(base64UrlDecode(headerB64).toString('utf8'));
    const payload = JSON.parse(base64UrlDecode(payloadB64).toString('utf8'));

    if (payload.iss !== ISSUER) return deny;

    const aud = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
    if (!aud.includes(AUDIENCE) && payload.azp !== AUDIENCE) return deny;

    if (!payload.exp || Date.now() / 1000 >= payload.exp) return deny;

    const jwks = await getJwks();
    const jwk = jwks.keys.find((k) => k.kid === header.kid);
    if (!jwk) return deny;

    const publicKey = crypto.createPublicKey({ key: jwk, format: 'jwk' });
    const signedData = Buffer.from(`${headerB64}.${payloadB64}`);
    const signature = base64UrlDecode(sigB64);

    const verified = crypto.verify(
      'RSA-SHA256',
      signedData,
      publicKey,
      signature,
    );
    if (!verified) return deny;

    return {
      isAuthorized: true,
      context: {
        sub: payload.sub ?? '',
        preferred_username: payload.preferred_username ?? '',
        email: payload.email ?? '',
      },
    };
  } catch (_) {
    return deny;
  }
};
