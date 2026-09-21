import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  matchCompetition,
  buildUidTranslator,
  buildPitMirror,
  buildScoutMirror,
} from '../src/crons/lib/mirror.mjs';

const TBA_EVENT = {
  key: '2026miket',
  name: 'FIM District Kettering University Event #1',
  short_name: 'Kettering University #1',
};

test('matchCompetition prefers an override that exists', () => {
  const picked = matchCompetition({
    eventKey: '2026miket',
    competitions: ['Kettering', 'Houston'],
    tbaEvent: TBA_EVENT,
    override: 'Houston',
  });
  assert.equal(picked, 'Houston');
});

test('matchCompetition ignores an override that names nothing', () => {
  const picked = matchCompetition({
    eventKey: '2026miket',
    competitions: ['Kettering'],
    tbaEvent: TBA_EVENT,
    override: 'Nowhere',
  });
  assert.equal(picked, 'Kettering');
});

test('matchCompetition matches the event key exactly', () => {
  assert.equal(
    matchCompetition({ eventKey: '2026miket', competitions: ['2026MIKET'], tbaEvent: null }),
    '2026MIKET',
  );
});

test('matchCompetition matches a competition contained in the TBA name', () => {
  assert.equal(
    matchCompetition({ eventKey: '2026miket', competitions: ['Houston', 'kettering'], tbaEvent: TBA_EVENT }),
    'kettering',
  );
});

test('matchCompetition returns null when nothing fits', () => {
  assert.equal(
    matchCompetition({ eventKey: '2026miket', competitions: ['Houston'], tbaEvent: TBA_EVENT }),
    null,
  );
  assert.equal(matchCompetition({ eventKey: '2026miket', competitions: [], tbaEvent: TBA_EVENT }), null);
});

const STRATEGY_PROFILES = [
  { uid: 's1', email: 'One@Example.com' },
  { uid: 's2', email: 'two@example.com', linkedEmails: ['two.alt@example.com'] },
  { uid: 's3' },
];
const PIT_PROFILES = [
  { uid: 'p1', email: 'one@example.com' },
  { uid: 'p2', email: 'TWO.ALT@example.com' },
];

test('buildUidTranslator joins on email, case-insensitively and through linked emails', () => {
  const toPit = buildUidTranslator(STRATEGY_PROFILES, PIT_PROFILES);
  assert.equal(toPit('s1'), 'p1');
  assert.equal(toPit('s2'), 'p2');
  assert.equal(toPit('s3'), null);
  assert.equal(toPit('unknown'), null);
  const toStrategy = buildUidTranslator(PIT_PROFILES, STRATEGY_PROFILES);
  assert.equal(toStrategy('p2'), 's2');
});

test('buildPitMirror re-keys assignees and drops fields a shift lacks', () => {
  const doc = buildPitMirror({
    eventKey: '2026miket',
    competition: 'Kettering',
    syncedAt: 'T',
    translateUid: (uid) => (uid === 'p1' ? 's1' : null),
    pitShifts: [
      {
        id: 'b',
        label: 'Load out',
        kind: 'loadOut',
        assignedUids: ['p1', 'unlinked:sam'],
        assignedNames: ['One', 'Sam'],
        startsAt: '2026-03-14T20:00:00.000Z',
        endsAt: '2026-03-14T22:00:00.000Z',
      },
      {
        id: 'a',
        label: 'Pit duty',
        kind: 'pitDuty',
        assignedUids: ['p1'],
        assignedNames: ['One'],
        startMatch: 1,
        endMatch: 20,
        notes: 'bring the cart',
      },
    ],
  });
  assert.deepEqual(doc, {
    eventKey: '2026miket',
    competition: 'Kettering',
    syncedAt: 'T',
    shifts: [
      {
        id: 'a',
        label: 'Pit duty',
        kind: 'pitDuty',
        assignees: [{ name: 'One', uid: 's1' }],
        startMatch: 1,
        endMatch: 20,
        notes: 'bring the cart',
      },
      {
        id: 'b',
        label: 'Load out',
        kind: 'loadOut',
        assignees: [{ name: 'One', uid: 's1' }, { name: 'Sam' }],
        startsAt: '2026-03-14T20:00:00.000Z',
        endsAt: '2026-03-14T22:00:00.000Z',
      },
    ],
  });
});

test('buildScoutMirror re-keys rotations and sorts shifts', () => {
  const doc = buildScoutMirror({
    eventKey: '2026miket',
    competition: 'Kettering',
    matchCount: 24,
    syncedAt: 'T',
    translateUid: (uid) => (uid === 's1' ? 'p1' : null),
    rotations: [
      { uid: 's1', name: 'One', shifts: [{ startMatch: 13, endMatch: 18 }, { startMatch: 1, endMatch: 6 }] },
      { uid: 's3', name: 'Three', shifts: [] },
      { uid: '', name: 'Typed Name', shifts: [{ startMatch: 7, endMatch: 12 }] },
    ],
  });
  assert.deepEqual(doc, {
    eventKey: '2026miket',
    competition: 'Kettering',
    matchCount: 24,
    syncedAt: 'T',
    rotations: [
      { name: 'One', uid: 'p1', shifts: [{ startMatch: 1, endMatch: 6 }, { startMatch: 13, endMatch: 18 }] },
      { name: 'Three', shifts: [] },
      { name: 'Typed Name', shifts: [{ startMatch: 7, endMatch: 12 }] },
    ],
  });
});
