import { test } from 'node:test';
import assert from 'node:assert/strict';

import worker, { runAllJobs, JOBS } from '../src/index.mjs';

function post(path, token = 'secret-1') {
  return new Request(`https://worker.test${path}`, {
    method: 'POST',
    headers: { 'X-Run-Token': token },
  });
}

test('every JOBS entry has a run function and a non-empty requires array', () => {
  for (const [name, job] of Object.entries(JOBS)) {
    assert.equal(typeof job.run, 'function', `${name}.run is a function`);
    assert.ok(
      Array.isArray(job.requires) && job.requires.length > 0,
      `${name}.requires is non-empty`,
    );
  }
});

test('/run/<name> runs that one job and names it in the response', async () => {
  const env = { RUN_TOKEN: 'secret-1' };
  for (const name of Object.keys(JOBS)) {
    const res = await worker.fetch(post(`/run/${name}`), env);
    const body = await res.json();
    assert.equal(body.job, name);

    assert.equal(body.result.skipped, 'missing-secrets');
    if (JOBS[name].critical) {

      assert.equal(res.status, 500, `${name} (critical) answers 500 when secrets are missing`);
      assert.ok(body.result.failed >= 1);
    } else {
      assert.equal(res.status, 200, `${name} route answers 200`);
    }
  }
});

test('a bare /run is a 404: every job is named in its own route', async () => {
  const res = await worker.fetch(post('/run'), { RUN_TOKEN: 'secret-1' });
  assert.equal(res.status, 404);
});

test('an unknown job name is a 404, not a 500', async () => {
  const res = await worker.fetch(post('/run/nope'), { RUN_TOKEN: 'secret-1' });
  assert.equal(res.status, 404);
  assert.equal((await res.json()).ok, false);
});

test('a job that throws answers 500 and says which job it was', async () => {

  const env = {
    RUN_TOKEN: 'secret-1',
    FIREBASE_SERVICE_ACCOUNT: 'not-json',
    FIREBASE_PROJECT: 'p',
  };
  const res = await worker.fetch(post('/run/usage'), env);
  assert.equal(res.status, 500);
  const body = await res.json();
  assert.equal(body.ok, false);
  assert.equal(body.job, 'usage');
  assert.ok(body.error);
});

test('runAllJobs reports every job, and one failure does not stop the rest', async () => {
  const env = {
    FIREBASE_SERVICE_ACCOUNT: 'not-json',
    SPECTRUM_PLATFORM_SERVICE_ACCOUNT: 'not-json',
    PIT_FIREBASE_SERVICE_ACCOUNT: 'not-json',
    SLACK_BOT_TOKEN: 'x',
    GH_TOKEN: 'x',
    FIREBASE_PROJECT: 'p',
  };
  const results = await runAllJobs(env);
  assert.deepEqual(Object.keys(results).sort(), Object.keys(JOBS).sort());
  for (const [name, result] of Object.entries(results)) {
    assert.ok(result.error, `${name} reported its failure instead of throwing`);
  }
});

test('a token with surrounding whitespace is accepted, since a scheduler field is typed by hand', async () => {
  const env = { RUN_TOKEN: 'secret-1' };
  const res = await worker.fetch(
    new Request('https://worker.test/run/shift', {
      method: 'POST',
      headers: { 'X-Run-Token': '  secret-1\n' },
    }),
    env,
  );
  assert.equal(res.status, 200);
});

test('a missing header says so, and names the header to add', async () => {
  const res = await worker.fetch(
    new Request('https://worker.test/run/shift', { method: 'POST' }),
    { RUN_TOKEN: 'secret-1' },
  );
  assert.equal(res.status, 401);
  const body = await res.json();
  assert.match(body.error, /no X-Run-Token header/);
  assert.match(body.hint, /X-Run-Token/);
});

test('a wrong token reports what the caller sent and nothing about the secret', async () => {
  const res = await worker.fetch(
    new Request('https://worker.test/run/shift', {
      method: 'POST',
      headers: { 'X-Run-Token': 'nope' },
    }),
    { RUN_TOKEN: 'a-much-longer-secret' },
  );
  assert.equal(res.status, 401);
  const body = await res.json();
  assert.equal(body.sentCharacters, 4);
  assert.equal(body.sentCharactersTrimmed, 4);

  const serialized = JSON.stringify(body);
  assert.equal(serialized.includes('a-much-longer-secret'), false);
  assert.equal(serialized.includes(String('a-much-longer-secret'.length)), false);
});

test('an empty header value is called out separately from a missing one', async () => {
  const res = await worker.fetch(
    new Request('https://worker.test/run/shift', {
      method: 'POST',
      headers: { 'X-Run-Token': '' },
    }),
    { RUN_TOKEN: 'secret-1' },
  );
  assert.equal(res.status, 401);
  const body = await res.json();
  assert.match(body.hint, /sent but empty/);
});

test('a job that swallowed failures answers 500, not a misleading 200', async () => {

  const { privateKeyPem } = await import('./support/fake_service_account.mjs');
  const env = {
    RUN_TOKEN: 'secret-1',
    FIREBASE_PROJECT: 'p',
    GH_TOKEN: 'gh',
    FIREBASE_SERVICE_ACCOUNT: JSON.stringify({
      client_email: 'x@example.iam.gserviceaccount.com',
      private_key: privateKeyPem,
    }),
    fetchImpl: async (url) => {
      const u = String(url);
      if (u.includes('oauth2.googleapis.com')) {
        return new Response(JSON.stringify({ access_token: 't', expires_in: 3600 }), { status: 200 });
      }
      if (u.includes(':runQuery')) {
        return new Response(
          JSON.stringify([
            {
              document: {
                name: 'projects/p/databases/(default)/documents/bugReports/r1',
                fields: { status: { stringValue: 'new' }, title: { stringValue: 'x' } },
              },
            },
          ]),
          { status: 200 },
        );
      }
      if (u.includes('api.github.com')) return new Response('nope', { status: 403 });
      return new Response('{}', { status: 200 });
    },
  };

  const res = await worker.fetch(
    new Request('https://worker.test/run/report', {
      method: 'POST',
      headers: { 'X-Run-Token': 'secret-1' },
    }),
    env,
  );
  assert.equal(res.status, 500);
  const body = await res.json();
  assert.equal(body.ok, false);
  assert.ok(body.result.failed >= 1, 'the failure count reaches the response');
  assert.equal(body.result.opened, 0);
});
