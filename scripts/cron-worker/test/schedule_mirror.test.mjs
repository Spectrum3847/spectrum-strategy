import { test } from 'node:test';
import assert from 'node:assert/strict';

import { runScheduleMirror } from '../src/crons/schedule_mirror.mjs';
import { fingerprintInputs, hashFingerprint } from '../src/crons/lib/fingerprint.mjs';
import { createFakeFirestore } from './support/fake_firestore.mjs';

const PROJECT = 'strategy-test';
const PIT_PROJECT = 'pit-test';
const EVENT_KEY = '2026miket';

function baseSeed() {
  return {
    [PROJECT]: {
      appConfig: {
        activeEvent: { eventKey: EVENT_KEY },
        scheduleMirror: { pitCompetition: 'CompA' },
        apiKeys: {},
      },
      scoutShifts: {
        [EVENT_KEY]: {
          matchCount: 10,
          rotations: [{ name: 'Red', uid: 'our-1', shifts: [{ startMatch: 1, endMatch: 5 }] }],
        },
      },
      shiftTrades: {},
      userProfiles: { 'our-1': { email: 'person@example.com' } },
    },
    [PIT_PROJECT]: {
      pitShifts: {
        'shift-1': {
          competition: 'CompA',
          label: 'Pit 1',
          kind: 'pit',
          assignedUids: ['pit-1'],
          assignedNames: ['Person'],
        },
      },
      userProfiles: { 'pit-1': { email: 'person@example.com' } },
    },
  };
}

function makeCtx(fakeFirestore, nowMs) {
  const { fetchImpl } = fakeFirestore;
  return {
    project: PROJECT,
    pitProject: PIT_PROJECT,
    fetchImpl,
    nowMs,
    nowIso: () => new Date(nowMs).toISOString(),
    opts: async () => ({ token: 't', fetchImpl, project: PROJECT }),
    pitOpts: async () => ({ token: 't', fetchImpl, project: PIT_PROJECT }),
  };
}

function userProfileRequests(requests, fromIndex = 0) {
  return requests.slice(fromIndex).filter((r) => r.url.includes('/userProfiles'));
}

const T0 = Date.parse('2026-09-21T12:00:00.000Z');

test('first run, no stored state: does the full run and writes a fingerprint', async () => {
  const fake = createFakeFirestore(baseSeed());
  const result = await runScheduleMirror(makeCtx(fake, T0));

  assert.equal(result.skipped, undefined);
  assert.equal(result.pitShifts, 1);
  assert.equal(result.rotations, 1);
  assert.ok(userProfileRequests(fake.requests).length > 0, 'the full run does read userProfiles');

  const state = fake.store[PROJECT].appConfig.scheduleMirrorState;
  assert.ok(state, 'appConfig/scheduleMirrorState was written');
  assert.match(state.fingerprint, /^[0-9a-f]{64}$/);
  assert.equal(state.syncedAt, new Date(T0).toISOString());
});

test('unchanged, state fresh: skips and never requests either userProfiles collection', async () => {
  const fake = createFakeFirestore(baseSeed());
  await runScheduleMirror(makeCtx(fake, T0));

  const beforeSecondRun = fake.requests.length;
  const oneHourLater = T0 + 60 * 60 * 1000;
  const result = await runScheduleMirror(makeCtx(fake, oneHourLater));

  assert.equal(result.skipped, 'unchanged');
  assert.equal(result.fingerprintAgeMinutes, 60);
  const requestsSinceSecondRun = fake.requests.slice(beforeSecondRun);
  assert.equal(
    userProfileRequests(fake.requests, beforeSecondRun).length,
    0,
    `expected no userProfiles request among: ${requestsSinceSecondRun.map((r) => r.url).join(', ')}`,
  );
});

test('changed data: does the full run again', async () => {
  const fake = createFakeFirestore(baseSeed());
  await runScheduleMirror(makeCtx(fake, T0));

  fake.store[PROJECT].shiftTrades['trade-1'] = {
    eventKey: EVENT_KEY,
    status: 'accepted',
    fromUid: 'our-1',
    toUid: 'our-1',
  };

  const beforeSecondRun = fake.requests.length;
  const result = await runScheduleMirror(makeCtx(fake, T0 + 60_000));

  assert.equal(result.skipped, undefined);
  assert.ok(
    userProfileRequests(fake.requests, beforeSecondRun).length > 0,
    'changed input data should trigger a full run, including userProfiles reads',
  );
});

test('unchanged but state older than 24 hours: does the full run anyway', async () => {
  const fake = createFakeFirestore(baseSeed());
  await runScheduleMirror(makeCtx(fake, T0));

  const beforeSecondRun = fake.requests.length;
  const justOverADayLater = T0 + 24 * 60 * 60 * 1000 + 1;
  const result = await runScheduleMirror(makeCtx(fake, justOverADayLater));

  assert.equal(result.skipped, undefined);
  assert.ok(
    userProfileRequests(fake.requests, beforeSecondRun).length > 0,
    'a stale fingerprint should force a full run even with unchanged data',
  );
});

test('fingerprint is stable across key order and document order', async () => {
  const pitShiftDocs = [
    { id: 'shift-2', data: { competition: 'CompA', label: 'Pit 2' } },
    { id: 'shift-1', data: { competition: 'CompA', label: 'Pit 1' } },
  ];
  const tradeDocs = [
    { id: 'trade-b', data: { eventKey: EVENT_KEY, status: 'accepted' } },
    { id: 'trade-a', data: { eventKey: EVENT_KEY, status: 'pending' } },
  ];
  const schedule = { matchCount: 10, rotations: [] };

  const a = await hashFingerprint(
    fingerprintInputs({
      eventKey: EVENT_KEY,
      override: 'CompA',
      tbaEvent: { short_name: 'Ket', name: 'Kettering Event' },
      pitShiftDocs,
      schedule,
      tradeDocs,
    }),
  );

  const b = await hashFingerprint(
    fingerprintInputs({
      eventKey: EVENT_KEY,
      override: 'CompA',
      tbaEvent: { name: 'Kettering Event', short_name: 'Ket' },
      pitShiftDocs: [...pitShiftDocs].reverse(),
      schedule: { rotations: [], matchCount: 10 },
      tradeDocs: [...tradeDocs].reverse(),
    }),
  );

  assert.equal(a, b);

  const c = await hashFingerprint(
    fingerprintInputs({
      eventKey: EVENT_KEY,
      override: 'CompA',
      tbaEvent: { short_name: 'Ket', name: 'Kettering Event' },
      pitShiftDocs,
      schedule: { matchCount: 11, rotations: [] },
      tradeDocs,
    }),
  );
  assert.notEqual(a, c);
});
