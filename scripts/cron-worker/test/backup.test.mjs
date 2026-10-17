import { test } from 'node:test';
import assert from 'node:assert/strict';

import worker, { runJob } from '../src/index.mjs';
import { createFakeFirestore } from './support/fake_firestore.mjs';
import { createFakeR2Bucket } from './support/fake_r2_bucket.mjs';
import { privateKeyPem } from './support/fake_service_account.mjs';

const PROJECT = 'proj-firebase';
const DATE = '2026-09-22';
const DAILY_SLOT_HOUR = 8;
const DAILY_SLOT_NOW = Date.parse(`${DATE}T${String(DAILY_SLOT_HOUR).padStart(2, '0')}:00:00Z`);
const OFF_SLOT_NOW = Date.parse(`${DATE}T14:00:00Z`);

const LAST_HOUR_NOW = Date.parse(`${DATE}T23:00:00Z`);

function serviceAccountJson() {
  return JSON.stringify({ client_email: 'firebase@example.iam.gserviceaccount.com', private_key: privateKeyPem });
}

function buildFetch(firestoreFetch) {
  return async (url, init = {}) => {
    const href = typeof url === 'string' ? url : url.toString();
    if (href === 'https://oauth2.googleapis.com/token') {
      return new Response(JSON.stringify({ access_token: 'token', expires_in: 3600 }), { status: 200 });
    }
    return firestoreFetch(href, init);
  };
}

function buildEnv({
  seed,
  bucketSeed,
  budget,
  pageSize,
  maxCombinedBytes,
  nowMs = DAILY_SLOT_NOW,
  bucketFailGet,
  bucketFailPut,
} = {}) {
  const { fetchImpl: firestoreFetch, requests } = createFakeFirestore({
    [PROJECT]: { ...(seed || {}) },
  });
  const bucket = createFakeR2Bucket(bucketSeed, {
    ...(bucketFailGet ? { failGet: bucketFailGet } : {}),
    ...(bucketFailPut ? { failPut: bucketFailPut } : {}),
  });
  const env = {
    FIREBASE_SERVICE_ACCOUNT: serviceAccountJson(),
    FIREBASE_PROJECT: PROJECT,
    fetchImpl: buildFetch(firestoreFetch),
    nowMs,
    PHOTOS: bucket,
    ...(budget ? { BACKUP_SUBREQUEST_BUDGET: budget } : {}),
    ...(pageSize ? { BACKUP_PAGE_SIZE: pageSize } : {}),
    ...(maxCombinedBytes ? { BACKUP_MAX_COMBINED_BYTES: maxCombinedBytes } : {}),
  };
  return { env, bucket, requests };
}

function recentScoutEntry(nowMs, msAgo) {
  return { updatedAtTs: new Date(nowMs - msAgo) };
}

test('skips cleanly with no PHOTOS binding', async () => {
  const { env } = buildEnv();
  delete env.PHOTOS;
  const result = await runJob(env, 'backup');
  assert.equal(result.skipped, 'no-bucket');
});

test('an off-slot hour with no recent scouting activity is a cheap no-op: one Firestore query, one R2 read', async () => {
  const seed = { scoutEntries: { old: recentScoutEntry(OFF_SLOT_NOW, 5 * 24 * 60 * 60 * 1000) } };
  const { env, bucket, requests } = buildEnv({ seed, nowMs: OFF_SLOT_NOW });

  const result = await runJob(env, 'backup');

  assert.equal(result.skipped, 'not-daily-slot');
  assert.equal(result.live, false);

  assert.deepEqual(
    bucket.calls.map((c) => c.op),
    ['get'],
  );
  const liveness = requests.filter((r) => r.url.includes(':runQuery'));
  assert.equal(liveness.length, 1);
  assert.equal(requests.some((r) => r.url.includes('listCollectionIds')), false);
});

test('a recent scoutEntries write makes the job live, with no activeEvent flag involved', async () => {
  const seed = { scoutEntries: { e1: recentScoutEntry(OFF_SLOT_NOW, 5 * 60 * 1000) } };
  const { env, bucket } = buildEnv({ seed, nowMs: OFF_SLOT_NOW });

  const result = await runJob(env, 'backup');

  assert.equal(result.live, true);
  assert.equal(result.slot, 'hour-14');
  assert.equal(bucket.store.has(`backups/${DATE}/hour-14/snapshot.json`), true);
});

