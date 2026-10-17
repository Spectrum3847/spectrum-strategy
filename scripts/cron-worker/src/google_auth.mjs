const TOKEN_URL = 'https://oauth2.googleapis.com/token';

const TOKEN_TIMEOUT_MS = 10_000;
const SCOPE = 'https://www.googleapis.com/auth/datastore';
const TOKEN_LIFETIME_SECONDS = 3600;

const EARLY_REFRESH_SECONDS = 60;

const CLOCK_SKEW_SECONDS = 30;

const tokenCache = new Map();

const inflightMints = new Map();

function base64UrlEncodeBytes(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlEncodeJson(value) {
  return base64UrlEncodeBytes(new TextEncoder().encode(JSON.stringify(value)));
}

function pemToBytes(pem) {
  const clean = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const binary = atob(clean);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

async function importPrivateKey(pem) {
  return crypto.subtle.importKey(
    'pkcs8',
    pemToBytes(pem).buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

async function signServiceAccountJwt(
  serviceAccount,
  { scope = SCOPE, audience = TOKEN_URL, nowSeconds } = {},
) {
  const now = nowSeconds ?? Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: serviceAccount.client_email,
    scope,
    aud: audience,
    iat: now - CLOCK_SKEW_SECONDS,
    exp: now + TOKEN_LIFETIME_SECONDS,
  };
  const signingInput = `${base64UrlEncodeJson(header)}.${base64UrlEncodeJson(claims)}`;

  const key = await importPrivateKey(serviceAccount.private_key);
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput),
  );
  return { jwt: `${signingInput}.${base64UrlEncodeBytes(new Uint8Array(signature))}`, claims };
}

async function getAccessToken(serviceAccount, { fetchImpl = fetch, nowSeconds } = {}) {
  const now = nowSeconds ?? Math.floor(Date.now() / 1000);
  const key = serviceAccount.client_email;

  const cached = tokenCache.get(key);
  if (cached && cached.expiresAt - now > EARLY_REFRESH_SECONDS) {
    return cached.token;
  }

  const existingMint = inflightMints.get(key);
  if (existingMint) return existingMint;

  const mint = mintAccessToken(serviceAccount, { fetchImpl, now }).finally(() => {
    inflightMints.delete(key);
  });
  inflightMints.set(key, mint);
  return mint;
}

async function mintAccessToken(serviceAccount, { fetchImpl, now }) {
  const { jwt } = await signServiceAccountJwt(serviceAccount, { nowSeconds: now });
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TOKEN_TIMEOUT_MS);
  let res;
  try {
    res = await fetchImpl(TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      }),
      signal: ctl.signal,
    });
  } finally {
    clearTimeout(timer);
  }
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`Google token exchange failed: HTTP ${res.status} ${text}`);
  }
  const data = await res.json();
  tokenCache.set(serviceAccount.client_email, {
    token: data.access_token,
    expiresAt: now + (data.expires_in ?? TOKEN_LIFETIME_SECONDS),
  });
  return data.access_token;
}

function clearTokenCacheForTests() {
  tokenCache.clear();
  inflightMints.clear();
}

const CUSTOM_TOKEN_AUDIENCE =
  'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit';
const CUSTOM_TOKEN_LIFETIME_SECONDS = 3600;

async function mintCustomToken(serviceAccount, uid, { nowSeconds } = {}) {
  const now = nowSeconds ?? Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const iat = now - CLOCK_SKEW_SECONDS;
  const claims = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: CUSTOM_TOKEN_AUDIENCE,
    iat,

    exp: iat + CUSTOM_TOKEN_LIFETIME_SECONDS,
    uid,
  };
  const signingInput = `${base64UrlEncodeJson(header)}.${base64UrlEncodeJson(claims)}`;
  const key = await importPrivateKey(serviceAccount.private_key);
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64UrlEncodeBytes(new Uint8Array(signature))}`;
}

export {
  getAccessToken,
  signServiceAccountJwt,
  mintCustomToken,
  clearTokenCacheForTests,
  SCOPE,
  TOKEN_URL,
};
