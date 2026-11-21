import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  buildShiftPushPayload,
  buildShiftStartDmText,
  buildTestPushPayload,
  buildTradeRequestDmText,
  matchRangeLabel,
} from '../src/messages.mjs';

test('matchRangeLabel collapses a single-match block', () => {
  assert.equal(matchRangeLabel(5, 5), 'match 5');
});

test('matchRangeLabel spans a multi-match block', () => {
  assert.equal(matchRangeLabel(1, 6), 'matches 1-6');
});

test('shift start DM mentions the match range', () => {
  const text = buildShiftStartDmText({ startMatch: 7, endMatch: 12 });
  assert.match(text, /matches 7-12/);
});

test('trade request DM names the requester and the block', () => {
  const text = buildTradeRequestDmText({
    requesterDisplayName: 'Alex',
    startMatch: 3,
    endMatch: 3,
  });
  assert.match(text, /Alex/);
  assert.match(text, /match 3/);
});

test('trade request DM falls back when the requester has no name', () => {
  const text = buildTradeRequestDmText({
    requesterDisplayName: '',
    startMatch: 3,
    endMatch: 3,
  });
  assert.match(text, /A teammate/);
});

test('shift push says how many matches away, the range and the station', () => {
  const base = { eventKey: '2026miket', startMatch: 7, endMatch: 12, station: 'B2' };
  assert.deepEqual(buildShiftPushPayload({ ...base, away: 3 }), {
    title: 'Your scouting shift starts in 3 matches',
    body: 'Scout matches 7-12 at B2. Head to the stands.',
    tag: 'shift-2026miket-7',
    url: '/scout',
  });
  assert.equal(
    buildShiftPushPayload({ ...base, away: 1 }).title,
    'Your scouting shift starts in 1 match',
  );
  assert.equal(buildShiftPushPayload({ ...base, away: 0 }).title, 'Your scouting shift is next');
});

test('shift push leaves the station out when the block has none', () => {
  const payload = buildShiftPushPayload({ eventKey: 'e', startMatch: 5, endMatch: 5, away: 2 });
  assert.equal(payload.body, 'Scout match 5. Head to the stands.');
});

test('every test push has its own tag', () => {
  assert.notEqual(buildTestPushPayload(1).tag, buildTestPushPayload(2).tag);
});