test('scouting activity that stopped days ago reads as quiet, unlike a stale activeEvent flag would', async () => {

  const seed = { scoutEntries: { old: recentScoutEntry(DAILY_SLOT_NOW, 3 * 24 * 60 * 60 * 1000) } };
  const { env, bucket } = buildEnv({ seed, nowMs: DAILY_SLOT_NOW });

  const result = await runJob(env, 'backup');

  assert.equal(result.live, false);
  assert.equal(result.slot, 'daily');
  assert.equal(bucket.store.has(`backups/${DATE}/daily/snapshot.json`), true);
});

test('an off-slot hour on a quiet day continues an already-started daily manifest instead of idling', async () => {
  const seed = {
    scoutEntries: { old: recentScoutEntry(DAILY_SLOT_NOW, 3 * 24 * 60 * 60 * 1000) },
    bugReports: { r1: {} },
  };

  const first = buildEnv({ seed, nowMs: DAILY_SLOT_NOW, budget: 6 });
  const firstResult = await runJob(first.env, 'backup');
  assert.equal(firstResult.partial, true);

  const secondEnv = { ...first.env, nowMs: OFF_SLOT_NOW, PHOTOS: first.bucket };
  delete secondEnv.BACKUP_SUBREQUEST_BUDGET;
  const secondResult = await runJob(secondEnv, 'backup');

  assert.deepEqual(secondResult.skipped, []);
  assert.equal(secondResult.slot, 'daily');
  assert.equal(secondResult.partial, false);
  assert.equal(secondResult.collections, 2);

  const snapshot = JSON.parse(first.bucket.store.get(`backups/${DATE}/daily/snapshot.json`));
  assert.deepEqual(Object.keys(snapshot.collections).sort(), ['bugReports', 'scoutEntries']);
});

test('the daily slot hour exports, discovering collections at runtime, into one combined snapshot', async () => {
  const seed = {
    scoutEntries: {
      e1: { teamNumber: 118, ...recentScoutEntry(DAILY_SLOT_NOW, 10 * 24 * 60 * 60 * 1000) },
      e2: { teamNumber: 254, ...recentScoutEntry(DAILY_SLOT_NOW, 10 * 24 * 60 * 60 * 1000) },
    },
    bugReports: { r1: { status: 'new' } },
  };
  const { env, bucket } = buildEnv({ seed, nowMs: DAILY_SLOT_NOW });

  const result = await runJob(env, 'backup');

  assert.equal(result.live, false);
  assert.equal(result.slot, 'daily');
  assert.equal(result.partial, false);
  assert.equal(result.failed, undefined);
  assert.equal(result.total, 2);
  assert.equal(result.collections, 2);

  const snapshot = JSON.parse(bucket.store.get(`backups/${DATE}/daily/snapshot.json`));
  assert.equal(snapshot.collections.scoutEntries.count, 2);
  assert.deepEqual(
    snapshot.collections.scoutEntries.documents.map((d) => d.id).sort(),
    ['e1', 'e2'],
  );
  const manifest = JSON.parse(bucket.store.get(`backups/${DATE}/daily/_manifest.json`));
  assert.deepEqual(Object.keys(manifest.completed).sort(), ['bugReports', 'scoutEntries']);

  assert.deepEqual(
    [...bucket.store.keys()].filter((k) => k.startsWith(`backups/${DATE}/daily/`)).sort(),
    [`backups/${DATE}/daily/_manifest.json`, `backups/${DATE}/daily/snapshot.json`],
  );
});

test('an empty collection never appears, since listCollectionIds only names ones with data', async () => {
  const { env, bucket } = buildEnv({ seed: { pickLists: {} }, nowMs: DAILY_SLOT_NOW });
  const result = await runJob(env, 'backup');
  assert.equal(result.total, 0);
  assert.equal(bucket.store.has(`backups/${DATE}/daily/snapshot.json`), false);
});

