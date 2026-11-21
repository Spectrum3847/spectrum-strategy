import { createFakeFirestore } from './fake_firestore.mjs';
import { privateKeyPem } from './fake_service_account.mjs';
import { b64urlDecode, b64urlEncode } from '../../src/webpush.mjs';
import { decodeFields } from '../../src/firestore.mjs';

const PROJECT = 'proj-firebase';
const PLATFORM = 'proj-platform';
const EVENT_KEY = '2026miket';
const NOW = Date.parse('2026-09-18T12:00:00Z');

const serviceAccount = (email) => JSON.stringify({ client_email: email, private_key: privateKeyPem });

async function vapidSecrets() {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
    'sign',
    'verify',
  ]);
  return {
    VAPID_PUBLIC_KEY: b64urlEncode(new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey))),
    VAPID_PRIVATE_KEY: (await crypto.subtle.exportKey('jwk', pair.privateKey)).d,
    VAPID_SUBJECT: 'mailto:push@example.test',
  };
}

const receivers = new Map();

async function subscriptionDoc(uid, endpoint) {
  const pair = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, [
    'deriveBits',
  ]);
  const doc = {
    uid,
    endpoint,
    p256dh: b64urlEncode(new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey))),
    auth: b64urlEncode(crypto.getRandomValues(new Uint8Array(16))),
    userAgent: 'test',
  };
  receivers.set(endpoint, { privateKey: pair.privateKey, doc });
  return doc;
}

async function hkdf(salt, ikm, info, bytes) {
  const key = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  return new Uint8Array(
    await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info }, key, bytes * 8),
  );
}

async function readPush(endpoint, body) {
  const { privateKey, doc } = receivers.get(endpoint);
  const text = new TextEncoder();
  const salt = body.slice(0, 16);
  const idLength = body[20];
  const senderPublic = body.slice(21, 21 + idLength);
  const ciphertext = body.slice(21 + idLength);
  const uaPublic = b64urlDecode(doc.p256dh);
  const senderKey = await crypto.subtle.importKey(
    'raw',
    senderPublic,
    { name: 'ECDH', namedCurve: 'P-256' },
    false,
    [],
  );
  const shared = new Uint8Array(
    await crypto.subtle.deriveBits({ name: 'ECDH', public: senderKey }, privateKey, 256),
  );
  const keyInfo = new Uint8Array([...text.encode('WebPush: info\0'), ...uaPublic, ...senderPublic]);
  const ikm = await hkdf(b64urlDecode(doc.auth), shared, keyInfo, 32);
  const cek = await hkdf(salt, ikm, text.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, text.encode('Content-Encoding: nonce\0'), 12);
  const aes = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['decrypt']);
  const record = new Uint8Array(
    await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce }, aes, ciphertext),
  );
  assertDelimiter(record.at(-1));
  return JSON.parse(new TextDecoder().decode(record.slice(0, -1)));
}

function assertDelimiter(byte) {
  if (byte !== 2) throw new Error(`last record delimiter is ${byte}, expected 2`);
}

async function buildPushEnv({
  rotations = [],
  subscriptions = {},
  state = {},
  playedThrough = 7,
  pushStatus = {},
  vapid = true,
  dryRun = false,
  profiles = {},
} = {}) {
  const fake = createFakeFirestore({
    [PROJECT]: {
      appConfig: {
        activeEvent: { eventKey: EVENT_KEY },
        apiKeys: { tba: 'tba-key' },
        shiftCronState: state,
      },
      scoutShifts: { [EVENT_KEY]: { rotations } },
      pushSubscriptions: subscriptions,
    },
  });

  const pushes = [];
  const patches = [];
  const profileReads = [];

  const fetchImpl = async (url, init = {}) => {
    const href = typeof url === 'string' ? url : url.toString();
    const method = init.method || 'GET';

    if (href === 'https://oauth2.googleapis.com/token') {
      return new Response(JSON.stringify({ access_token: 'token', expires_in: 3600 }));
    }
    if (href.includes('/documents/appConfig/shiftCronState') && method === 'PATCH') {
      patches.push(decodeFields(JSON.parse(init.body).fields));
      return new Response('{}');
    }
    if (href.includes(`/projects/${PROJECT}/databases/(default)/documents/userProfiles/`)) {

      const uid = decodeURIComponent(href.split('/userProfiles/')[1]);
      profileReads.push({ uid, authorization: init.headers?.Authorization });
      return new Response('{}', { status: profiles[uid] ?? 200 });
    }
    if (href.startsWith('https://www.thebluealliance.com/api/v3/event/')) {
      if (href.endsWith('/matches/simple')) {
        const matches = Array.from({ length: playedThrough }, (_, i) => ({
          comp_level: 'qm',
          match_number: i + 1,
          winning_alliance: 'red',
        }));
        return new Response(JSON.stringify(matches));
      }
      return new Response(JSON.stringify({ start_date: '2026-09-18', end_date: '2026-09-20' }));
    }
    if (href === 'https://slack.com/api/chat.postMessage') {
      return new Response(JSON.stringify({ ok: true }));
    }
    if (pushStatus[href] !== undefined || href.startsWith('https://fcm.googleapis.com/')) {
      pushes.push({ url: href, init });
      return new Response(null, { status: pushStatus[href] ?? 201 });
    }
    return fake.fetchImpl(href, init);
  };

  const env = {
    FIREBASE_SERVICE_ACCOUNT: serviceAccount('firebase@example.iam.gserviceaccount.com'),
    SPECTRUM_PLATFORM_SERVICE_ACCOUNT: serviceAccount('platform@example.iam.gserviceaccount.com'),
    SLACK_BOT_TOKEN: 'xoxb-test',
    FIREBASE_PROJECT: PROJECT,
    PLATFORM_PROJECT: PLATFORM,
    ALLOWED_ORIGINS: 'https://app.example.test',
    ...(vapid ? await vapidSecrets() : {}),
    fetchImpl,
    nowMs: NOW,
    ...(dryRun ? { DRY_RUN: '1' } : {}),
  };

  return { env, store: fake.store[PROJECT], pushes, patches, profileReads };
}

const fcm = (name) => `https://fcm.googleapis.com/fcm/send/${name}`;

export { EVENT_KEY, buildPushEnv, fcm, readPush, subscriptionDoc };
