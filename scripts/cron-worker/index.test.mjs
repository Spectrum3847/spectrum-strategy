import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';

import worker, { runJob } from './src/index.mjs';
import { encodeFields, decodeFields } from './src/firestore.mjs';

const FIREBASE_PROJECT = 'proj-firebase';
const PLATFORM_PROJECT = 'proj-platform';
const EVENT_KEY = '2026miket';

function makeServiceAccountJson(email) {
  const { privateKey } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  });
  return JSON.stringify({ client_email: email, private_key: privateKey });
}

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), { status });
}

function docsBase(project) {
  return `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
}

function buildEnv({ state = {}, dryRun = false } = {}) {
  const rotationsDoc = {
    rotations: [{ uid: 'u1', name: 'Scouter 1', shifts: [{ startMatch: 10, endMatch: 15 }] }],
  };
  const tradeDoc = {
    eventKey: EVENT_KEY,
    status: 'pending',
    requesterUid: 'u1',
    targetUid: 'u2',
    requesterDisplayName: 'Alex',
    requesterBlock: { startMatch: 20, endMatch: 25 },
  };
  const platformUsers = [
    { id: 'p1', email: 'u1@example.com', slackId: 'U1SLACK' },
    { id: 'p2', email: 'u2@example.com', slackId: 'U2SLACK' },
  ];
  const userProfiles = [
    { id: 'u1', email: 'u1@example.com' },
    { id: 'u2', email: 'u2@example.com' },
  ];

  const slackCalls = [];
  const patches = [];
  const tbaCalls = [];

  const fetchImpl = async (url, init = {}) => {
    const href = typeof url === 'string' ? url : url.toString();
    const method = init.method || 'GET';

    if (href === 'https://oauth2.googleapis.com/token') {
      return jsonResponse(200, { access_token: `token-${Math.random()}`, expires_in: 3600 });
    }

    if (href === `${docsBase(FIREBASE_PROJECT)}/appConfig/activeEvent`) {
      return jsonResponse(200, { fields: encodeFields({ eventKey: EVENT_KEY }) });
    }
    if (href === `${docsBase(FIREBASE_PROJECT)}/scoutShifts/${EVENT_KEY}`) {
      return jsonResponse(200, { fields: encodeFields(rotationsDoc) });
    }
    if (href === `${docsBase(FIREBASE_PROJECT)}/appConfig/apiKeys`) {
      return jsonResponse(200, { fields: encodeFields({ tba: 'tba-key' }) });
    }
    if (href.startsWith(`${docsBase(FIREBASE_PROJECT)}/appConfig/shiftCronState`)) {
      if (method === 'PATCH') {
        patches.push(JSON.parse(init.body));
        return jsonResponse(200, {});
      }
      return jsonResponse(200, { fields: encodeFields(state) });
    }
    if (href === `${docsBase(FIREBASE_PROJECT)}:runQuery`) {
      return jsonResponse(200, [
        {
          document: {
            name: `projects/${FIREBASE_PROJECT}/databases/(default)/documents/shiftTrades/trade1`,
            fields: encodeFields(tradeDoc),
          },
        },
      ]);
    }
    if (href.startsWith(`${docsBase(FIREBASE_PROJECT)}/userProfiles`)) {
      return jsonResponse(200, {
        documents: userProfiles.map((p) => ({
          name: `projects/${FIREBASE_PROJECT}/databases/(default)/documents/userProfiles/${p.id}`,
          fields: encodeFields({ email: p.email }),
        })),
      });
    }
    if (href.startsWith(`${docsBase(PLATFORM_PROJECT)}/users`)) {
      return jsonResponse(200, {
        documents: platformUsers.map((u) => ({
          name: `projects/${PLATFORM_PROJECT}/databases/(default)/documents/users/${u.id}`,
          fields: encodeFields({ email: u.email, slackId: u.slackId }),
        })),
      });
    }

    if (
      href.startsWith('https://www.thebluealliance.com/api/v3/event/') &&
      href.endsWith('/matches/simple')
    ) {
      tbaCalls.push(href);
      const matches = Array.from({ length: 7 }, (_, i) => ({
        comp_level: 'qm',
        match_number: i + 1,
        winning_alliance: 'red',
      }));
      return jsonResponse(200, matches);
    }
    if (href.startsWith('https://www.thebluealliance.com/api/v3/event/') && href.endsWith('/simple')) {
      tbaCalls.push(href);
      return jsonResponse(200, { start_date: '2026-09-18', end_date: '2026-09-20' });
    }

    if (href === 'https://slack.com/api/chat.postMessage') {
      const body = JSON.parse(init.body);
      slackCalls.push(body);
      return jsonResponse(200, { ok: true });
    }

    throw new Error(`unexpected fetch in test: ${method} ${href}`);
  };

  const env = {
    FIREBASE_SERVICE_ACCOUNT: makeServiceAccountJson('firebase@example.iam.gserviceaccount.com'),
    SPECTRUM_PLATFORM_SERVICE_ACCOUNT: makeServiceAccountJson('platform@example.iam.gserviceaccount.com'),
    SLACK_BOT_TOKEN: 'xoxb-test',
    FIREBASE_PROJECT,
    PLATFORM_PROJECT,
    fetchImpl,
    nowMs: Date.parse('2026-09-18T12:00:00Z'),
    ...(dryRun ? { DRY_RUN: '1' } : {}),
  };

  return { env, slackCalls, patches, tbaCalls };
}

test('a run sends the shift-start DM and the trade-request DM, then writes dedupe state', async () => {
  const { env, slackCalls, patches } = buildEnv();
  const stats = await runJob(env, 'shift');

  assert.equal(stats.shiftDmed, 1);
  assert.equal(stats.tradeDmed, 1);
  assert.equal(slackCalls.length, 2);
  assert.deepEqual(
    slackCalls.map((c) => c.channel).sort(),
    ['U1SLACK', 'U2SLACK'],
  );
  const shiftDm = slackCalls.find((c) => c.channel === 'U1SLACK');
  assert.match(shiftDm.text, /matches 10-15/);
  const tradeDm = slackCalls.find((c) => c.channel === 'U2SLACK');
  assert.match(tradeDm.text, /Alex/);

  assert.equal(patches.length, 1);
  const patchedState = decodeFields(patches[0].fields);
  assert.equal(patchedState.dmedShifts[`${EVENT_KEY}:u1:10`], true);
  assert.equal(patchedState.dmedTrades.trade1, true);
});

test('a second run against the state the first run wrote sends nothing (dedupe)', async () => {
  const first = buildEnv();
  const firstStats = await runJob(first.env, 'shift');
  assert.equal(firstStats.shiftDmed + firstStats.tradeDmed, 2);
  const carriedState = decodeFields(first.patches[0].fields);

  const second = buildEnv({ state: carriedState });
  const secondStats = await runJob(second.env, 'shift');

  assert.equal(secondStats.shiftDmed, 0);
  assert.equal(secondStats.tradeDmed, 0);
  assert.equal(second.slackCalls.length, 0);
});

test('a dry run logs instead of sending and never writes state', async () => {
  const { env, slackCalls, patches } = buildEnv({ dryRun: true });
  const stats = await runJob(env, 'shift');

  assert.equal(stats.shiftDmed, 0);
  assert.equal(stats.tradeDmed, 0);
  assert.equal(slackCalls.length, 0);
  assert.equal(patches.length, 0);
});

test('missing secrets skip the run before any fetch', async () => {
  const env = {
    FIREBASE_PROJECT,
    PLATFORM_PROJECT,
    fetchImpl: async () => {
      throw new Error('should not fetch when secrets are missing');
    },
  };
  const result = await runJob(env, 'shift');
  assert.equal(result.skipped, 'missing-secrets');
  assert.deepEqual(result.missing, [
    'FIREBASE_SERVICE_ACCOUNT',
    'SPECTRUM_PLATFORM_SERVICE_ACCOUNT',
    'SLACK_BOT_TOKEN',
  ]);
});

test('no active event skips the run before any TBA or Slack call', async () => {
  const { env, slackCalls, tbaCalls } = buildEnv();
  const originalFetch = env.fetchImpl;
  env.fetchImpl = async (url, init) => {
    const href = typeof url === 'string' ? url : url.toString();
    if (href === `${docsBase(FIREBASE_PROJECT)}/appConfig/activeEvent`) {
      return jsonResponse(200, {});
    }
    return originalFetch(url, init);
  };

  const result = await runJob(env, 'shift');
  assert.equal(result.skipped, 'no-active-event');
  assert.equal(slackCalls.length, 0);
  assert.equal(tbaCalls.length, 0);
});

test('outside the event window the run skips before the trades query or any Slack call', async () => {
  const { env, slackCalls } = buildEnv();
  env.nowMs = Date.parse('2026-01-01T00:00:00Z');

  const result = await runJob(env, 'shift');
  assert.equal(result.skipped, 'outside-window');
  assert.equal(slackCalls.length, 0);
});

test('POST /run/shift needs the RUN_TOKEN header and then runs that job', async () => {
  const env = { RUN_TOKEN: 'secret-1' };
  const req = (method, token) =>
    new Request('https://worker.test/run/shift', {
      method,
      headers: token === undefined ? {} : { 'X-Run-Token': token },
    });

  assert.equal((await worker.fetch(req('GET', 'secret-1'), env)).status, 405);
  assert.equal((await worker.fetch(req('POST'), env)).status, 401);
  assert.equal((await worker.fetch(req('POST', 'secret-2'), env)).status, 401);
  assert.equal((await worker.fetch(req('POST', 'secret-1'), {})).status, 503);

  const res = await worker.fetch(req('POST', 'secret-1'), env);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.job, 'shift');
  assert.equal(body.result.skipped, 'missing-secrets');
});

test('unknown paths are 404 and the health route stays open', async () => {
  assert.equal((await worker.fetch(new Request('https://worker.test/'), {})).status, 200);
  assert.equal((await worker.fetch(new Request('https://worker.test/other'), {})).status, 404);

  assert.equal((await worker.fetch(new Request('https://worker.test/run'), {})).status, 404);
});