test('a mid-date deferral is quiet: partial but not a failure, and 200 through the HTTP route', async () => {
  const seed = {
    scoutEntries: { old: recentScoutEntry(DAILY_SLOT_NOW, 3 * 24 * 60 * 60 * 1000) },
    bugReports: { r1: {} },
    pitScoutEntries: { p1: {} },
  };
  const { env, bucket } = buildEnv({ seed, nowMs: DAILY_SLOT_NOW, budget: 6 });
  env.RUN_TOKEN = 'secret-1';

  const res = await worker.fetch(
    new Request('https://worker.test/run/backup', {
      method: 'POST',
      headers: { 'X-Run-Token': 'secret-1' },
    }),
    env,
  );

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.result.failed, undefined);
  assert.equal(body.result.partial, true);
  assert.ok(body.result.skipped.length > 0);
  assert.ok(body.result.collections < body.result.total);

  const manifest = JSON.parse(bucket.store.get(`backups/${DATE}/daily/_manifest.json`));
  assert.equal(manifest.skipped.length, body.result.skipped.length);

  assert.equal(body.result.pruned, 0);
  assert.equal(bucket.calls.some((c) => c.op === 'delete'), false);
});

test("an incomplete manifest at the daily slot's last hour is loud: failed > 0 and a 500", async () => {
  const seed = {
    scoutEntries: { old: recentScoutEntry(DAILY_SLOT_NOW, 3 * 24 * 60 * 60 * 1000) },
    bugReports: { r1: {} },
    pitScoutEntries: { p1: {} },
  };

  const first = buildEnv({ seed, nowMs: DAILY_SLOT_NOW, budget: 6 });
  const firstResult = await runJob(first.env, 'backup');
  assert.equal(firstResult.partial, true);
  assert.equal(firstResult.failed, undefined);

  const secondEnv = { ...first.env, nowMs: LAST_HOUR_NOW, PHOTOS: first.bucket };
  secondEnv.RUN_TOKEN = 'secret-1';

  const res = await worker.fetch(
    new Request('https://worker.test/run/backup', {
      method: 'POST',
      headers: { 'X-Run-Token': 'secret-1' },
    }),
    secondEnv,
  );

  assert.equal(res.status, 500);
  const body = await res.json();
  assert.equal(body.ok, false);
  assert.equal(body.job, 'backup');
  assert.equal(body.result.partial, true);
  assert.ok(body.result.failed > 0);
});

test('an error backing up a collection is loud immediately, even with hours left in the day', async () => {
  const seed = { scoutEntries: { old: recentScoutEntry(DAILY_SLOT_NOW, 3 * 24 * 60 * 60 * 1000) } };
  const { fetchImpl: firestoreFetch } = createFakeFirestore({ [PROJECT]: seed });
  const bucket = createFakeR2Bucket();
  const env = {
    FIREBASE_SERVICE_ACCOUNT: serviceAccountJson(),
    FIREBASE_PROJECT: PROJECT,
    nowMs: DAILY_SLOT_NOW,
    PHOTOS: bucket,
    fetchImpl: async (url, init = {}) => {
      const href = typeof url === 'string' ? url : url.toString();
      if (href === 'https://oauth2.googleapis.com/token') {
        return new Response(JSON.stringify({ access_token: 'token', expires_in: 3600 }), { status: 200 });
      }
      if (href.includes('/scoutEntries?')) {
        return new Response('boom', { status: 500 });
      }
      return firestoreFetch(href, init);
    },
  };

  const result = await runJob(env, 'backup');

  assert.ok(result.failed > 0);
  assert.equal(result.skipped.includes('scoutEntries'), true);
});

