const encoder = new TextEncoder();

const RECORD_SIZE = 4096;
const VAPID_LIFETIME_SECONDS = 12 * 60 * 60;
const PUSH_TIMEOUT_MS = 8_000;

const PUSH_HOSTS = ['fcm.googleapis.com', 'web.push.apple.com'];
const PUSH_HOST_SUFFIXES = [
  '.push.services.mozilla.com',
  '.push.apple.com',
  '.notify.windows.com',
];

function b64urlEncode(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

function b64urlDecode(text) {
  const base64 = text.replaceAll('-', '+').replaceAll('_', '/');
  const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), '=');
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

function concat(...parts) {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

function isAllowedPushEndpoint(endpoint) {
  let url;
  try {
    url = new URL(endpoint);
  } catch {
    return false;
  }
  if (url.protocol !== 'https:') return false;
  const host = url.hostname;
  return PUSH_HOSTS.includes(host) || PUSH_HOST_SUFFIXES.some((s) => host.endsWith(s));
}

async function hkdf(salt, ikm, info, bytes) {
  const key = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt, info },
    key,
    bytes * 8,
  );
  return new Uint8Array(bits);
}

async function generateSenderKey() {
  const pair = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, [
    'deriveBits',
  ]);
  const publicRaw = new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey));
  return { privateKey: pair.privateKey, publicRaw };
}

async function encryptPayload(plaintext, { p256dh, auth }, { salt, senderKey } = {}) {
  const uaPublic = b64urlDecode(p256dh);
  const authSecret = b64urlDecode(auth);
  if (uaPublic.length !== 65 || uaPublic[0] !== 4) throw new Error('bad p256dh key');
  if (authSecret.length !== 16) throw new Error('bad auth secret');

  const sender = senderKey ?? (await generateSenderKey());
  const uaKey = await crypto.subtle.importKey(
    'raw',
    uaPublic,
    { name: 'ECDH', namedCurve: 'P-256' },
    false,
    [],
  );
  const shared = new Uint8Array(
    await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey }, sender.privateKey, 256),
  );

  const keyInfo = concat(encoder.encode('WebPush: info\0'), uaPublic, sender.publicRaw);
  const ikm = await hkdf(authSecret, shared, keyInfo, 32);
  const messageSalt = salt ?? crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(messageSalt, ikm, encoder.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(messageSalt, ikm, encoder.encode('Content-Encoding: nonce\0'), 12);

  const aesKey = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['encrypt']);

  const record = concat(plaintext, Uint8Array.of(2));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, aesKey, record),
  );

  const header = new Uint8Array(21);
  header.set(messageSalt, 0);
  new DataView(header.buffer).setUint32(16, RECORD_SIZE);
  header[20] = sender.publicRaw.length;
  return concat(header, sender.publicRaw, ciphertext);
}

function createVapid({ publicKey, privateKey, subject }) {
  const publicRaw = b64urlDecode(publicKey);
  let signingKey;
  const tokens = new Map();

  async function key() {
    signingKey ??= crypto.subtle.importKey(
      'jwk',
      {
        kty: 'EC',
        crv: 'P-256',
        d: privateKey,
        x: b64urlEncode(publicRaw.slice(1, 33)),
        y: b64urlEncode(publicRaw.slice(33, 65)),
      },
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['sign'],
    );
    return signingKey;
  }

  async function authorization(audience, nowMs) {
    let token = tokens.get(audience);
    if (!token) {
      const part = (value) => b64urlEncode(encoder.encode(JSON.stringify(value)));
      const unsigned =
        `${part({ typ: 'JWT', alg: 'ES256' })}.` +
        part({
          aud: audience,
          exp: Math.floor(nowMs / 1000) + VAPID_LIFETIME_SECONDS,
          sub: subject,
        });

      const signature = await crypto.subtle.sign(
        { name: 'ECDSA', hash: 'SHA-256' },
        await key(),
        encoder.encode(unsigned),
      );
      token = `${unsigned}.${b64urlEncode(new Uint8Array(signature))}`;
      tokens.set(audience, token);
    }
    return `vapid t=${token}, k=${publicKey}`;
  }

  return { authorization };
}

async function sendWebPush({ fetchImpl, vapid, subscription, payload, nowMs, ttl = 3600 }) {
  if (!isAllowedPushEndpoint(subscription.endpoint)) return { outcome: 'gone', status: 0 };

  let body;
  try {
    body = await encryptPayload(encoder.encode(JSON.stringify(payload)), subscription);
  } catch {
    return { outcome: 'gone', status: 0 };
  }

  const audience = new URL(subscription.endpoint).origin;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), PUSH_TIMEOUT_MS);
  try {
    const res = await fetchImpl(subscription.endpoint, {
      method: 'POST',
      headers: {
        Authorization: await vapid.authorization(audience, nowMs),
        'Content-Encoding': 'aes128gcm',
        'Content-Type': 'application/octet-stream',
        TTL: String(ttl),
        Urgency: 'high',
      },
      body,
      redirect: 'manual',
      signal: ctl.signal,
    });
    if (res.status >= 200 && res.status < 300) return { outcome: 'sent', status: res.status };
    if (res.status === 404 || res.status === 410) return { outcome: 'gone', status: res.status };
    if (res.status === 429 || res.status >= 500) return { outcome: 'retry', status: res.status };
    return { outcome: 'rejected', status: res.status };
  } catch {
    return { outcome: 'retry', status: 0 };
  } finally {
    clearTimeout(timer);
  }
}

export {
  b64urlDecode,
  b64urlEncode,
  createVapid,
  encryptPayload,
  isAllowedPushEndpoint,
  sendWebPush,
};
