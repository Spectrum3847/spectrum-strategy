import { test } from 'node:test';
import assert from 'node:assert/strict';

import worker, { runJob } from '../src/index.mjs';
import { CANARY_UID, CANARY_ENTRY_ID, classify } from '../src/crons/canary.mjs';
import { createFakeFirestore } from './support/fake_firestore.mjs';
import { privateKeyPem } from './support/fake_service_account.mjs';

const PROJECT = 'proj-firebase';

function serviceAccountJson() {
  return JSON.stringify({
    client_email: 'firebase@example.iam.gserviceaccount.com',
    private_key: privateKeyPem,
  });
}

function base64Url(obj) {
  return Buffer.from(JSON.stringify(obj))
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function fakeIdToken(aud) {
  return `header.${base64Url({ aud, sub: CANARY_UID })}.signature`;
}

const CANARY_ID_TOKEN = fakeIdToken(PROJECT);

function buildEnv({
  writeOutcome = 'success',
  exchangeStatus = 200,
  idTokenAud = PROJECT,
  profileSeed,
  seedScoutEntries,
  quotaOnProfileGet = false,
  nowMs = Date.parse('2026-09-22T12:00:00Z'),
} = {}) {
  const { fetchImpl: adminFirestoreFetch, store } = createFakeFirestore({
    [PROJECT]: {
      ...(profileSeed ? { userProfiles: profileSeed } : {}),
      ...(seedScoutEntries ? { scoutEntries: seedScoutEntries } : {}),
    },
  });
  const asUserCalls = [];
  const slackCalls = [];
  const issuedIdToken = fakeIdToken(idTokenAud);

  const fetchImpl = async (url, init = {}) => {
    const href = String(url);
    const method = init.method || 'GET';

    if (href === 'https://oauth2.googleapis.com/token') {
      return new Response(JSON.stringify({ access_token: 'admin-token', expires_in: 3600 }), {
        status: 200,
      });
    }
    if (href.includes('identitytoolkit.googleapis.com')) {
      if (exchangeStatus !== 200) {
        return new Response(
          JSON.stringify({ error: { code: exchangeStatus, message: 'INVALID_CUSTOM_TOKEN' } }),
          { status: exchangeStatus },
        );
      }
      return new Response(
        JSON.stringify({ idToken: issuedIdToken, localId: CANARY_UID }),
        { status: 200 },
      );
    }
    if (href === 'https://slack.com/api/chat.postMessage') {
      slackCalls.push(JSON.parse(init.body));
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }

    if (
      quotaOnProfileGet &&
      href.includes(`userProfiles/${CANARY_UID}`) &&
      method === 'GET'
    ) {
      return new Response(
        JSON.stringify({ error: { code: 429, status: 'RESOURCE_EXHAUSTED', message: 'Quota exceeded.' } }),
        { status: 429 },
      );
    }

    const auth = init.headers && init.headers.Authorization;
    if (auth === `Bearer ${issuedIdToken}`) {
      asUserCalls.push({ url: href, method, body: init.body ? JSON.parse(init.body) : undefined });
      if (writeOutcome === 'refused') {
        return new Response(
          JSON.stringify({
            error: { code: 403, message: 'Missing or insufficient permissions.', status: 'PERMISSION_DENIED' },
          }),
          { status: 403 },
        );
      }
      if (writeOutcome === 'broken400') {
        return new Response(
          JSON.stringify({ error: { code: 400, message: 'Invalid argument.', status: 'INVALID_ARGUMENT' } }),
          { status: 400 },
        );
      }
      if (writeOutcome === 'transient') {
        return new Response('bad gateway', { status: 502 });
      }
      if (writeOutcome === 'network') {
        throw new TypeError('fetch failed');
      }
      if (writeOutcome === 'cleanupNetwork' && method === 'DELETE') {
        throw new TypeError('fetch failed');
      }
      if (writeOutcome === 'cleanup5xx' && method === 'DELETE') {
        return new Response('bad gateway', { status: 502 });
      }
      return new Response('{}', { status: 200 });
    }

    return adminFirestoreFetch(href, init);
  };

  const env = {
    FIREBASE_SERVICE_ACCOUNT: serviceAccountJson(),
    FIREBASE_PROJECT: PROJECT,
    SLACK_BOT_TOKEN: 'xoxb-test',
    SLACK_STRATEGY_CHANNEL_ID: 'C-STRATEGY',
    fetchImpl,
    nowMs,
  };
  return { env, store, asUserCalls, slackCalls };
}

test('classify: 403 or PERMISSION_DENIED is refused', () => {
  assert.equal(classify(403, {}), 'refused');
  assert.equal(classify(400, { error: { status: 'PERMISSION_DENIED' } }), 'refused');
});

test('classify: no response (0), 429, and any 5xx are transient', () => {
  assert.equal(classify(0, {}), 'transient');
  assert.equal(classify(429, {}), 'transient');
  assert.equal(classify(500, {}), 'transient');
  assert.equal(classify(503, {}), 'transient');
});

test('classify: every other 4xx is broken, not transient', () => {
  assert.equal(classify(400, {}), 'broken');
  assert.equal(classify(401, {}), 'broken');
  assert.equal(classify(404, {}), 'broken');
});

test('a healthy run bootstraps the profile once, writes as the canary user, and cleans up', async () => {
  const { env, store, asUserCalls, slackCalls } = buildEnv({ writeOutcome: 'success' });

  const result = await runJob(env, 'canary');

  assert.equal(result.ok, true);
  assert.equal(result.failed, undefined, 'a healthy run reports no failures');
  assert.equal(slackCalls.length, 0, 'no alert on a healthy run');

  const profile = store[PROJECT].userProfiles[CANARY_UID];
  assert.ok(profile, 'the canary profile was bootstrapped');
  assert.deepEqual(profile.roles, ['scouter']);

  const writeCalls = asUserCalls.filter((c) => c.method === 'POST');
  assert.equal(writeCalls.length, 1);
  assert.equal(asUserCalls.filter((c) => c.method === 'DELETE').length, 1);
  assert.ok(asUserCalls.some((c) => c.url.includes(CANARY_ENTRY_ID)));
  assert.deepEqual(writeCalls[0].body.writes[0].currentDocument, { exists: false });
});

test('an already-bootstrapped profile is left alone', async () => {
  const { env, store } = buildEnv({
    writeOutcome: 'success',
    profileSeed: { [CANARY_UID]: { uid: CANARY_UID, displayName: 'Scouting canary', roles: ['scouter'] } },
  });

  const result = await runJob(env, 'canary');

  assert.equal(result.ok, true);

  assert.deepEqual(store[PROJECT].userProfiles[CANARY_UID].roles, ['scouter']);
});

test('repairs a canary profile that lost the scouter role, without touching its other fields', async () => {
  const { env, store } = buildEnv({
    writeOutcome: 'success',
    profileSeed: {
      [CANARY_UID]: {
        uid: CANARY_UID,
        displayName: 'Scouting canary',
        roles: ['viewer'],
        email: 'kept@example.com',
      },
    },
  });

  const result = await runJob(env, 'canary');

  assert.equal(result.ok, true);
  const profile = store[PROJECT].userProfiles[CANARY_UID];
  assert.ok(profile.roles.includes('scouter'), 'the scouter role was restored');
  assert.ok(profile.roles.includes('viewer'), 'the existing role was not removed');
  assert.equal(profile.email, 'kept@example.com', 'unrelated fields are untouched');
});

test('deletes any leftover canary document as the service account before writing, so every write is a create', async () => {
  const { env, store } = buildEnv({
    writeOutcome: 'success',
    seedScoutEntries: { [CANARY_ENTRY_ID]: { stale: true } },
  });

  const result = await runJob(env, 'canary');

  assert.equal(result.ok, true);
  assert.equal(
    Object.prototype.hasOwnProperty.call(store[PROJECT].scoutEntries || {}, CANARY_ENTRY_ID),
    false,
    'the leftover document is gone before the write',
  );
});

test('a rules refusal is loud: it fails the run and alerts the strategy Slack channel', async () => {
  const { env, slackCalls } = buildEnv({ writeOutcome: 'refused' });

  const result = await runJob(env, 'canary');

  assert.equal(result.refused, true);
  assert.ok(result.failed >= 1, 'a refusal counts as a run failure');
  assert.ok(result.failures.some((f) => f.includes('canary write')));

  assert.equal(slackCalls.length, 1);
  assert.equal(slackCalls[0].channel, 'C-STRATEGY');
  assert.match(slackCalls[0].text, /refused/);
  assert.match(slackCalls[0].text, /firestore\.rules/);
});

test('without SLACK_BOT_TOKEN/SLACK_STRATEGY_CHANNEL_ID a refusal still fails the run, just silently', async () => {
  const { env, slackCalls } = buildEnv({ writeOutcome: 'refused' });
  delete env.SLACK_BOT_TOKEN;
  delete env.SLACK_STRATEGY_CHANNEL_ID;

  const result = await runJob(env, 'canary');

  assert.equal(result.refused, true);
  assert.ok(result.failed >= 1);
  assert.equal(slackCalls.length, 0);
});

test('a write refused with something other than 403/PERMISSION_DENIED is broken, loudly, not silently transient', async () => {
  const { env, slackCalls } = buildEnv({ writeOutcome: 'broken400' });

  const result = await runJob(env, 'canary');

  assert.equal(result.broken, true);
  assert.equal(result.stage, 'write');
  assert.ok(result.failed >= 1);
  assert.equal(slackCalls.length, 1);
  assert.match(slackCalls[0].text, /broken/);

  assert.match(slackCalls[0].text, /not a rules refusal/);
});

test('a token exchange the endpoint rejects is loud, since the canary can then prove nothing', async () => {
  const { env, asUserCalls, slackCalls } = buildEnv({ exchangeStatus: 400 });

  const result = await runJob(env, 'canary');

  assert.equal(result.broken, true);
  assert.ok(result.failed >= 1, 'a canary that cannot sign in must fail the run');
  assert.equal(asUserCalls.length, 0, 'no write is attempted without an ID token');
  assert.equal(slackCalls.length, 1);
  assert.match(slackCalls[0].text, /broken/);
});

test('an ID token minted for the wrong Firebase project is broken, not silently trusted', async () => {
  const { env, asUserCalls, slackCalls } = buildEnv({ idTokenAud: 'some-other-project' });

  const result = await runJob(env, 'canary');

  assert.equal(result.broken, true);
  assert.equal(result.stage, 'token-exchange');
  assert.equal(asUserCalls.length, 0, 'no write is attempted with a mismatched-audience token');
  assert.equal(slackCalls.length, 1);
  assert.match(slackCalls[0].text, /audience/);
});

test('a transient write failure is quiet on Slack but still fails the run (this job is critical)', async () => {
  const { env, slackCalls } = buildEnv({ writeOutcome: 'transient' });

  const result = await runJob(env, 'canary');

  assert.equal(result.skipped, 'transient');
  assert.ok(result.failed >= 1, 'a critical job must not report a quiet success on a transient skip');
  assert.equal(slackCalls.length, 0, 'a transient failure must not page anyone');
});

test('an exchange endpoint outage is quiet on Slack but still fails the run', async () => {
  const { env, slackCalls } = buildEnv({ exchangeStatus: 503 });

  const result = await runJob(env, 'canary');

  assert.equal(result.skipped, 'transient');
  assert.equal(result.stage, 'token-exchange');
  assert.ok(result.failed >= 1);
  assert.equal(slackCalls.length, 0);
});

test('a write that gets no response at all is quiet on Slack but still fails the run', async () => {
  const { env, slackCalls } = buildEnv({ writeOutcome: 'network' });

  const result = await runJob(env, 'canary');

  assert.equal(result.skipped, 'transient');
  assert.equal(result.stage, 'write');
  assert.ok(result.failed >= 1);
  assert.equal(slackCalls.length, 0);
});

test('a cleanup that gets no response at all still reports the write as proven, quietly and successfully', async () => {
  const { env, slackCalls } = buildEnv({ writeOutcome: 'cleanupNetwork' });

  const result = await runJob(env, 'canary');

  assert.equal(result.ok, true);
  assert.equal(result.failed, undefined);
  assert.equal(slackCalls.length, 0);
});

test('a 5xx on the post-write cleanup delete is quiet too, since the write already proved the thing that matters', async () => {
  const { env, slackCalls } = buildEnv({ writeOutcome: 'cleanup5xx' });

  const result = await runJob(env, 'canary');

  assert.equal(result.ok, true);
  assert.equal(result.failed, undefined);
  assert.equal(slackCalls.length, 0);
});

test('a missing FIREBASE_SERVICE_ACCOUNT secret fails the run loudly instead of a quiet skip', async () => {
  const { env } = buildEnv();
  delete env.FIREBASE_SERVICE_ACCOUNT;

  const result = await runJob(env, 'canary');

  assert.equal(result.skipped, 'missing-secrets');
  assert.ok(result.failed >= 1);
});

test('a leftover DRY_RUN=1 fails the run loudly rather than passing quietly', async () => {
  const { env } = buildEnv();
  env.DRY_RUN = '1';

  const result = await runJob(env, 'canary');

  assert.equal(result.dryRun, true);
  assert.ok(result.failed >= 1);
});

test('a Firestore quota error is not swallowed as a quiet skip for this critical job', async () => {
  const { env } = buildEnv({ quotaOnProfileGet: true });

  await assert.rejects(runJob(env, 'canary'), (err) => {
    assert.match(String(err && err.message), /quota/i);
    return true;
  });
});

test('at the HTTP layer, that same quota error is a loud 500, not a quiet 200', async () => {
  const { env } = buildEnv({ quotaOnProfileGet: true });

  const res = await worker.fetch(
    new Request('https://worker.test/run/canary', {
      method: 'POST',
      headers: { 'X-Run-Token': 'secret-1' },
    }),
    { ...env, RUN_TOKEN: 'secret-1' },
  );

  assert.equal(res.status, 500);
});