test('a collection truncated mid-page resumes from where it left off, entirely inside the manifest', async () => {

  const scoutEntries = { old: recentScoutEntry(DAILY_SLOT_NOW, 3 * 24 * 60 * 60 * 1000) };
  for (let i = 1; i <= 5; i++) scoutEntries[`e${i}`] = { teamNumber: i };
  const seed = { scoutEntries };

  const first = buildEnv({ seed, nowMs: DAILY_SLOT_NOW, budget: 6, pageSize: 2 });
  const firstResult = await runJob(first.env, 'backup');
  assert.equal(firstResult.partial, true);
  assert.deepEqual(firstResult.skipped, ['scoutEntries']);

  const manifestAfterFirst = JSON.parse(first.bucket.store.get(`backups/${DATE}/daily/_manifest.json`));
  assert.equal(manifestAfterFirst.partial.scoutEntries.pageToken, '2');
  assert.equal(manifestAfterFirst.partial.scoutEntries.documents.length, 2);

  assert.equal(first.bucket.store.has(`backups/${DATE}/daily/scoutEntries.json`), false);
  assert.equal(first.bucket.store.has(`backups/${DATE}/daily/snapshot.json`), false);

  const secondFirestore = createFakeFirestore({ [PROJECT]: seed });
  const secondEnv = {
    ...first.env,
    fetchImpl: buildFetch(secondFirestore.fetchImpl),
    PHOTOS: first.bucket,
  };
  delete secondEnv.BACKUP_SUBREQUEST_BUDGET;
  const secondResult = await runJob(secondEnv, 'backup');

  assert.equal(secondResult.partial, false);
  const snapshot = JSON.parse(first.bucket.store.get(`backups/${DATE}/daily/snapshot.json`));
  assert.equal(snapshot.collections.scoutEntries.count, 6);
  assert.deepEqual(
    snapshot.collections.scoutEntries.documents.map((d) => d.id).sort(),
    ['e1', 'e2', 'e3', 'e4', 'e5', 'old'],
  );

  const manifestAfterSecond = JSON.parse(first.bucket.store.get(`backups/${DATE}/daily/_manifest.json`));
  assert.deepEqual(manifestAfterSecond.partial, {});
  assert.equal(manifestAfterSecond.completed.scoutEntries, 6);

  const scoutEntriesRequests = secondFirestore.requests.filter((r) => r.url.includes('/scoutEntries?'));
  assert.ok(scoutEntriesRequests.some((r) => r.url.includes('pageToken=2')));
  assert.equal(scoutEntriesRequests.some((r) => r.url.includes('pageToken=0')), false);
});

test('a follow-up run in the same slot finishes without re-fetching what already completed', async () => {
  const seed = {
    scoutEntries: { old: recentScoutEntry(DAILY_SLOT_NOW, 3 * 24 * 60 * 60 * 1000) },
    bugReports: { r1: {} },
  };
  const first = buildEnv({ seed, nowMs: DAILY_SLOT_NOW, budget: 6 });
  const firstResult = await runJob(first.env, 'backup');
  assert.equal(firstResult.partial, true);
  const completedFirst = Object.keys(
    JSON.parse(first.bucket.store.get(`backups/${DATE}/daily/_manifest.json`)).completed,
  );
  assert.equal(completedFirst.length, 1);

  const secondFirestore = createFakeFirestore({ [PROJECT]: seed });
  const secondEnv = {
    ...first.env,
    fetchImpl: buildFetch(secondFirestore.fetchImpl),
    PHOTOS: first.bucket,
  };
  delete secondEnv.BACKUP_SUBREQUEST_BUDGET;

  const secondResult = await runJob(secondEnv, 'backup');
  assert.equal(secondResult.partial, false);
  assert.equal(secondResult.collections, 2);

  const alreadyDoneCollection = completedFirst[0];
  const refetched = secondFirestore.requests.some((r) => r.url.includes(`/${alreadyDoneCollection}?`));
  assert.equal(refetched, false);

  const snapshot = JSON.parse(first.bucket.store.get(`backups/${DATE}/daily/snapshot.json`));
  assert.deepEqual(Object.keys(snapshot.collections).sort(), ['bugReports', 'scoutEntries']);
});

test('a collection that would push the combined snapshot past its size cap is deferred, not written oversized', async () => {
  const seed = {
    bugReports: { r1: { title: 'x' } },
    scoutEntries: { e1: { teamNumber: 1 } },
  };

  const { env, bucket } = buildEnv({ seed, nowMs: DAILY_SLOT_NOW, maxCombinedBytes: 58 });

  const result = await runJob(env, 'backup');

  assert.equal(result.partial, true);
  assert.equal(result.collections, 1);
  assert.deepEqual(result.skipped, ['scoutEntries']);

  const snapshot = JSON.parse(bucket.store.get(`backups/${DATE}/daily/snapshot.json`));
  assert.deepEqual(Object.keys(snapshot.collections), ['bugReports']);

  const manifest = JSON.parse(bucket.store.get(`backups/${DATE}/daily/_manifest.json`));

  assert.equal(manifest.partial.scoutEntries.pageToken, null);
  assert.equal(manifest.partial.scoutEntries.documents.length, 1);

  const secondFirestore = createFakeFirestore({ [PROJECT]: seed });
  const secondEnv = { ...env, fetchImpl: buildFetch(secondFirestore.fetchImpl), PHOTOS: bucket };
  delete secondEnv.BACKUP_MAX_COMBINED_BYTES;
  const secondResult = await runJob(secondEnv, 'backup');

  assert.equal(secondResult.partial, false);
  assert.equal(secondFirestore.requests.some((r) => r.url.includes('/scoutEntries?')), false);
  const finalSnapshot = JSON.parse(bucket.store.get(`backups/${DATE}/daily/snapshot.json`));
  assert.deepEqual(Object.keys(finalSnapshot.collections).sort(), ['bugReports', 'scoutEntries']);
});

