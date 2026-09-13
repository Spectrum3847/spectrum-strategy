'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { computeWindowStart } = require('../lib/window');

const NOW = Date.parse('2026-07-02T12:00:00.000Z');

test('no watermark falls back to the fixed window', () => {
  assert.equal(
    computeWindowStart({ watermark: null, nowMs: NOW, fallbackMinutes: 20 }),
    '2026-07-02T11:40:00.000Z',
  );
});

test('malformed watermark falls back to the fixed window', () => {
  assert.equal(
    computeWindowStart({
      watermark: 'not-a-date',
      nowMs: NOW,
      fallbackMinutes: 20,
    }),
    '2026-07-02T11:40:00.000Z',
  );
});

test('watermark resumes from last scan minus the overlap', () => {

  assert.equal(
    computeWindowStart({
      watermark: '2026-07-02T10:26:00.000Z',
      nowMs: NOW,
      fallbackMinutes: 20,
    }),
    '2026-07-02T10:21:00.000Z',
  );
});

test('stale watermark is clamped to the max lookback', () => {
  assert.equal(
    computeWindowStart({
      watermark: '2026-05-01T00:00:00.000Z',
      nowMs: NOW,
      fallbackMinutes: 20,
      maxLookbackDays: 7,
    }),
    '2026-06-25T12:00:00.000Z',
  );
});

test('future-dated watermark is clamped to now', () => {
  assert.equal(
    computeWindowStart({
      watermark: '2026-07-03T12:00:00.000Z',
      nowMs: NOW,
      fallbackMinutes: 20,
      overlapMinutes: 0,
    }),
    '2026-07-02T12:00:00.000Z',
  );
});
