import { test } from 'node:test';
import assert from 'node:assert/strict';

import { keepDate, datesToPrune, DAILY_WINDOW_DAYS } from '../src/crons/lib/backup_retention.mjs';

const TODAY = '2026-09-22';

test('every day inside the daily window survives, whatever the weekday', () => {
  assert.equal(keepDate(TODAY, TODAY), true);
  assert.equal(keepDate('2026-09-15', TODAY), true);
  assert.equal(keepDate('2026-09-08', TODAY), true);
});

test('past the daily window, only a Sunday survives', () => {

  assert.equal(keepDate('2026-09-07', TODAY), false);

  assert.equal(keepDate('2026-09-06', TODAY), true);
});

test('a Sunday older than the weekly window is pruned too', () => {
  assert.equal(keepDate('2026-07-19', TODAY), true);
  assert.equal(keepDate('2026-07-12', TODAY), false);
  assert.equal(keepDate('2026-01-01', TODAY), false);
});

test('a future or same-day date is never pruned', () => {
  assert.equal(keepDate('2026-09-23', TODAY), true);
});

test('datesToPrune keeps the recent window and drops the rest', () => {
  const existing = ['2026-09-22', '2026-09-20', '2026-09-06', '2026-09-07', '2026-01-01'];
  assert.deepEqual(datesToPrune(existing, TODAY).sort(), ['2026-01-01', '2026-09-07']);
});

test('the daily window constant matches what the module documents', () => {
  assert.equal(DAILY_WINDOW_DAYS, 14);
});