test('prunes snapshots outside the retention window once the day is complete, and only once', async () => {
  const seed = { scoutEntries: { old: recentScoutEntry(DAILY_SLOT_NOW, 3 * 24 * 60 * 60 * 1000) } };
  const bucketSeed = {
    [`backups/2026-01-01/daily/_manifest.json`]: JSON.stringify({ completed: { scoutEntries: 1 }, skipped: [] }),
    [`backups/2026-01-01/daily/snapshot.json`]: JSON.stringify({ collections: { scoutEntries: { count: 1, documents: [] } } }),
    [`backups/2026-09-20/daily/_manifest.json`]: JSON.stringify({ completed: { scoutEntries: 1 }, skipped: [] }),
    [`backups/2026-09-20/daily/snapshot.json`]: JSON.stringify({ collections: { scoutEntries: { count: 1, documents: [] } } }),
  };
  const { env, bucket } = buildEnv({ seed, bucketSeed, nowMs: DAILY_SLOT_NOW });

  const result = await runJob(env, 'backup');

  assert.equal(result.partial, false);
  assert.ok(result.pruned > 0);
  assert.equal(bucket.store.has('backups/2026-01-01/daily/snapshot.json'), false);
  assert.equal(bucket.store.has('backups/2026-01-01/daily/_manifest.json'), false);

  assert.equal(bucket.store.has('backups/2026-09-20/daily/snapshot.json'), true);

  const deleteCallsAfterFirst = bucket.calls.filter((c) => c.op === 'delete').length;

  const second = buildEnv({ seed, bucketSeed: Object.fromEntries(bucket.store), nowMs: DAILY_SLOT_NOW });
  await runJob(second.env, 'backup');
  assert.equal(second.bucket.calls.filter((c) => c.op === 'delete').length, 0);
  assert.ok(deleteCallsAfterFirst > 0);
});

test('a run killed between the snapshot write and the manifest write does not lose what the snapshot already has', async () => {

  const seed = {
    scoutEntries: { old: recentScoutEntry(DAILY_SLOT_NOW, 3 * 24 * 60 * 60 * 1000) },
    bugReports: { r1: { title: 'x' } },
  };
  let dieOnManifestWrite = true;
  const { env, bucket } = buildEnv({
    seed,
    nowMs: DAILY_SLOT_NOW,
    bucketFailPut: (key) => dieOnManifestWrite && key.endsWith('_manifest.json'),
  });

  await assert.rejects(() => runJob(env, 'backup'), /fake R2 put failure/);

  const snapshotAfterCrash = JSON.parse(bucket.store.get(`backups/${DATE}/daily/snapshot.json`));
  assert.deepEqual(Object.keys(snapshotAfterCrash.collections).sort(), ['bugReports', 'scoutEntries']);
  assert.equal(bucket.store.has(`backups/${DATE}/daily/_manifest.json`), false);

  dieOnManifestWrite = false;
  const secondFirestore = createFakeFirestore({ [PROJECT]: seed });
  const secondEnv = {
    ...env,
    fetchImpl: buildFetch(secondFirestore.fetchImpl),
    PHOTOS: bucket,
    BACKUP_SUBREQUEST_BUDGET: 6,
  };
  const secondResult = await runJob(secondEnv, 'backup');

  assert.equal(secondResult.partial, true);
  assert.deepEqual(secondResult.skipped, ['scoutEntries']);

  const snapshotAfterRestart = JSON.parse(bucket.store.get(`backups/${DATE}/daily/snapshot.json`));
  assert.deepEqual(Object.keys(snapshotAfterRestart.collections).sort(), ['bugReports', 'scoutEntries']);
  assert.equal(snapshotAfterRestart.collections.scoutEntries.count, 1);
  assert.deepEqual(
    snapshotAfterRestart.collections.scoutEntries.documents.map((d) => d.id),
    ['old'],
  );
});
